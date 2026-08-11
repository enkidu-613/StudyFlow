import 'dart:convert';

import 'package:cryptography/cryptography.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

enum StoredKeyName { device, accountData }

abstract interface class SecureKeyStore {
  Future<String?> read({
    required String accountId,
    required StoredKeyName keyName,
  });

  Future<void> write({
    required String accountId,
    required StoredKeyName keyName,
    required String value,
  });
}

abstract interface class PayloadKeyProvider {
  String get accountId;

  Future<SecretKey> loadAccountDataKey();
}

final class AccountDatabaseKey {
  AccountDatabaseKey._({required this.accountId, required SecretKey key})
      : _key = key;

  final String accountId;
  final SecretKey _key;

  Future<List<int>> extractBytes() => _key.extractBytes();
}

class FlutterSecureKeyStore implements SecureKeyStore {
  FlutterSecureKeyStore({FlutterSecureStorage? storage})
      : _storage = storage ??
            const FlutterSecureStorage(
              aOptions: AndroidOptions(
                resetOnError: false,
                storageNamespace: 'studyflow.keys.v1',
              ),
              mOptions: MacOsOptions(
                accessibility: KeychainAccessibility.unlocked_this_device,
                synchronizable: false,
                usesDataProtectionKeychain: true,
              ),
            );

  final FlutterSecureStorage _storage;

  @override
  Future<String?> read({
    required String accountId,
    required StoredKeyName keyName,
  }) =>
      _storage.read(key: _storageKey(accountId, keyName));

  @override
  Future<void> write({
    required String accountId,
    required StoredKeyName keyName,
    required String value,
  }) =>
      _storage.write(key: _storageKey(accountId, keyName), value: value);

  String _storageKey(String accountId, StoredKeyName keyName) =>
      'studyflow.v1.${_normalizedAccountId(accountId)}.${keyName.name}';
}

final class KeyManager implements PayloadKeyProvider {
  KeyManager({
    required String accountId,
    SecureKeyStore? store,
  })  : accountId = _normalizedAccountId(accountId),
        _store = store ?? FlutterSecureKeyStore();

  @override
  final String accountId;
  final SecureKeyStore _store;
  final Cipher _keyAlgorithm = Xchacha20.poly1305Aead();

  static final Map<String, Future<SecretKey>> _accountDataKeyBootstraps =
      <String, Future<SecretKey>>{};

  Future<SecretKey>? _deviceKeyFuture;
  Future<SecretKey>? _accountDataKeyFuture;

  Future<SecretKey> loadOrCreateDeviceKey() =>
      _deviceKeyFuture ??= _loadOrCreate(StoredKeyName.device);

  Future<SecretKey> createAccountDataKey() {
    final inFlight = _accountDataKeyBootstraps[accountId];
    if (inFlight != null) {
      return inFlight;
    }

    late final Future<SecretKey> bootstrap;
    bootstrap = _createAccountDataKeyOnce().whenComplete(() {
      if (identical(_accountDataKeyBootstraps[accountId], bootstrap)) {
        _accountDataKeyBootstraps.remove(accountId);
      }
    });
    _accountDataKeyBootstraps[accountId] = bootstrap;
    return bootstrap;
  }

  Future<SecretKey> _createAccountDataKeyOnce() async {
    if (await _read(StoredKeyName.accountData) != null) {
      throw StateError('The account data key already exists.');
    }

    final generated = await _keyAlgorithm.newSecretKey();
    await _persist(StoredKeyName.accountData, generated);
    final persisted = await _read(StoredKeyName.accountData);
    if (persisted == null ||
        base64Encode(await persisted.extractBytes()) !=
            base64Encode(await generated.extractBytes())) {
      throw const KeyRecoveryException(
        'Secure key storage did not preserve the generated account key.',
      );
    }
    _accountDataKeyFuture = Future<SecretKey>.value(persisted);
    return persisted;
  }

  @override
  Future<SecretKey> loadAccountDataKey() =>
      _accountDataKeyFuture ??= _accountDataKeyBootstraps[accountId] ??
          _loadRequired(StoredKeyName.accountData);

  Future<AccountDatabaseKey> loadDatabaseKey() async {
    final accountDataKey = await loadAccountDataKey();
    final derivedKey =
        await Hkdf(hmac: Hmac.sha256(), outputLength: 32).deriveKey(
      secretKey: accountDataKey,
      nonce: utf8.encode('StudyFlow database key salt v1'),
      info: utf8.encode(accountId),
    );
    return AccountDatabaseKey._(accountId: accountId, key: derivedKey);
  }

  Future<SecretKey> _loadOrCreate(StoredKeyName keyName) async {
    final existing = await _read(keyName);
    if (existing != null) {
      return existing;
    }

    final generated = await _keyAlgorithm.newSecretKey();
    await _persist(keyName, generated);
    return generated;
  }

  Future<SecretKey> _loadRequired(StoredKeyName keyName) async {
    final key = await _read(keyName);
    if (key == null) {
      throw const KeyRecoveryException(
        'The account encryption key is unavailable. Restore the account key '
        'before opening encrypted data.',
      );
    }
    return key;
  }

  Future<SecretKey?> _read(StoredKeyName keyName) async {
    final String? encoded;
    try {
      encoded = await _store.read(accountId: accountId, keyName: keyName);
    } catch (error) {
      throw KeyRecoveryException(
        'Secure key storage is unavailable. Unlock the device and retry.',
        cause: error,
      );
    }
    if (encoded == null) {
      return null;
    }

    try {
      final bytes = base64Decode(encoded);
      if (bytes.length != 32 || base64Encode(bytes) != encoded) {
        throw const FormatException('invalid key material');
      }
      return SecretKey(bytes);
    } on FormatException catch (error) {
      throw KeyRecoveryException(
        'Stored encryption key material is invalid. Restore the account key '
        'instead of creating a replacement.',
        cause: error,
      );
    }
  }

  Future<void> _persist(StoredKeyName keyName, SecretKey key) async {
    final bytes = await key.extractBytes();
    if (bytes.length != 32) {
      throw const KeyRecoveryException(
        'Generated encryption key has an invalid length.',
      );
    }
    try {
      await _store.write(
        accountId: accountId,
        keyName: keyName,
        value: base64Encode(bytes),
      );
    } catch (error) {
      throw KeyRecoveryException(
        'Secure key storage could not persist the encryption key.',
        cause: error,
      );
    }
  }
}

class KeyRecoveryException implements Exception {
  const KeyRecoveryException(this.message, {this.cause});

  final String message;
  final Object? cause;

  @override
  String toString() => 'KeyRecoveryException: $message';
}

String _normalizedAccountId(String accountId) {
  final normalized = accountId.toLowerCase();
  if (!_uuidPattern.hasMatch(normalized)) {
    throw ArgumentError.value(accountId, 'accountId', 'must be a UUID');
  }
  return normalized;
}

final RegExp _uuidPattern = RegExp(
  r'^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$',
);
