# pdfme_flutter

Generate PDFs in Flutter from pdfme Designer templates (on-device, no server).

```dart
final pdf = await PdfmeGenerator.generate(
  template: templateFromDesigner,
  inputs: [
    {'billedToInput': 'Kamesh', /* field values from your template */},
  ],
);
```

## Run the example

```bash
cd example
flutter pub get
flutter run
```

## Rebuild the JS engine (only if you change `js/`)

```bash
cd js
npm install
npm run build
```

Keep `js/package-lock.json` committed so engine rebuilds stay reproducible.

## Security notes

- Generation runs in an **offscreen** WebView. It is not shown to users.
- Android blocks network loads on the WebView. iOS blocks `http(s)` via content rules and navigation policy.
- The JS runtime stubs `fetch` / `XMLHttpRequest` and rejects remote `basePdf` or input values that are bare `http(s)` URLs.
- Treat Designer templates and inputs as **trusted app data**. Do not feed untrusted user-controlled HTML/JS into the template.
- The bundled `engine.js` is a minified build of pdfme; rebuild from `js/` when updating dependencies.
