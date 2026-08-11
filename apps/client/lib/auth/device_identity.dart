import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../util/uuid.dart';

abstract interface class DeviceIdentityStore {
  Future<String?> read();

  Future<void> write(String value);
}

final class FlutterSecureDeviceIdentityStore implements DeviceIdentityStore {
  FlutterSecureDeviceIdentityStore({FlutterSecureStorage? storage})
      : _storage = storage ??
            const FlutterSecureStorage(
              aOptions: AndroidOptions(
                resetOnError: false,
                storageNamespace: 'studyflow.device.v1',
              ),
              mOptions: MacOsOptions(
                accessibility: KeychainAccessibility.unlocked_this_device,
                synchronizable: false,
                // Local macOS Debug builds are unsigned; Data Protection
                // Keychain requires a provisioning profile.
                usesDataProtectionKeychain: !kDebugMode,
              ),
            );

  static const _deviceIdKey = 'studyflow.device-id.v1';

  final FlutterSecureStorage _storage;

  @override
  Future<String?> read() => _storage.read(key: _deviceIdKey);

  @override
  Future<void> write(String value) => _storage.write(
        key: _deviceIdKey,
        value: value,
      );
}

final class DeviceIdentity {
  DeviceIdentity({
    required DeviceIdentityStore store,
    String Function()? generate,
  })  : _store = store,
        _generate = generate ?? newUuidV4;

  final DeviceIdentityStore _store;
  final String Function() _generate;
  Future<String>? _identityFuture;

  Future<String> loadOrCreate() => _identityFuture ??= _loadOrCreate();

  Future<String> _loadOrCreate() async {
    final persisted = await _store.read();
    if (persisted != null) {
      return _canonicalUuid(persisted, 'stored device ID');
    }

    final generated = _canonicalUuid(_generate(), 'generated device ID');
    await _store.write(generated);
    final persistedAfterWrite = await _store.read();
    if (persistedAfterWrite != generated) {
      throw const DeviceIdentityException(
        'Secure storage did not preserve the device identity.',
      );
    }
    return generated;
  }
}

final class DeviceIdentityException implements Exception {
  const DeviceIdentityException(this.message, {this.cause});

  final String message;
  final Object? cause;

  @override
  String toString() => 'DeviceIdentityException: $message';
}

String _canonicalUuid(String value, String name) {
  final normalized = value.toLowerCase();
  if (!_uuidPattern.hasMatch(normalized) || normalized != value) {
    throw DeviceIdentityException('$name is not canonical UUID text.');
  }
  return normalized;
}

final RegExp _uuidPattern = RegExp(
  r'^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$',
);
