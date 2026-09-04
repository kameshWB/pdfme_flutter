# Architecture (internal)

```
PdfmeGenerator.generate(template, inputs)
  → MethodChannel
  → Android WebView / iOS WKWebView (offscreen, network blocked)
  → bundled @pdfme/generator
  → PDF bytes
```

Headless WebView is required because pdfme barcode/signature rendering uses canvas.

Native hosts pass a base64 JSON envelope into `PdfmeMobile.runRequest(...)` so template/input data is not interpolated into executable JavaScript source.

Rebuild JS with `cd js && npm install && npm run build`. See [doc/ARCHITECTURE.md](doc/ARCHITECTURE.md).
