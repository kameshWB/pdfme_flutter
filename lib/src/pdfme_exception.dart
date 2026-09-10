/// Thrown when PDF generation fails.
class PdfmeException implements Exception {
  final String message;
  final String? code;

  const PdfmeException(this.message, {this.code});

  @override
  String toString() =>
      code == null ? 'PdfmeException: $message' : 'PdfmeException ($code): $message';
}
