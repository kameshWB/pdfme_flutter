package com.pdfme.pdfme_flutter

import android.os.Handler
import android.os.Looper
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.MethodChannel.MethodCallHandler
import io.flutter.plugin.common.MethodChannel.Result
import java.util.concurrent.Executors

/** PdfmeFlutterPlugin — bridges Dart to the offscreen pdfme JS engine. */
class PdfmeFlutterPlugin :
    FlutterPlugin,
    MethodCallHandler {
    private lateinit var channel: MethodChannel
    private var engine: PdfmeEngine? = null
    private val executor = Executors.newSingleThreadExecutor()
    private val mainHandler = Handler(Looper.getMainLooper())

    override fun onAttachedToEngine(flutterPluginBinding: FlutterPlugin.FlutterPluginBinding) {
        channel = MethodChannel(flutterPluginBinding.binaryMessenger, "pdfme_flutter")
        channel.setMethodCallHandler(this)
        engine = PdfmeEngine(flutterPluginBinding.applicationContext)
    }

    override fun onMethodCall(
        call: MethodCall,
        result: Result,
    ) {
        when (call.method) {
            "initialize" -> {
                executor.execute {
                    try {
                        engine?.initialize()
                            ?: throw PdfmeNativeException("RUNTIME_INIT_ERROR", "Engine missing")
                        mainHandler.post { result.success(null) }
                    } catch (e: PdfmeNativeException) {
                        mainHandler.post { result.error(e.code, e.message, null) }
                    } catch (t: Throwable) {
                        mainHandler.post {
                            result.error("RUNTIME_INIT_ERROR", t.message, null)
                        }
                    }
                }
            }
            "generate" -> {
                val templateJson = call.argument<String>("templateJson")
                val inputsJson = call.argument<String>("inputsJson")
                val optionsJson = call.argument<String>("optionsJson") ?: "{}"
                if (templateJson.isNullOrEmpty() || inputsJson.isNullOrEmpty()) {
                    result.error("INVALID_INPUT", "templateJson and inputsJson are required", null)
                    return
                }
                executor.execute {
                    try {
                        val bytes =
                            engine?.generate(templateJson, inputsJson, optionsJson)
                                ?: throw PdfmeNativeException("RUNTIME_INIT_ERROR", "Engine missing")
                        mainHandler.post { result.success(bytes) }
                    } catch (e: PdfmeNativeException) {
                        mainHandler.post { result.error(e.code, e.message, null) }
                    } catch (t: Throwable) {
                        mainHandler.post {
                            result.error("GENERATION_ERROR", t.message, null)
                        }
                    }
                }
            }
            "dispose" -> {
                executor.execute {
                    try {
                        engine?.dispose()
                        mainHandler.post { result.success(null) }
                    } catch (t: Throwable) {
                        mainHandler.post {
                            result.error("RUNTIME_INIT_ERROR", t.message, null)
                        }
                    }
                }
            }
            "getPlatformVersion" -> result.success("Android ${android.os.Build.VERSION.RELEASE}")
            else -> result.notImplemented()
        }
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        channel.setMethodCallHandler(null)
        executor.execute {
            engine?.dispose()
            engine = null
        }
        executor.shutdown()
    }
}
