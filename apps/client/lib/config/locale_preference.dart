import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Persisted language preference. `null` means follow the system locale.
abstract interface class LocalePreferenceStore {
  Future<String?> read();

  Future<void> write(String? localeTag);

  Future<void> clear();
}

final class SecureLocalePreferenceStore implements LocalePreferenceStore {
  SecureLocalePreferenceStore({FlutterSecureStorage? storage})
      : _storage = storage ??
            const FlutterSecureStorage(
              aOptions: AndroidOptions(
                resetOnError: false,
                storageNamespace: 'studyflow.ui.v1',
              ),
              mOptions: MacOsOptions(
                accessibility: KeychainAccessibility.unlocked_this_device,
                synchronizable: false,
                usesDataProtectionKeychain: false,
              ),
            );

  static const _localeKey = 'studyflow.ui.locale.v1';

  final FlutterSecureStorage _storage;

  @override
  Future<String?> read() => _storage.read(key: _localeKey);

  @override
  Future<void> write(String? localeTag) => localeTag == null
      ? _storage.delete(key: _localeKey)
      : _storage.write(key: _localeKey, value: localeTag);

  @override
  Future<void> clear() => _storage.delete(key: _localeKey);
}
