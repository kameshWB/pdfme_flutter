import Flutter
import UIKit

public class PdfmeFlutterPlugin: NSObject, FlutterPlugin {
  private let engine = PdfmeEngine()
  private let serial = DispatchQueue(label: "com.pdfme.pdfme_flutter.engine")

  public static func register(with registrar: FlutterPluginRegistrar) {
    let channel = FlutterMethodChannel(name: "pdfme_flutter", binaryMessenger: registrar.messenger())
    let instance = PdfmeFlutterPlugin()
    registrar.addMethodCallDelegate(instance, channel: channel)
  }

  public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "initialize":
      Task {
        do {
          try await engine.initialize()
          DispatchQueue.main.async { result(nil) }
        } catch let error as PdfmeNativeError {
          DispatchQueue.main.async { result(FlutterError(code: error.code, message: error.message, details: nil)) }
        } catch {
          DispatchQueue.main.async {
            result(FlutterError(code: "RUNTIME_INIT_ERROR", message: error.localizedDescription, details: nil))
          }
        }
      }
    case "generate":
      guard
        let args = call.arguments as? [String: Any],
        let templateJson = args["templateJson"] as? String,
        let inputsJson = args["inputsJson"] as? String
      else {
        result(FlutterError(code: "INVALID_INPUT", message: "templateJson and inputsJson are required", details: nil))
        return
      }
      let optionsJson = (args["optionsJson"] as? String) ?? "{}"
      Task {
        do {
          let data = try await engine.generate(
            templateJson: templateJson,
            inputsJson: inputsJson,
            optionsJson: optionsJson
          )
          DispatchQueue.main.async { result(data) }
        } catch let error as PdfmeNativeError {
          DispatchQueue.main.async { result(FlutterError(code: error.code, message: error.message, details: nil)) }
        } catch {
          DispatchQueue.main.async {
            result(FlutterError(code: "GENERATION_ERROR", message: error.localizedDescription, details: nil))
          }
        }
      }
    case "dispose":
      engine.dispose()
      result(nil)
    case "getPlatformVersion":
      result("iOS " + UIDevice.current.systemVersion)
    default:
      result(FlutterMethodNotImplemented)
    }
  }
}
