import 'dart:convert';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';

import '../security/key_manager.dart';

final class DeviceEnrollmentCrypto {
  DeviceEnrollmentCrypto({
    required String accountId,
    required SecureKeyStore store,
  })  : accountId = _normalizedUuid(accountId, 'accountId'),
        _store = store;

  final String accountId;
  final SecureKeyStore _store;
  final X25519 _keyExchange = X25519();
  final Cipher _cipher = Xchacha20.poly1305Aead();
  final Hkdf _keyDerivation = Hkdf(hmac: Hmac.sha256(), outputLength: 32);
  Future<SimpleKeyPair>? _keyPairFuture;

  Future<String> publicKeyBase64() async {
    final publicKey = await (await _loadOrCreateKeyPair()).extractPublicKey();
    return base64Encode(publicKey.bytes);
  }

  Future<String> sealAccountDataKey({
    required SecretKey accountDataKey,
    required String targetDeviceId,
    required String targetDevicePublicKey,
  }) async {
    final normalizedTargetDeviceId =
        _normalizedUuid(targetDeviceId, 'targetDeviceId');
    final targetPublicKey = _decodePublicKey(targetDevicePublicKey);
    final sourceKeyPair = await _loadOrCreateKeyPair();
    final sourcePublicKey = await sourceKeyPair.extractPublicKey();
    final envelopeKey = await _deriveEnvelopeKey(
      keyPair: sourceKeyPair,
      remotePublicKey: targetPublicKey,
      targetDeviceId: normalizedTargetDeviceId,
    );
    final associatedData = _associatedData(normalizedTargetDeviceId);
    final accountDataKeyBytes = Uint8List.fromList(
      await accountDataKey.extractBytes(),
    );
    if (accountDataKeyBytes.length != 32) {
      accountDataKeyBytes.fillRange(0, accountDataKeyBytes.length, 0);
      throw const DeviceEnrollmentException(
        'The account data key has an invalid length.',
      );
    }
    try {
      final secretBox = await _cipher.encrypt(
        accountDataKeyBytes,
        secretKey: envelopeKey,
        aad: associatedData,
      );
      final envelopeJson = <String, Object?>{
        'version': 1,
        'source_public_key': base64Encode(sourcePublicKey.bytes),
        'nonce': base64Encode(secretBox.nonce),
        'ciphertext': base64Encode(<int>[
          ...secretBox.cipherText,
          ...secretBox.mac.bytes,
        ]),
      };
      return base64Encode(utf8.encode(jsonEncode(envelopeJson)));
    } finally {
      accountDataKeyBytes.fillRange(0, accountDataKeyBytes.length, 0);
    }
  }

  Future<SecretKey> openAccountDataKeyEnvelope(
    String encodedEnvelope, {
    required String targetDeviceId,
  }) async {
    final normalizedTargetDeviceId =
        _normalizedUuid(targetDeviceId, 'targetDeviceId');
    final envelope = _decodeEnvelope(encodedEnvelope);
    final sourcePublicKey = _decodePublicKey(
      _requiredString(envelope, 'source_public_key'),
    );
    final ciphertextAndMac =
        base64Decode(_requiredString(envelope, 'ciphertext'));
    if (ciphertextAndMac.length != 48) {
      throw const FormatException(
          'Enrollment envelope has an invalid ciphertext.');
    }
    final envelopeKey = await _deriveEnvelopeKey(
      keyPair: await _loadOrCreateKeyPair(),
      remotePublicKey: sourcePublicKey,
      targetDeviceId: normalizedTargetDeviceId,
    );
    final plaintext = await _cipher.decrypt(
      SecretBox(
        ciphertextAndMac.sublist(0, 32),
        nonce: base64Decode(_requiredString(envelope, 'nonce')),
        mac: Mac(ciphertextAndMac.sublist(32)),
      ),
      secretKey: envelopeKey,
      aad: _associatedData(normalizedTargetDeviceId),
    );
    if (plaintext.length != 32) {
      throw const DeviceEnrollmentException(
        'Enrollment envelope did not contain a valid account data key.',
      );
    }
    return SecretKey(plaintext);
  }

  Future<SecretKey> _deriveEnvelopeKey({
    required SimpleKeyPair keyPair,
    required SimplePublicKey remotePublicKey,
    required String targetDeviceId,
  }) async {
    try {
      final sharedSecret = await _keyExchange.sharedSecretKey(
        keyPair: keyPair,
        remotePublicKey: remotePublicKey,
      );
      final sharedSecretBytes = Uint8List.fromList(
        await sharedSecret.extractBytes(),
      );
      try {
        var nonZeroAccumulator = 0;
        for (final byte in sharedSecretBytes) {
          nonZeroAccumulator |= byte;
        }
        if (sharedSecretBytes.length != 32 || nonZeroAccumulator == 0) {
          throw const DeviceEnrollmentException(
            'Device public key produced an invalid shared secret.',
          );
        }
        return await _keyDerivation.deriveKey(
          secretKey: SecretKey(sharedSecretBytes),
          nonce: utf8.encode('$accountId\u0000$targetDeviceId'),
          info: utf8.encode('studyflow-device-envelope-v1'),
        );
      } finally {
        sharedSecretBytes.fillRange(0, sharedSecretBytes.length, 0);
        sharedSecret.destroy();
      }
    } on DeviceEnrollmentException {
      rethrow;
    } on Object catch (error) {
      throw DeviceEnrollmentException(
        'Device public key exchange failed.',
        cause: error,
      );
    }
  }

  List<int> _associatedData(String targetDeviceId) => utf8.encode(
        jsonEncode(<String, Object?>{
          'version': 1,
          'account_id': accountId,
          'target_device_id': targetDeviceId,
        }),
      );

  Future<SimpleKeyPair> _loadOrCreateKeyPair() =>
      _keyPairFuture ??= _loadOrCreateKeyPairOnce();

  Future<SimpleKeyPair> _loadOrCreateKeyPairOnce() async {
    final encoded = await _store.read(
      accountId: accountId,
      keyName: StoredKeyName.deviceAgreementPrivate,
    );
    if (encoded != null) {
      final seed = _decodePrivateSeed(encoded);
      return _keyExchange.newKeyPairFromSeed(seed);
    }

    final generated = await _keyExchange.newKeyPair();
    final seed = await generated.extractPrivateKeyBytes();
    if (seed.length != 32) {
      throw const DeviceEnrollmentException(
        'Generated device enrollment key has an invalid length.',
      );
    }
    await _store.write(
      accountId: accountId,
      keyName: StoredKeyName.deviceAgreementPrivate,
      value: base64Encode(seed),
    );
    final persisted = await _store.read(
      accountId: accountId,
      keyName: StoredKeyName.deviceAgreementPrivate,
    );
    if (persisted == null || persisted != base64Encode(seed)) {
      throw const DeviceEnrollmentException(
        'Secure storage did not preserve the device enrollment key.',
      );
    }
    return generated;
  }

  SimplePublicKey _decodePublicKey(String encoded) {
    final bytes = base64Decode(encoded);
    if (bytes.length != 32 || base64Encode(bytes) != encoded) {
      throw const FormatException(
          'Device public key must be canonical base64.');
    }
    return SimplePublicKey(bytes, type: KeyPairType.x25519);
  }

  List<int> _decodePrivateSeed(String encoded) {
    final bytes = base64Decode(encoded);
    if (bytes.length != 32 || base64Encode(bytes) != encoded) {
      throw const DeviceEnrollmentException(
        'Stored device enrollment key is invalid.',
      );
    }
    return bytes;
  }

  Map<String, Object?> _decodeEnvelope(String encoded) {
    final decoded = jsonDecode(utf8.decode(base64Decode(encoded)));
    if (decoded is! Map || decoded['version'] != 1) {
      throw const FormatException('Unsupported device enrollment envelope.');
    }
    const expected = <String>{
      'version',
      'source_public_key',
      'nonce',
      'ciphertext',
    };
    if (decoded.keys.any((key) => key is! String) ||
        decoded.keys.cast<String>().toSet().difference(expected).isNotEmpty ||
        expected.difference(decoded.keys.cast<String>().toSet()).isNotEmpty) {
      throw const FormatException(
          'Device enrollment envelope has unexpected fields.');
    }
    return decoded.cast<String, Object?>();
  }
}

class DeviceEnrollmentException implements Exception {
  const DeviceEnrollmentException(this.message, {this.cause});

  final String message;
  final Object? cause;
}

String _requiredString(Map<String, Object?> json, String key) {
  final value = json[key];
  if (value is! String) {
    throw FormatException('$key must be a string.');
  }
  return value;
}

String _normalizedUuid(String value, String name) {
  final normalized = value.toLowerCase();
  if (!_uuidPattern.hasMatch(normalized)) {
    throw ArgumentError.value(value, name, 'must be a UUID');
  }
  return normalized;
}

final RegExp _uuidPattern = RegExp(
  r'^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$',
);
