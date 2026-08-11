import 'dart:convert';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:studyflow/security/key_manager.dart';
import 'package:studyflow/security/payload_cipher.dart';

const accountA = '11111111-1111-4111-8111-111111111111';
const accountB = '22222222-2222-4222-8222-222222222222';
const recordA = '33333333-3333-4333-8333-333333333333';

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

    test('fresh nonces decrypt exactly and bind all operation metadata',
        () async {
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
      await expectLater(
        cipher.decrypt(
          first,
          PayloadAssociatedData(
            accountId: accountA,
            recordId: recordA,
            schemaVersion: 1,
            entityType: 'check_in',
          ),
        ),
        throwsA(isA<SecretBoxAuthenticationError>()),
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

class FixedPayloadKeyProvider implements PayloadKeyProvider {
  FixedPayloadKeyProvider({required this.accountId, required List<int> bytes})
      : _key = SecretKey(bytes);

  @override
  final String accountId;
  final SecretKey _key;

  @override
  Future<SecretKey> loadAccountDataKey() async => _key;
}

List<int> _hex(String value) => <int>[
      for (var index = 0; index < value.length; index += 2)
        int.parse(value.substring(index, index + 2), radix: 16),
    ];

String _toHex(List<int> bytes) =>
    bytes.map((byte) => byte.toRadixString(16).padLeft(2, '0')).join();
