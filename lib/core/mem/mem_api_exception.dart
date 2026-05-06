/// Thrown when the Mem REST API returns a non-success status or malformed JSON.
class MemApiException implements Exception {
  MemApiException(this.message, {this.statusCode, this.requestId});

  final String message;
  final int? statusCode;
  final String? requestId;

  @override
  String toString() =>
      'MemApiException($statusCode): $message${requestId != null ? ' [rid: $requestId]' : ''}';
}
