import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pdfme_flutter/pdfme_flutter.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const MaterialApp(home: GeneratePage()));
}

class GeneratePage extends StatefulWidget {
  const GeneratePage({super.key});

  @override
  State<GeneratePage> createState() => _GeneratePageState();
}

class _GeneratePageState extends State<GeneratePage> {
  String _status = 'Tap generate';
  bool _busy = false;

  Future<void> _generate() async {
    setState(() {
      _busy = true;
      _status = 'Generating…';
    });

    try {
      final templateJson =
          await rootBundle.loadString('assets/templates/invoice.json');
      final template =
          jsonDecode(templateJson) as Map<String, dynamic>;

      // Editable fields from the Designer template (read-only labels stay in template).
      final inputs = [
        {
          'billedToInput':
              'Kamesh Adadadi\n+91-98765-43210\n12 MG Road, Bengaluru, KA, India 560001',
          'info': jsonEncode({
            'InvoiceNo': 'INV-7842',
            'Date': '4 September 2026',
          }),
          'orders': jsonEncode([
            ['Wireless Mouse', '2', '899', '1798'],
            ['USB-C Hub', '1', '2499', '2499'],
            ['Laptop Sleeve', '1', '1299', '1299'],
          ]),
          'taxInput': jsonEncode({'rate': '18'}),
          'paymentInfoInput':
              'HDFC Bank\nAccount Name: Kamesh Adadadi\nAccount No.: 50100-234-5678\nPay by: 18 September 2026',
        },
      ];

      final pdfBytes = await PdfmeGenerator.generate(
        template: template,
        inputs: inputs,
      );

      final dir = await getApplicationDocumentsDirectory();
      final file = File('${dir.path}/output.pdf');
      await file.writeAsBytes(pdfBytes, flush: true);

      setState(() => _status = 'Saved: ${file.path}');
    } on PdfmeException catch (e) {
      setState(() => _status = '$e');
    } catch (e) {
      setState(() => _status = 'Error: $e');
    } finally {
      setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('pdfme_flutter')),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            FilledButton(
              onPressed: _busy ? null : _generate,
              child: Text(_busy ? 'Generating…' : 'Generate PDF'),
            ),
            const SizedBox(height: 16),
            SelectableText(_status),
          ],
        ),
      ),
    );
  }
}
