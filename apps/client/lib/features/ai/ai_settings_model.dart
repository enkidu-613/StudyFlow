import 'package:flutter_secure_storage/flutter_secure_storage.dart';

final class AiSettings {
  const AiSettings({
    required this.baseUrl,
    required this.model,
    required this.apiKey,
    required this.enabled,
  });

  final String baseUrl;
  final String model;
  final String apiKey;
  final bool enabled;

  static const AiSettings empty = AiSettings(
    baseUrl: '',
    model: '',
    apiKey: '',
    enabled: false,
  );

  AiSettings copyWith({
    String? baseUrl,
    String? model,
    String? apiKey,
    bool? enabled,
  }) =>
      AiSettings(
        baseUrl: baseUrl ?? this.baseUrl,
        model: model ?? this.model,
        apiKey: apiKey ?? this.apiKey,
        enabled: enabled ?? this.enabled,
      );

  bool get isConfigured =>
      baseUrl.isNotEmpty && model.isNotEmpty && apiKey.isNotEmpty;

  @override
  String toString() =>
      'AiSettings(baseUrl: $baseUrl, model: $model, '
      'apiKey: <redacted>, enabled: $enabled)';
}

abstract interface class AiSettingsStore {
  Future<AiSettings> read();

  Future<void> write(AiSettings settings);

  Future<void> clear();
}

final class SecureAiSettingsStore implements AiSettingsStore {
  SecureAiSettingsStore({FlutterSecureStorage? storage})
      : _storage = storage ??
            const FlutterSecureStorage(
              aOptions: AndroidOptions(
                resetOnError: false,
                storageNamespace: 'studyflow.ai.v1',
              ),
              mOptions: MacOsOptions(
                accessibility: KeychainAccessibility.unlocked_this_device,
                synchronizable: false,
                usesDataProtectionKeychain: false,
              ),
            );

  static const _baseUrlKey = 'studyflow.ai.base-url.v1';
  static const _modelKey = 'studyflow.ai.model.v1';
  static const _apiKeyKey = 'studyflow.ai.api-key.v1';
  static const _enabledKey = 'studyflow.ai.enabled.v1';

  final FlutterSecureStorage _storage;

  @override
  Future<AiSettings> read() async {
    final baseUrl = await _storage.read(key: _baseUrlKey);
    final model = await _storage.read(key: _modelKey);
    final apiKey = await _storage.read(key: _apiKeyKey);
    final enabledValue = await _storage.read(key: _enabledKey);
    return AiSettings(
      baseUrl: baseUrl ?? '',
      model: model ?? '',
      apiKey: apiKey ?? '',
      enabled: enabledValue == 'true',
    );
  }

  @override
  Future<void> write(AiSettings settings) async {
    await _storage.write(key: _baseUrlKey, value: settings.baseUrl);
    await _storage.write(key: _modelKey, value: settings.model);
    await _storage.write(key: _apiKeyKey, value: settings.apiKey);
    await _storage.write(key: _enabledKey, value: '${settings.enabled}');
  }

  @override
  Future<void> clear() async {
    await _storage.delete(key: _baseUrlKey);
    await _storage.delete(key: _modelKey);
    await _storage.delete(key: _apiKeyKey);
    await _storage.delete(key: _enabledKey);
  }
}

String? validateAiBaseUrl(String? value) {
  final trimmed = value?.trim() ?? '';
  if (trimmed.isEmpty) {
    return 'Base URL is required';
  }
  final uri = Uri.tryParse(trimmed);
  if (uri == null || uri.host.isEmpty) {
    return 'Enter a valid URL';
  }
  final isLoopback =
      uri.host == 'localhost' || uri.host == '127.0.0.1' || uri.host == '::1';
  if (uri.scheme != 'https' && !(uri.scheme == 'http' && isLoopback)) {
    return 'Base URL must use HTTPS';
  }
  return null;
}
