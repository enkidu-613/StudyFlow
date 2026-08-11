import 'package:cryptography/cryptography.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:studyflow/auth/device_enrollment_crypto.dart';
import 'package:studyflow/security/key_manager.dart';

const accountId = '11111111-1111-4111-8111-111111111111';
const targetDeviceId = '22222222-2222-4222-8222-222222222222';

void main() {
  test('enrollment envelope key can be imported into account key manager',
      () async {
    final source = DeviceEnrollmentCrypto(
      accountId: accountId,
      store: MemorySecureKeyStore(),
    );
    final target = DeviceEnrollmentCrypto(
      accountId: accountId,
      store: MemorySecureKeyStore(),
    );
    final original = SecretKey(List<int>.generate(32, (index) => index));
    final envelope = await source.sealAccountDataKey(
      accountDataKey: original,
      targetDeviceId: targetDeviceId,
      targetDevicePublicKey: await target.publicKeyBase64(),
    );
    final opened = await target.openAccountDataKeyEnvelope(
      envelope,
      targetDeviceId: targetDeviceId,
    );
    final keyManager = KeyManager(
      accountId: accountId,
      store: MemorySecureKeyStore(),
    );

    await keyManager.restoreAccountDataKey(opened);

    expect(
      await (await keyManager.loadAccountDataKey()).extractBytes(),
      await original.extractBytes(),
    );
  });

  test('account key import rejects a different existing key', () async {
    final keyManager = KeyManager(
      accountId: accountId,
      store: MemorySecureKeyStore(),
    );
    await keyManager.createAccountDataKey();

    await expectLater(
      keyManager.restoreAccountDataKey(SecretKey(List<int>.filled(32, 9))),
      throwsA(isA<KeyRecoveryException>()),
    );
  });
}

final class MemorySecureKeyStore implements SecureKeyStore {
  final Map<String, String> values = <String, String>{};

  @override
  Future<String?> read({
    required String accountId,
    required StoredKeyName keyName,
  }) async =>
      values['$accountId:${keyName.name}'];

  @override
  Future<void> write({
    required String accountId,
    required StoredKeyName keyName,
    required String value,
  }) async {
    values['$accountId:${keyName.name}'] = value;
  }
}
