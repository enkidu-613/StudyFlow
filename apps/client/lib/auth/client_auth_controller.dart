import '../security/key_manager.dart';
import '../util/uuid.dart';
import 'auth_repository.dart';
import 'device_enrollment_crypto.dart';
import 'device_identity.dart';

final class ClientAuthController {
  ClientAuthController({
    required AuthRepository repository,
    required DeviceIdentity deviceIdentity,
    SecureKeyStore? keyStore,
    String Function()? generateAccountId,
  })  : _repository = repository,
        _deviceIdentity = deviceIdentity,
        _keyStore = keyStore ?? FlutterSecureKeyStore(),
        _generateAccountId = generateAccountId ?? newUuidV4;

  static const _pendingAccountId = '00000000-0000-4000-8000-000000000000';

  final AuthRepository _repository;
  final DeviceIdentity _deviceIdentity;
  final SecureKeyStore _keyStore;
  final String Function() _generateAccountId;

  Future<String> deviceId() => _deviceIdentity.loadOrCreate();

  Future<AuthContext> bootstrap({
    required String bootstrapToken,
    required String password,
  }) async {
    final accountId = _generateAccountId().toLowerCase();
    final selectedDeviceId = await deviceId();
    final keyManager = KeyManager(accountId: accountId, store: _keyStore);
    final accountDataKey = await keyManager.createAccountDataKey();
    final enrollment = DeviceEnrollmentCrypto(
      accountId: accountId,
      keyStoreAccountId: selectedDeviceId,
      store: _keyStore,
    );
    final publicKey = await enrollment.publicKeyBase64();
    final envelope = await enrollment.sealAccountDataKey(
      accountDataKey: accountDataKey,
      targetDeviceId: selectedDeviceId,
      targetDevicePublicKey: publicKey,
    );
    final context = await _repository.bootstrap(
      bootstrapToken: bootstrapToken,
      password: password,
      accountId: accountId,
      deviceId: selectedDeviceId,
      devicePublicKey: publicKey,
      encryptedAccountDataKeyEnvelope: envelope,
    );
    _requireSameIdentity(context, accountId, selectedDeviceId);
    return context;
  }

  Future<AuthContext> login({required String password}) async {
    final selectedDeviceId = await deviceId();
    final context = await _repository.login(
      password: password,
      deviceId: selectedDeviceId,
    );
    if (context.deviceId != selectedDeviceId) {
      throw const AuthScopeException(
        'Login response was bound to a different device.',
      );
    }
    return context;
  }

  Future<AuthContext> pair({required String code}) async {
    final selectedDeviceId = await deviceId();
    final pendingEnrollment = DeviceEnrollmentCrypto(
      accountId: _pendingAccountId,
      keyStoreAccountId: selectedDeviceId,
      store: _keyStore,
    );
    final publicKey = await pendingEnrollment.publicKeyBase64();
    final context = await _repository.pair(
      code: code,
      deviceId: selectedDeviceId,
      devicePublicKey: publicKey,
    );
    final enrollment = DeviceEnrollmentCrypto(
      accountId: context.accountId,
      keyStoreAccountId: selectedDeviceId,
      store: _keyStore,
    );
    final accountDataKey = await enrollment.openAccountDataKeyEnvelope(
      context.encryptedAccountDataKeyEnvelope,
      targetDeviceId: selectedDeviceId,
    );
    await KeyManager(accountId: context.accountId, store: _keyStore)
        .restoreAccountDataKey(accountDataKey);
    return context;
  }

  Future<void> restoreRecoveryKey({
    required String accountId,
    required String recoveryKey,
  }) =>
      KeyManager(accountId: accountId, store: _keyStore)
          .restoreRecoveryKey(recoveryKey);

  void _requireSameIdentity(
    AuthContext context,
    String accountId,
    String deviceId,
  ) {
    if (context.accountId != accountId || context.deviceId != deviceId) {
      throw const AuthScopeException(
        'Authentication response was bound to a different account or device.',
      );
    }
  }
}
