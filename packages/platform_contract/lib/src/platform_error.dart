enum PlatformErrorCode {
  unavailable,
  permissionDenied,
  invalidArgument,
  internal,
}

final class PlatformCapabilityException implements Exception {
  const PlatformCapabilityException(this.code, this.message, {this.details});

  final PlatformErrorCode code;
  final String message;
  final Map<String, Object?>? details;

  @override
  String toString() => 'PlatformCapabilityException($code): $message';
}
