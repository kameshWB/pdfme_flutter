package com.pdfme.pdfme_flutter

import android.annotation.SuppressLint
import android.content.Context
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.util.Base64
import android.webkit.JavascriptInterface
import android.webkit.WebResourceRequest
import android.webkit.WebSettings
import android.webkit.WebView
import android.webkit.WebViewClient
import org.json.JSONObject
import java.nio.charset.StandardCharsets
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicReference

/**
 * Offscreen WebView host for the bundled pdfme engine.
 * Never attached to a visible UI hierarchy. Network access is blocked.
 */
internal class PdfmeEngine(private val context: Context) {
    private val mainHandler = Handler(Looper.getMainLooper())
    private val lock = Any()

    @Volatile
    private var webView: WebView? = null

    @Volatile
    private var ready = false

    private val readyLatch = AtomicReference<CountDownLatch?>(null)

    fun initialize(timeoutMs: Long = 30_000L) {
        synchronized(lock) {
            if (ready && webView != null) return

            val latch = CountDownLatch(1)
            readyLatch.set(latch)

            runOnMainBlocking {
                destroyUnlocked()
                WebView.setWebContentsDebuggingEnabled(false)
                val view = WebView(context.applicationContext)
                configureWebView(view)
                view.addJavascriptInterface(Bridge(), "PdfmeBridge")
                view.webViewClient =
                    object : WebViewClient() {
                        override fun shouldOverrideUrlLoading(
                            view: WebView?,
                            request: WebResourceRequest?,
                        ): Boolean {
                            val url = request?.url?.toString().orEmpty()
                            return !isAllowedLocalUrl(url)
                        }

                        @Deprecated("Deprecated in Java")
                        override fun shouldOverrideUrlLoading(
                            view: WebView?,
                            url: String?,
                        ): Boolean = !isAllowedLocalUrl(url.orEmpty())

                        override fun onPageFinished(
                            view: WebView?,
                            url: String?,
                        ) {
                            mainHandler.postDelayed({
                                if (!ready) {
                                    ready = true
                                    readyLatch.get()?.countDown()
                                }
                            }, 250)
                        }
                    }

                webView = view
                view.loadUrl("file:///android_asset/pdfme/engine.html")
            }

            val ok = latch.await(timeoutMs, TimeUnit.MILLISECONDS)
            if (!ok) {
                dispose()
                throw PdfmeNativeException(
                    "RUNTIME_INIT_ERROR",
                    "Timed out while initializing the pdfme JavaScript runtime",
                )
            }
            ready = true
        }
    }

    fun generate(
        templateJson: String,
        inputsJson: String,
        optionsJson: String,
        timeoutMs: Long = 120_000L,
    ): ByteArray {
        synchronized(lock) {
            if (!ready || webView == null) {
                initialize()
            }

            val resultLatch = CountDownLatch(1)
            val resultRef = AtomicReference<GenerationResult?>(null)
            val requestId = System.nanoTime().toString()

            pending[requestId] = { result ->
                resultRef.set(result)
                resultLatch.countDown()
            }

            // Pass payload as base64 JSON so template/input bytes are never
            // interpolated into an executable JS string literal.
            val envelope =
                JSONObject()
                    .put("requestId", requestId)
                    .put("templateJson", templateJson)
                    .put("inputsJson", inputsJson)
                    .put("optionsJson", optionsJson)
            val envelopeB64 =
                Base64.encodeToString(
                    envelope.toString().toByteArray(StandardCharsets.UTF_8),
                    Base64.NO_WRAP,
                )
            val script =
                "globalThis.PdfmeMobile.runRequest(${JSONObject.quote(envelopeB64)});"

            runOnMain {
                webView?.evaluateJavascript(script, null)
                    ?: throw PdfmeNativeException("RUNTIME_INIT_ERROR", "WebView is not available")
            }

            val completed = resultLatch.await(timeoutMs, TimeUnit.MILLISECONDS)
            pending.remove(requestId)

            if (!completed) {
                throw PdfmeNativeException(
                    "GENERATION_ERROR",
                    "Timed out while generating PDF",
                )
            }

            val result =
                resultRef.get()
                    ?: throw PdfmeNativeException("GENERATION_ERROR", "Empty generation result")

            if (result.errorCode != null) {
                throw PdfmeNativeException(
                    result.errorCode,
                    result.errorMessage ?: "PDF generation failed",
                )
            }

            val bytes =
                result.pdfBytes
                    ?: throw PdfmeNativeException("GENERATION_ERROR", "Missing PDF bytes")

            if (bytes.size < 5 ||
                bytes[0] != 0x25.toByte() ||
                bytes[1] != 0x50.toByte() ||
                bytes[2] != 0x44.toByte() ||
                bytes[3] != 0x46.toByte()
            ) {
                throw PdfmeNativeException("GENERATION_ERROR", "Generated output is not a valid PDF")
            }

            return bytes
        }
    }

    fun dispose() {
        synchronized(lock) {
            runOnMainBlocking {
                destroyUnlocked()
            }
            ready = false
            pending.clear()
        }
    }

    @SuppressLint("SetJavaScriptEnabled")
    private fun configureWebView(view: WebView) {
        val settings = view.settings
        settings.javaScriptEnabled = true
        settings.domStorageEnabled = false
        settings.databaseEnabled = false
        settings.cacheMode = WebSettings.LOAD_NO_CACHE
        settings.blockNetworkLoads = true
        settings.blockNetworkImage = true
        settings.allowContentAccess = false
        // Required to load bundled file:///android_asset HTML + JS.
        settings.allowFileAccess = true
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.JELLY_BEAN) {
            @Suppress("DEPRECATION")
            settings.allowFileAccessFromFileURLs = false
            @Suppress("DEPRECATION")
            settings.allowUniversalAccessFromFileURLs = false
        }
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.LOLLIPOP) {
            settings.mixedContentMode = WebSettings.MIXED_CONTENT_NEVER_ALLOW
        }
        settings.setSupportZoom(false)
        settings.builtInZoomControls = false
        settings.displayZoomControls = false
        settings.mediaPlaybackRequiresUserGesture = true
        view.setWillNotDraw(true)
    }

    private fun isAllowedLocalUrl(url: String): Boolean {
        if (url.isEmpty() || url == "about:blank") return true
        return url.startsWith("file:///android_asset/")
    }

    private fun destroyUnlocked() {
        webView?.apply {
            stopLoading()
            removeJavascriptInterface("PdfmeBridge")
            loadUrl("about:blank")
            destroy()
        }
        webView = null
        ready = false
    }

    private fun runOnMain(block: () -> Unit) {
        if (Looper.myLooper() == Looper.getMainLooper()) {
            block()
        } else {
            mainHandler.post(block)
        }
    }

    private fun runOnMainBlocking(block: () -> Unit) {
        if (Looper.myLooper() == Looper.getMainLooper()) {
            block()
            return
        }
        val latch = CountDownLatch(1)
        val error = AtomicReference<Throwable?>(null)
        mainHandler.post {
            try {
                block()
            } catch (t: Throwable) {
                error.set(t)
            } finally {
                latch.countDown()
            }
        }
        latch.await(30, TimeUnit.SECONDS)
        error.get()?.let { throw it }
    }

    private inner class Bridge {
        @JavascriptInterface
        fun onReady() {
            ready = true
            readyLatch.get()?.countDown()
        }

        @JavascriptInterface
        fun onResult(
            requestId: String,
            json: String,
        ) {
            val callback = pending.remove(requestId) ?: return
            try {
                val obj = JSONObject(json)
                if (obj.has("error") && !obj.isNull("error")) {
                    val err = obj.getJSONObject("error")
                    callback(
                        GenerationResult(
                            errorCode = err.optString("code", "GENERATION_ERROR"),
                            errorMessage = err.optString("message", "PDF generation failed"),
                        ),
                    )
                } else {
                    val b64 = obj.getString("pdfBase64")
                    val bytes = Base64.decode(b64, Base64.DEFAULT)
                    callback(GenerationResult(pdfBytes = bytes))
                }
            } catch (t: Throwable) {
                callback(
                    GenerationResult(
                        errorCode = "JS_EXECUTION_ERROR",
                        errorMessage = t.message ?: "Failed to parse JS result",
                    ),
                )
            }
        }
    }

    private data class GenerationResult(
        val pdfBytes: ByteArray? = null,
        val errorCode: String? = null,
        val errorMessage: String? = null,
    )

    companion object {
        private val pending =
            java.util.concurrent.ConcurrentHashMap<String, (GenerationResult) -> Unit>()
    }
}

internal class PdfmeNativeException(
    val code: String,
    override val message: String,
) : Exception(message)
