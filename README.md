# pdfme_flutter

Generate PDFs **on the device** from [pdfme](https://pdfme.com) Designer templates.

Design the layout once in the pdfme Designer, then fill it with data in Flutter — no PDF server, no Designer UI in your app, no internet required after install.

```dart
final pdfBytes = await PdfmeGenerator.generate(
  template: templateFromDesigner, // Map from Designer JSON
  inputs: [
    {
      'billedToInput': 'Ada Lovelace',
      'info': '{"InvoiceNo":"INV-001","Date":"4 Sep 2026"}',
    },
  ],
);
```

`pdfBytes` is a `Uint8List` you can save, share, or preview.

| Platform | Supported |
|---|---|
| Android | Yes |
| iOS | Yes |
| Web / Desktop | Not yet |

---

## How it works

pdfme’s generator (`@pdfme/generator`) is a **JavaScript** library. Flutter cannot run it as Dart, so this plugin embeds a small offline JS runtime:

```
Your Flutter app
    │  PdfmeGenerator.generate(template, inputs)
    ▼
MethodChannel
    ▼
Android / iOS (offscreen WebView — never shown to the user)
    ▼
Bundled pdfme engine (engine.js)
    ▼
PDF bytes → back to Dart
```

1. You export a **template** from the [pdfme Designer](https://pdfme.com/demo) (JSON with `basePdf` + `schemas`).
2. Your app passes that template plus **inputs** (field values).
3. The plugin loads a bundled copy of pdfme inside a hidden WebView.
4. pdfme renders the PDF locally and returns the bytes.

You do **not** rewrite pdfme in Dart. You do **not** open a browser for the user. Generation stays on-device.

---

## Install

```yaml
dependencies:
  pdfme_flutter: ^0.1.0
```

```bash
flutter pub get
```

---

## Usage

### 1. Design a template

Use the pdfme Designer (web) to lay out text, tables, images, QR codes, etc., then export / copy the template JSON.

### 2. Load it in Flutter

```dart
import 'dart:convert';
import 'package:flutter/services.dart';
import 'package:pdfme_flutter/pdfme_flutter.dart';

final template = jsonDecode(
  await rootBundle.loadString('assets/templates/invoice.json'),
) as Map<String, dynamic>;
```

### 3. Generate

```dart
final inputs = [
  {
    // Keys must match schema `name` values from the Designer.
    'billedToInput': 'Ada Lovelace\nLondon, UK',
    'info': jsonEncode({
      'InvoiceNo': 'INV-1001',
      'Date': '4 September 2026',
    }),
    'orders': jsonEncode([
      ['Widget', '2', '10', '20'],
      ['Gadget', '1', '15', '15'],
    ]),
    'taxInput': jsonEncode({'rate': '18'}),
    'paymentInfoInput': 'Bank transfer due in 14 days',
  },
];

final pdf = await PdfmeGenerator.generate(
  template: template,
  inputs: inputs,
);

// Save or share:
await File('invoice.pdf').writeAsBytes(pdf);
```

Only **editable** fields need values in `inputs`. Read-only labels from the Designer stay in the template.

### Errors

Failures throw `PdfmeException` with a `message` and optional `code` (for example `INVALID_INPUT`, `GENERATION_ERROR`).

---

## Images, fonts, and offline data

- Prefer **`data:` URIs** for images/signatures (not `https://` URLs). Remote URLs are rejected so generation stays offline.
- `basePdf` should be a blank-pdf object or embedded `data:application/pdf;base64,...`, not a remote URL.
- Custom fonts can be embedded via pdfme’s usual `options.font` mechanism when you extend the API later; the bundled engine includes pdfme’s default font path for basic text.

---

## Example app

```bash
cd example
flutter pub get
flutter run
```

The example loads a Designer invoice template and generates a PDF on a simulator/device.

---

## Security notes

- The WebView is **offscreen** and not a user-facing browser.
- Android blocks WebView network loads; iOS blocks `http(s)` navigations/resources.
- The JS layer stubs `fetch` / `XHR` and rejects remote `basePdf` / bare `http(s)` input values.
- Treat templates and inputs as **trusted app data** (same as shipping any JS bundle in your app).

---

## Rebuild the JS engine (maintainers)

```bash
cd js
npm install
npm run build
```

That refreshes `assets/pdfme/`, Android assets, and iOS resources. Keep `js/package-lock.json` committed.

---

## License

MIT. This package bundles [pdfme](https://github.com/pdfme/pdfme) (`@pdfme/generator` and related packages), also MIT.

Not an official pdfme product — a community Flutter bridge so mobile apps can use Designer templates locally.
