import 'package:flutter_test/flutter_test.dart';
import 'package:pdfme_flutter/pdfme_flutter.dart';

void main() {
  test('rejects empty inputs', () {
    expect(
      () => PdfmeGenerator.generate(
        template: {
          'basePdf': {'width': 210, 'height': 297, 'padding': [10, 10, 10, 10]},
          'schemas': [<Map<String, dynamic>>[]],
        },
        inputs: const [],
      ),
      throwsA(isA<PdfmeException>()),
    );
  });

  test('PdfmeException toString', () {
    expect(
      const PdfmeException('fail', code: 'X').toString(),
      'PdfmeException (X): fail',
    );
  });
}
