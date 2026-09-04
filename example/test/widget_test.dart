import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdfme_flutter_example/main.dart';

void main() {
  testWidgets('shows generate button', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: GeneratePage()));
    expect(find.text('Generate PDF'), findsOneWidget);
  });
}
