import 'package:cryptography/cryptography.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:studyflow/auth/auth_repository.dart';
import 'package:studyflow/auth/client_auth_controller.dart';
import 'package:studyflow/auth/device_enrollment_crypto.dart';
import 'package:studyflow/auth/device_identity.dart';
import 'package:studyflow/security/key_manager.dart';

const accountA = '11111111-1111-4111-8111-111111111111';
const deviceA = '22222222-2222-4222-8222-222222222222';
const deviceB = '33333333-3333-4333-8333-333333333333';
const pendingAccountId = '00000000-0000-4000-8000-000000000000';

void main() {
  test('bootstrap creates a client-bound envelope before calling the API',
      () async {
    final keyStore = MemorySecureKeyStore();
    final authApi = RecordingAuthApi(
      bootstrapContext: contextFor(accountId: accountA, deviceId: deviceA),
    );
    final repository = AuthRepository(
      api: authApi,
      store: MemoryAuthContextStore(),
    );
    final controller = ClientAuthController(
      repository: repository,
      deviceIdentity: DeviceIdentity(
        store: MemoryDeviceIdentityStore(deviceA),
      ),
      keyStore: keyStore,
      generateAccountId: () => accountA,
    );

    final context = await controller.bootstrap(
      bootstrapToken: 'temporary-bootstrap-token',
      password: 'correct horse battery staple',
    );

    expect(context.accountId, accountA);
    expect(authApi.bootstrapAccountId, accountA);
    expect(authApi.bootstrapDeviceId, deviceA);
    expect(authApi.bootstrapEnvelope, isNotEmpty);
    expect(
      await KeyManager(accountId: accountA, store: keyStore)
          .loadAccountDataKey(),
      isA<SecretKey>(),
    );
  });

  test('pairing imports the account key using the pre-account device key',
      () async {
    final keyStore = MemorySecureKeyStore();
    final source = DeviceEnrollmentCrypto(
      accountId: accountA,
      store: MemorySecureKeyStore(),
    );
    final accountKey = SecretKey(List<int>.filled(32, 7));
    final authApi = RecordingAuthApi(
      pairContext: contextFor(accountId: accountA, deviceId: deviceB),
      pairEnvelopeFor: (publicKey) => source.sealAccountDataKey(
        accountDataKey: accountKey,
        targetDeviceId: deviceB,
        targetDevicePublicKey: publicKey,
      ),
    );
    final controller = ClientAuthController(
      repository: AuthRepository(
        api: authApi,
        store: MemoryAuthContextStore(),
      ),
      deviceIdentity: DeviceIdentity(
        store: MemoryDeviceIdentityStore(deviceB),
      ),
      keyStore: keyStore,
    );

    await controller.pair(code: '123456');

    expect(
      await (await KeyManager(accountId: accountA, store: keyStore)
              .loadAccountDataKey())
          .extractBytes(),
      List<int>.filled(32, 7),
    );
  });
}

AuthContext contextFor({required String accountId, required String deviceId}) =>
    AuthContext(
      accountId: accountId,
      deviceId: deviceId,
      accessToken: 'access-token',
      refreshToken: 'refresh-token',
      encryptedAccountDataKeyEnvelope: 'ZW52ZWxvcGU=',
    );

final class RecordingAuthApi implements AuthApi {
  RecordingAuthApi(
      {this.bootstrapContext, this.pairContext, this.pairEnvelopeFor});

  final AuthContext? bootstrapContext;
  final AuthContext? pairContext;
  final Future<String> Function(String publicKey)? pairEnvelopeFor;
  String? bootstrapAccountId;
  String? bootstrapDeviceId;
  String? bootstrapEnvelope;

  @override
  Future<AuthContext> bootstrap({
    required String bootstrapToken,
    required String password,
    required String accountId,
    required String deviceId,
    required String devicePublicKey,
    required String encryptedAccountDataKeyEnvelope,
  }) async {
    bootstrapAccountId = accountId;
    bootstrapDeviceId = deviceId;
    bootstrapEnvelope = encryptedAccountDataKeyEnvelope;
    return bootstrapContext!;
  }

  @override
  Future<AuthContext> login({
    required String password,
    required String deviceId,
  }) =>
      throw UnimplementedError();

  @override
  Future<AuthContext> refresh({required String refreshToken}) =>
      throw UnimplementedError();

  @override
  Future<PairingCodeResult> createPairingCode({
    required String accessToken,
    required String targetDeviceId,
    required String targetDevicePublicKey,
    required String encryptedAccountDataKeyEnvelope,
  }) =>
      throw UnimplementedError();

  @override
  Future<AuthContext> pair({
    required String code,
    required String deviceId,
    required String devicePublicKey,
  }) async {
    final envelope = await pairEnvelopeFor!(devicePublicKey);
    return AuthContext(
      accountId: pairContext!.accountId,
      deviceId: pairContext!.deviceId,
      accessToken: pairContext!.accessToken,
      refreshToken: pairContext!.refreshToken,
      encryptedAccountDataKeyEnvelope: envelope,
    );
  }

  @override
  Future<void> revokeDevice({
    required String accessToken,
    required String deviceId,
  }) async {}
}

final class MemoryDeviceIdentityStore implements DeviceIdentityStore {
  MemoryDeviceIdentityStore(this.value);

  String? value;

  @override
  Future<String?> read() async => value;

  @override
  Future<void> write(String value) async => this.value = value;
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

final class MemoryAuthContextStore implements AuthContextStore {
  AuthContext? value;

  @override
  Future<AuthContext?> read() async => value;

  @override
  Future<void> write(AuthContext context) async => value = context;

  @override
  Future<void> delete() async => value = null;
}
