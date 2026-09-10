import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdfme_flutter/pdfme_flutter.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('pdfme_flutter');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  late List<MethodCall> calls;

  setUp(() {
    calls = <MethodCall>[];
    messenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      if (call.method == 'initialize') {
        return null;
      }
      if (call.method == 'generate') {
        return Uint8List.fromList('%PDF-1.4'.codeUnits);
      }
      return null;
    });
  });

  tearDown(() {
    messenger.setMockMethodCallHandler(channel, null);
  });

  test('rejects empty inputs', () {
    expect(
      () => PdfmeGenerator.generate(
        template: {
          'basePdf': {
            'width': 210,
            'height': 297,
            'padding': [10, 10, 10, 10],
          },
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

  test('defaults optionsJson to an empty object', () async {
    await PdfmeGenerator.generate(
      template: {
        'basePdf': {
          'width': 210,
          'height': 297,
          'padding': [10, 10, 10, 10],
        },
        'schemas': [<Map<String, dynamic>>[]],
      },
      inputs: const [
        {'customerName': 'Ada'},
      ],
    );

    final generateCall = calls.firstWhere((call) => call.method == 'generate');
    final args = generateCall.arguments as Map<dynamic, dynamic>;
    expect(jsonDecode(args['optionsJson'] as String), <String, dynamic>{});
  });

  test('encodes font options as optionsJson', () async {
    const fontUri = 'data:font/ttf;base64,AA==';

    await PdfmeGenerator.generate(
      template: {
        'basePdf': {
          'width': 210,
          'height': 297,
          'padding': [10, 10, 10, 10],
        },
        'schemas': [<Map<String, dynamic>>[]],
      },
      inputs: const [
        {'customerName': 'Ada'},
      ],
      options: {
        'font': {
          'NotoSans': {'data': fontUri, 'fallback': true},
        },
      },
    );

    final generateCall = calls.firstWhere((call) => call.method == 'generate');
    final args = generateCall.arguments as Map<dynamic, dynamic>;
    expect(jsonDecode(args['optionsJson'] as String), {
      'font': {
        'NotoSans': {'data': fontUri, 'fallback': true},
      },
    });
  });
}
