import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:pdfme_flutter/pdfme_flutter.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('generate returns a PDF', (tester) async {
    final pdf = await PdfmeGenerator.generate(
      template: {
        'basePdf': {
          'width': 210,
          'height': 297,
          'padding': [20, 20, 20, 20],
        },
        'schemas': [
          [
            {
              'name': 'customerName',
              'type': 'text',
              'position': {'x': 20, 'y': 30},
              'width': 100,
              'height': 10,
            },
          ],
        ],
      },
      inputs: [
        {'customerName': 'John Doe'},
      ],
    );

    expect(pdf.length, greaterThan(100));
    expect(String.fromCharCodes(pdf.take(4)), '%PDF');
  });
}
