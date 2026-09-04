import Flutter
import UIKit
import WebKit

/// Offscreen WKWebView host for the bundled pdfme engine.
/// Network navigations and http(s) resource loads are blocked.
final class PdfmeEngine: NSObject, WKScriptMessageHandler, WKNavigationDelegate {
  private var webView: WKWebView?
  private let lock = NSLock()
  private var ready = false
  private var readyContinuations: [CheckedContinuation<Void, Error>] = []
  private var pending: [String: CheckedContinuation<[UInt8], Error>] = [:]
  private var contentRulesInstalled = false

  func initialize(timeoutSeconds: TimeInterval = 30) async throws {
    try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
      lock.lock()
      if ready, webView != nil {
        lock.unlock()
        cont.resume()
        return
      }
      readyContinuations.append(cont)
      let needsCreate = webView == nil
      lock.unlock()

      if needsCreate {
        DispatchQueue.main.async {
          self.createWebView()
        }
      }

      DispatchQueue.global().asyncAfter(deadline: .now() + timeoutSeconds) {
        self.lock.lock()
        guard !self.ready else {
          self.lock.unlock()
          return
        }
        let waiting = self.readyContinuations
        self.readyContinuations.removeAll()
        self.lock.unlock()
        for c in waiting {
          c.resume(throwing: PdfmeNativeError(code: "RUNTIME_INIT_ERROR", message: "Timed out while initializing the pdfme JavaScript runtime"))
        }
      }
    }
  }

  func generate(templateJson: String, inputsJson: String, optionsJson: String, timeoutSeconds: TimeInterval = 120) async throws -> FlutterStandardTypedData {
    try await initialize()

    let requestId = UUID().uuidString
    let bytes: [UInt8] = try await withCheckedThrowingContinuation { cont in
      self.lock.lock()
      self.pending[requestId] = cont
      self.lock.unlock()

      let envelope: [String: String] = [
        "requestId": requestId,
        "templateJson": templateJson,
        "inputsJson": inputsJson,
        "optionsJson": optionsJson,
      ]
      guard let envelopeData = try? JSONSerialization.data(withJSONObject: envelope, options: [])
      else {
        self.failPending(requestId: requestId, code: "INVALID_INPUT", message: "Failed to encode generation payload")
        return
      }
      let envelopeB64 = envelopeData.base64EncodedString()

      let script = "globalThis.PdfmeMobile.runRequest(\(Self.jsString(envelopeB64)));"

      DispatchQueue.main.async {
        self.webView?.evaluateJavaScript(script, completionHandler: { _, error in
          if let error = error {
            self.failPending(requestId: requestId, code: "JS_EXECUTION_ERROR", message: error.localizedDescription)
          }
        })
      }

      DispatchQueue.global().asyncAfter(deadline: .now() + timeoutSeconds) {
        self.failPending(requestId: requestId, code: "GENERATION_ERROR", message: "Timed out while generating PDF")
      }
    }

    if bytes.count < 5 || bytes[0] != 0x25 || bytes[1] != 0x50 || bytes[2] != 0x44 || bytes[3] != 0x46 {
      throw PdfmeNativeError(code: "GENERATION_ERROR", message: "Generated output is not a valid PDF")
    }

    return FlutterStandardTypedData(bytes: Data(bytes))
  }

  func dispose() {
    lock.lock()
    ready = false
    contentRulesInstalled = false
    let waitingReady = readyContinuations
    readyContinuations.removeAll()
    let waitingGen = pending
    pending.removeAll()
    lock.unlock()

    for c in waitingReady {
      c.resume(throwing: PdfmeNativeError(code: "RUNTIME_INIT_ERROR", message: "Engine disposed"))
    }
    for (_, c) in waitingGen {
      c.resume(throwing: PdfmeNativeError(code: "RUNTIME_INIT_ERROR", message: "Engine disposed"))
    }

    DispatchQueue.main.async {
      self.webView?.configuration.userContentController.removeScriptMessageHandler(forName: "PdfmeBridge")
      self.webView?.configuration.userContentController.removeAllContentRuleLists()
      self.webView?.stopLoading()
      self.webView?.navigationDelegate = nil
      self.webView = nil
    }
  }

  // MARK: - Private

  private func createWebView() {
    let config = WKWebViewConfiguration()
    config.websiteDataStore = .nonPersistent()
    config.suppressesIncrementalRendering = true
    config.preferences.javaScriptEnabled = true
    if #available(iOS 14.0, *) {
      config.defaultWebpagePreferences.allowsContentJavaScript = true
    }

    let controller = WKUserContentController()
    controller.add(self, name: "PdfmeBridge")
    config.userContentController = controller

    let view = WKWebView(frame: .zero, configuration: config)
    view.isHidden = true
    view.navigationDelegate = self
    webView = view

    installNetworkBlockRules(on: controller) { [weak self] in
      guard let self else { return }
      if let url = Self.engineHtmlURL() {
        view.loadFileURL(url, allowingReadAccessTo: url.deletingLastPathComponent())
      } else {
        self.markReadyFailed(PdfmeNativeError(code: "RUNTIME_INIT_ERROR", message: "Bundled engine.html not found"))
      }
    }
  }

  private func installNetworkBlockRules(on controller: WKUserContentController, completion: @escaping () -> Void) {
    // Block http/https resource loads at the WebKit content-filter layer.
    let rules = """
    [
      {
        "trigger": { "url-filter": "^https?://.*" },
        "action": { "type": "block" }
      }
    ]
    """
    WKContentRuleListStore.default().compileContentRuleList(
      forIdentifier: "pdfme_flutter_block_network",
      encodedContentRuleList: rules
    ) { list, error in
      DispatchQueue.main.async {
        if let list {
          controller.add(list)
          self.contentRulesInstalled = true
        } else if let error {
          // Continue without rules; navigation delegate + JS fetch stub still apply.
          NSLog("pdfme_flutter: content rules unavailable: \(error.localizedDescription)")
        }
        completion()
      }
    }
  }

  private func markReady() {
    lock.lock()
    ready = true
    let waiting = readyContinuations
    readyContinuations.removeAll()
    lock.unlock()
    for c in waiting {
      c.resume()
    }
  }

  private func markReadyFailed(_ error: Error) {
    lock.lock()
    let waiting = readyContinuations
    readyContinuations.removeAll()
    lock.unlock()
    for c in waiting {
      c.resume(throwing: error)
    }
  }

  private func failPending(requestId: String, code: String, message: String) {
    lock.lock()
    let cont = pending.removeValue(forKey: requestId)
    lock.unlock()
    cont?.resume(throwing: PdfmeNativeError(code: code, message: message))
  }

  func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
    guard message.name == "PdfmeBridge" else { return }
    guard let body = message.body as? [String: Any], let type = body["type"] as? String else { return }

    if type == "ready" {
      markReady()
      return
    }

    guard type == "result",
          let requestId = body["requestId"] as? String,
          let payload = body["payload"] as? [String: Any]
    else { return }

    lock.lock()
    let cont = pending.removeValue(forKey: requestId)
    lock.unlock()
    guard let cont else { return }

    if let error = payload["error"] as? [String: Any] {
      let code = (error["code"] as? String) ?? "GENERATION_ERROR"
      let message = (error["message"] as? String) ?? "PDF generation failed"
      cont.resume(throwing: PdfmeNativeError(code: code, message: message))
      return
    }

    guard let b64 = payload["pdfBase64"] as? String,
          let data = Data(base64Encoded: b64)
    else {
      cont.resume(throwing: PdfmeNativeError(code: "GENERATION_ERROR", message: "Missing PDF bytes"))
      return
    }

    cont.resume(returning: [UInt8](data))
  }

  func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
    guard let url = navigationAction.request.url else {
      decisionHandler(.cancel)
      return
    }
    if url.isFileURL || url.absoluteString == "about:blank" {
      decisionHandler(.allow)
      return
    }
    decisionHandler(.cancel)
  }

  func webView(_ webView: WKWebView, decidePolicyFor navigationResponse: WKNavigationResponse, decisionHandler: @escaping (WKNavigationResponsePolicy) -> Void) {
    guard let url = navigationResponse.response.url else {
      decisionHandler(.cancel)
      return
    }
    if url.isFileURL || url.absoluteString == "about:blank" {
      decisionHandler(.allow)
      return
    }
    decisionHandler(.cancel)
  }

  func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
      self.lock.lock()
      let already = self.ready
      self.lock.unlock()
      if !already {
        self.markReady()
      }
    }
  }

  func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
    markReadyFailed(PdfmeNativeError(code: "RUNTIME_INIT_ERROR", message: error.localizedDescription))
  }

  func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
    markReadyFailed(PdfmeNativeError(code: "RUNTIME_INIT_ERROR", message: error.localizedDescription))
  }

  /// Escapes a Swift string as a JavaScript string literal.
  private static func jsString(_ value: String) -> String {
    let data = try! JSONSerialization.data(withJSONObject: [value], options: [])
    let wrapped = String(data: data, encoding: .utf8) ?? "[\"\"]"
    return String(wrapped.dropFirst().dropLast())
  }

  private static func engineHtmlURL() -> URL? {
    #if SWIFT_PACKAGE
    if let url = Bundle.module.url(forResource: "engine", withExtension: "html") {
      return url
    }
    #endif
    if let bundleURL = Bundle(for: PdfmeEngine.self).url(forResource: "pdfme_flutter_resources", withExtension: "bundle"),
       let bundle = Bundle(url: bundleURL),
       let url = bundle.url(forResource: "engine", withExtension: "html") {
      return url
    }
    return Bundle(for: PdfmeEngine.self).url(forResource: "engine", withExtension: "html")
  }
}

struct PdfmeNativeError: Error {
  let code: String
  let message: String
}
