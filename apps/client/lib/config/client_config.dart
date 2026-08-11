final class ClientConfig {
  const ClientConfig._(this.apiBaseUri);

  factory ClientConfig.fromValue(String value) {
    final trimmed = value.trim();
    if (trimmed.isEmpty) {
      return const ClientConfig._(null);
    }
    final uri = Uri.tryParse(trimmed);
    if (uri == null || uri.host.isEmpty || uri.hasQuery || uri.hasFragment) {
      throw ArgumentError.value(value, 'apiBaseUrl', 'must be an origin URI');
    }
    final isLoopback =
        uri.host == 'localhost' || uri.host == '127.0.0.1' || uri.host == '::1';
    if (uri.scheme != 'https' && !(uri.scheme == 'http' && isLoopback)) {
      throw ArgumentError.value(
        value,
        'apiBaseUrl',
        'must use HTTPS unless it is a loopback development URL',
      );
    }
    return ClientConfig._(uri);
  }

  static ClientConfig fromDartDefines() =>
      ClientConfig.fromValue(_apiBaseUrlDefine);

  final Uri? apiBaseUri;

  static const _apiBaseUrlDefine = String.fromEnvironment(
    'STUDYFLOW_API_BASE_URL',
  );
}
