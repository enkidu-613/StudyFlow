import 'dart:convert';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';

import 'key_manager.dart';

const int _macLength = 16;
const Set<String> _entityTypes = <String>{
  'task',
  'schedule_block',
  'focus_session',
  'check_in',
};

class PayloadAssociatedData {
  PayloadAssociatedData({
    required String accountId,
    required String recordId,
    required this.schemaVersion,
    required this.entityType,
  })  : accountId = _normalizedUuid(accountId, 'accountId'),
        recordId = _normalizedUuid(recordId, 'recordId') {
    if (schemaVersion <= 0) {
      throw ArgumentError.value(
        schemaVersion,
        'schemaVersion',
        'must be positive',
      );
    }
    if (!_entityTypes.contains(entityType)) {
      throw ArgumentError.value(
        entityType,
        'entityType',
        'must be a supported encrypted entity type',
      );
    }
  }

  final String accountId;
  final String recordId;
  final int schemaVersion;
  final String entityType;

  Uint8List encode() => Uint8List.fromList(
        utf8.encode(
          jsonEncode(<String, Object>{
            'account_id': accountId,
            'record_id': recordId,
            'schema_version': schemaVersion,
            'entity_type': entityType,
          }),
        ),
      );
}

class EncryptedPayload {
  EncryptedPayload({required List<int> nonce, required List<int> ciphertext})
      : _nonce = Uint8List.fromList(nonce),
        _ciphertext = Uint8List.fromList(ciphertext);

  final Uint8List _nonce;
  final Uint8List _ciphertext;

  Uint8List get nonce => Uint8List.fromList(_nonce);
  Uint8List get ciphertext => Uint8List.fromList(_ciphertext);
}

class PayloadCipher {
  PayloadCipher(this._keyProvider);

  final PayloadKeyProvider _keyProvider;
  final Cipher _algorithm = Xchacha20.poly1305Aead();

  Future<EncryptedPayload> encrypt(
    List<int> plaintext,
    PayloadAssociatedData associatedData,
  ) async {
    _checkAccountScope(associatedData);
    final plaintextSnapshot = Uint8List.fromList(plaintext);
    final accountKey = await _keyProvider.loadAccountDataKey();
    final secretBox = await _algorithm.encrypt(
      plaintextSnapshot,
      secretKey: accountKey,
      aad: associatedData.encode(),
    );
    return EncryptedPayload(
      nonce: secretBox.nonce,
      ciphertext: <int>[...secretBox.cipherText, ...secretBox.mac.bytes],
    );
  }

  Future<Uint8List> decrypt(
    EncryptedPayload payload,
    PayloadAssociatedData associatedData,
  ) async {
    _checkAccountScope(associatedData);
    final nonce = payload.nonce;
    final combined = payload.ciphertext;
    if (nonce.length != _algorithm.nonceLength ||
        combined.length < _macLength) {
      throw const FormatException('Malformed encrypted payload.');
    }

    final cipherTextLength = combined.length - _macLength;
    final secretBox = SecretBox(
      combined.sublist(0, cipherTextLength),
      nonce: nonce,
      mac: Mac(combined.sublist(cipherTextLength)),
    );
    final plaintext = await _algorithm.decrypt(
      secretBox,
      secretKey: await _keyProvider.loadAccountDataKey(),
      aad: associatedData.encode(),
    );
    return Uint8List.fromList(plaintext);
  }

  void _checkAccountScope(PayloadAssociatedData associatedData) {
    if (associatedData.accountId != _keyProvider.accountId.toLowerCase()) {
      throw const AccountScopeException(
        'Payload account does not match the active account.',
      );
    }
  }
}

class AccountScopeException implements Exception {
  const AccountScopeException(this.message);

  final String message;

  @override
  String toString() => 'AccountScopeException: $message';
}

String _normalizedUuid(String value, String fieldName) {
  final normalized = value.toLowerCase();
  final pattern = RegExp(
    r'^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$',
  );
  if (!pattern.hasMatch(normalized)) {
    throw ArgumentError.value(value, fieldName, 'must be a UUID');
  }
  return normalized;
}
