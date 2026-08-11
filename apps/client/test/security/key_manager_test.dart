import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:studyflow/security/key_manager.dart';
import 'package:studyflow/security/payload_cipher.dart';

const accountA = '11111111-1111-4111-8111-111111111111';
const accountB = '22222222-2222-4222-8222-222222222222';
const recordA = '33333333-3333-4333-8333-333333333333';
const recordB = '44444444-4444-4444-8444-444444444444';

void main() {
  group('KeyManager', () {
    test(
        'device keys are reused within one account and isolated across accounts',
        () async {
      final storage = MemorySecureKeyStore();
      final firstManager = KeyManager(accountId: accountA, store: storage);
      final reopenedManager = KeyManager(accountId: accountA, store: storage);
      final otherAccountManager =
          KeyManager(accountId: accountB, store: storage);

      final firstKey = await firstManager.loadOrCreateDeviceKey();
      final reopenedKey = await reopenedManager.loadOrCreateDeviceKey();
      final otherAccountKey = await otherAccountManager.loadOrCreateDeviceKey();

      expect(
        await reopenedKey.extractBytes(),
        await firstKey.extractBytes(),
      );
      expect(
        await otherAccountKey.extractBytes(),
        isNot(await firstKey.extractBytes()),
      );
    });

    test('unreadable stored key raises a recovery error instead of rotating',
        () async {
      final storage = MemorySecureKeyStore();
      await storage.write(
        accountId: accountA,
        keyName: StoredKeyName.device,
        value: base64Encode(List<int>.filled(31, 7)),
      );
      final manager = KeyManager(accountId: accountA, store: storage);

      await expectLater(
        manager.loadOrCreateDeviceKey(),
        throwsA(isA<KeyRecoveryException>()),
      );
      expect(
        await storage.read(
          accountId: accountA,
          keyName: StoredKeyName.device,
        ),
        base64Encode(List<int>.filled(31, 7)),
      );
    });

    test('account data key is created once during bootstrap and then loaded',
        () async {
      final storage = MemorySecureKeyStore();
      final manager = KeyManager(accountId: accountA, store: storage);

      final created = await manager.createAccountDataKey();
      final loaded = await manager.loadAccountDataKey();

      expect(await loaded.extractBytes(), await created.extractBytes());
      await expectLater(
        manager.createAccountDataKey(),
        throwsA(isA<StateError>()),
      );
    });

    test('concurrent account key bootstrap returns one durable key', () async {
      final storage = MemorySecureKeyStore();
      final firstManager = KeyManager(accountId: accountA, store: storage);
      final secondManager = KeyManager(accountId: accountA, store: storage);

      final createdKeys = await Future.wait(<Future<SecretKey>>[
        firstManager.createAccountDataKey(),
        secondManager.createAccountDataKey(),
      ]);
      final firstBytes = await createdKeys.first.extractBytes();
      final secondBytes = await createdKeys.last.extractBytes();
      final persistedBytes = await KeyManager(
        accountId: accountA,
        store: storage,
      ).loadAccountDataKey().then((key) => key.extractBytes());

      expect(secondBytes, firstBytes);
      expect(persistedBytes, firstBytes);
      expect(
        await PayloadCipher(firstManager).decrypt(
          await PayloadCipher(firstManager).encrypt(
            Uint8List.fromList(const <int>[1, 2, 3]),
            PayloadAssociatedData(
              accountId: accountA,
              recordId: recordA,
              schemaVersion: 1,
              entityType: 'task',
            ),
          ),
          PayloadAssociatedData(
            accountId: accountA,
            recordId: recordA,
            schemaVersion: 1,
            entityType: 'task',
          ),
        ),
        const <int>[1, 2, 3],
      );
    });

    test('account key bootstrap fails if secure storage changes the write',
        () async {
      final manager = KeyManager(
        accountId: accountA,
        store: CorruptingSecureKeyStore(),
      );

      await expectLater(
        manager.createAccountDataKey(),
        throwsA(isA<KeyRecoveryException>()),
      );
    });
  });

  group('PayloadCipher', () {
    test('reviewed XChaCha20-Poly1305 matches a libsodium fixed vector',
        () async {
      final algorithm = Xchacha20.poly1305Aead();
      final secretBox = await algorithm.encrypt(
        const <int>[],
        secretKey: SecretKey(_hex(
          '1f4774fbe6324700d62dd6a104e7b3ca'
          '7160cfd958413f2afdb96695475f007e',
        )),
        nonce: _hex(
          '029174e5102710975a8a4a936075eb3e0f470d436884d250',
        ),
        aad: const <int>[],
      );

      expect(secretBox.cipherText, isEmpty);
      expect(
        _toHex(secretBox.mac.bytes),
        'f55cf0949af356f977479f1f187d7291',
      );
    });

    test('fresh nonces decrypt exactly', () async {
      final provider = FixedPayloadKeyProvider(
        accountId: accountA,
        bytes: List<int>.filled(32, 7),
      );
      final cipher = PayloadCipher(provider);
      final associatedData = PayloadAssociatedData(
        accountId: accountA,
        recordId: recordA,
        schemaVersion: 1,
        entityType: 'task',
      );
      final plaintext = Uint8List.fromList(utf8.encode('{"title":"algebra"}'));

      final first = await cipher.encrypt(plaintext, associatedData);
      final second = await cipher.encrypt(plaintext, associatedData);

      expect(await cipher.decrypt(first, associatedData), plaintext);
      expect(first.nonce, hasLength(24));
      expect(first.nonce, isNot(second.nonce));
      expect(first.ciphertext, isNot(containsAll(plaintext)));
    });

    test('account_id is authenticated', () async {
      final keyBytes = List<int>.filled(32, 7);
      final encrypted = await PayloadCipher(
        FixedPayloadKeyProvider(accountId: accountA, bytes: keyBytes),
      ).encrypt(
        Uint8List.fromList(const <int>[1, 2, 3]),
        _associatedData(),
      );

      await expectLater(
        PayloadCipher(
          FixedPayloadKeyProvider(accountId: accountB, bytes: keyBytes),
        ).decrypt(
          encrypted,
          _associatedData(accountId: accountB),
        ),
        throwsA(isA<SecretBoxAuthenticationError>()),
      );
    });

    test('record_id is authenticated', () async {
      await _expectAuthenticatedFieldFailure(
        _associatedData(recordId: recordB),
      );
    });

    test('schema_version is authenticated', () async {
      await _expectAuthenticatedFieldFailure(
        _associatedData(schemaVersion: 2),
      );
    });

    test('entity_type is authenticated', () async {
      await _expectAuthenticatedFieldFailure(
        _associatedData(entityType: 'check_in'),
      );
    });

    test('plaintext is snapshotted before awaiting the account key', () async {
      final provider = DelayedPayloadKeyProvider(
        accountId: accountA,
        bytes: List<int>.filled(32, 13),
      );
      final cipher = PayloadCipher(provider);
      final plaintext = Uint8List.fromList(const <int>[1, 2, 3]);

      final encryptedFuture = cipher.encrypt(plaintext, _associatedData());
      await provider.keyRequested;
      plaintext[0] = 99;
      provider.releaseKey();

      final encrypted = await encryptedFuture;
      expect(
        await cipher.decrypt(encrypted, _associatedData()),
        const <int>[1, 2, 3],
      );
    });

    test('associated data from another account is rejected before encryption',
        () async {
      final cipher = PayloadCipher(
        FixedPayloadKeyProvider(
          accountId: accountA,
          bytes: List<int>.filled(32, 9),
        ),
      );

      await expectLater(
        cipher.encrypt(
          Uint8List.fromList(const <int>[1, 2, 3]),
          PayloadAssociatedData(
            accountId: accountB,
            recordId: recordA,
            schemaVersion: 1,
            entityType: 'task',
          ),
        ),
        throwsA(isA<AccountScopeException>()),
      );
    });
  });
}

class MemorySecureKeyStore implements SecureKeyStore {
  final Map<String, String> _values = <String, String>{};

  @override
  Future<String?> read({
    required String accountId,
    required StoredKeyName keyName,
  }) async =>
      _values['$accountId:${keyName.name}'];

  @override
  Future<void> write({
    required String accountId,
    required StoredKeyName keyName,
    required String value,
  }) async {
    _values['$accountId:${keyName.name}'] = value;
  }
}

class CorruptingSecureKeyStore extends MemorySecureKeyStore {
  @override
  Future<void> write({
    required String accountId,
    required StoredKeyName keyName,
    required String value,
  }) =>
      super.write(
        accountId: accountId,
        keyName: keyName,
        value: keyName == StoredKeyName.accountData
            ? base64Encode(List<int>.filled(32, 0))
            : value,
      );
}

class FixedPayloadKeyProvider implements PayloadKeyProvider {
  FixedPayloadKeyProvider({required this.accountId, required List<int> bytes})
      : _key = SecretKey(bytes);

  @override
  final String accountId;
  final SecretKey _key;

  @override
  Future<SecretKey> loadAccountDataKey() async => _key;
}

class DelayedPayloadKeyProvider implements PayloadKeyProvider {
  DelayedPayloadKeyProvider({
    required this.accountId,
    required List<int> bytes,
  }) : _key = SecretKey(bytes);

  @override
  final String accountId;
  final SecretKey _key;
  final Completer<void> _keyRequested = Completer<void>();
  final Completer<void> _release = Completer<void>();

  Future<void> get keyRequested => _keyRequested.future;

  void releaseKey() => _release.complete();

  @override
  Future<SecretKey> loadAccountDataKey() async {
    if (!_keyRequested.isCompleted) {
      _keyRequested.complete();
    }
    await _release.future;
    return _key;
  }
}

PayloadAssociatedData _associatedData({
  String accountId = accountA,
  String recordId = recordA,
  int schemaVersion = 1,
  String entityType = 'task',
}) =>
    PayloadAssociatedData(
      accountId: accountId,
      recordId: recordId,
      schemaVersion: schemaVersion,
      entityType: entityType,
    );

Future<void> _expectAuthenticatedFieldFailure(
  PayloadAssociatedData tamperedAssociatedData,
) async {
  final cipher = PayloadCipher(
    FixedPayloadKeyProvider(
      accountId: accountA,
      bytes: List<int>.filled(32, 7),
    ),
  );
  final encrypted = await cipher.encrypt(
    Uint8List.fromList(const <int>[1, 2, 3]),
    _associatedData(),
  );

  await expectLater(
    cipher.decrypt(encrypted, tamperedAssociatedData),
    throwsA(isA<SecretBoxAuthenticationError>()),
  );
}

List<int> _hex(String value) => <int>[
      for (var index = 0; index < value.length; index += 2)
        int.parse(value.substring(index, index + 2), radix: 16),
    ];

String _toHex(List<int> bytes) =>
    bytes.map((byte) => byte.toRadixString(16).padLeft(2, '0')).join();
