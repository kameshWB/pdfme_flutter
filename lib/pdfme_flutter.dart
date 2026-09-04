import 'dart:convert';

import 'package:flutter/services.dart';

import 'src/pdfme_exception.dart';

export 'src/pdfme_exception.dart';

/// Generates PDFs locally using the bundled pdfme engine.
///
/// ```dart
/// final pdf = await PdfmeGenerator.generate(
///   template: templateFromDesigner,
///   inputs: [{'customerName': 'John Doe'}],
/// );
/// ```
class PdfmeGenerator {
  PdfmeGenerator._();

  static const MethodChannel _channel = MethodChannel('pdfme_flutter');
  static Future<void>? _initFuture;

  /// Generates a PDF from a pdfme [template] and [inputs].
  ///
  /// [template] is the JSON map exported from the pdfme Designer
  /// (`basePdf` + `schemas`). [inputs] is a non-empty list of field values.
  ///
  /// Returns PDF bytes.
  static Future<Uint8List> generate({
    required Map<String, dynamic> template,
    required List<Map<String, dynamic>> inputs,
  }) async {
    if (inputs.isEmpty) {
      throw const PdfmeException(
        'inputs must contain at least one object',
        code: 'INVALID_INPUT',
      );
    }

    await (_initFuture ??= _initialize());

    try {
      final result = await _channel.invokeMethod<dynamic>('generate', {
        'templateJson': jsonEncode(template),
        'inputsJson': jsonEncode(inputs),
        'optionsJson': '{}',
      });

      final bytes = switch (result) {
        final Uint8List b => b,
        final List<int> list => Uint8List.fromList(list),
        _ => throw const PdfmeException(
            'Native bridge returned unexpected PDF payload',
            code: 'GENERATION_ERROR',
          ),
      };

      if (bytes.length < 5 ||
          bytes[0] != 0x25 ||
          bytes[1] != 0x50 ||
          bytes[2] != 0x44 ||
          bytes[3] != 0x46) {
        throw const PdfmeException(
          'Generated output is not a valid PDF',
          code: 'GENERATION_ERROR',
        );
      }

      return bytes;
    } on PdfmeException {
      rethrow;
    } on PlatformException catch (e) {
      throw PdfmeException(
        e.message ?? 'PDF generation failed',
        code: e.code.isEmpty ? 'GENERATION_ERROR' : e.code,
      );
    } catch (e) {
      throw PdfmeException(
        'PDF generation failed: $e',
        code: 'GENERATION_ERROR',
      );
    }
  }

  static Future<void> _initialize() async {
    try {
      await _channel.invokeMethod<void>('initialize');
    } on PlatformException catch (e) {
      _initFuture = null;
      throw PdfmeException(
        e.message ?? 'Failed to initialize pdfme runtime',
        code: e.code.isEmpty ? 'RUNTIME_INIT_ERROR' : e.code,
      );
    } catch (e) {
      _initFuture = null;
      throw PdfmeException(
        'Failed to initialize pdfme runtime: $e',
        code: 'RUNTIME_INIT_ERROR',
      );
    }
  }
}
