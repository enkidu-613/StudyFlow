import 'dart:convert';

import 'package:cryptography/cryptography.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:studyflow/auth/auth_repository.dart';
import 'package:studyflow/auth/device_enrollment_crypto.dart';
import 'package:studyflow/auth/pairing_screen.dart';
import 'package:studyflow/auth/recovery_key_screen.dart';
import 'package:studyflow/security/key_manager.dart';

const accountA = '11111111-1111-4111-8111-111111111111';
const accountB = '22222222-2222-4222-8222-222222222222';
const deviceA = '33333333-3333-4333-8333-333333333333';
const deviceB = '44444444-4444-4444-8444-444444444444';
const envelopeA = 'ZW5jcnlwdGVkLWVudmVsb3BlLWE=';
const allZeroX25519PublicKey = 'AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=';
const lowOrderX25519PublicKey = 'AQAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=';

void main() {
  group('AuthRepository', () {
    test('bootstrap persists the first authenticated account context',
        () async {
      final api = FakeAuthApi()..nextContext = contextA();
      final store = MemoryAuthContextStore();
      final repository = AuthRepository(api: api, store: store);

      final active = await repository.bootstrap(
        bootstrapToken: 'bootstrap-token-used-once',
        password: 'correct horse battery staple',
        accountId: accountA,
        deviceId: deviceA,
        devicePublicKey: allZeroX25519PublicKey,
        encryptedAccountDataKeyEnvelope: envelopeA,
      );

      expect(active, contextA());
      expect(api.bootstrapCallCount, 1);
      expect(api.lastBootstrapToken, 'bootstrap-token-used-once');
      expect(store.readBack(), active);
    });

    test('bootstrap fails closed when the server changes account ownership',
        () async {
      final api = FakeAuthApi()
        ..nextContext = contextA(accountId: accountB, deviceId: deviceA);
      final store = MemoryAuthContextStore();
      final repository = AuthRepository(api: api, store: store);

      await expectLater(
        repository.bootstrap(
          bootstrapToken: 'bootstrap-token-used-once',
          password: 'correct horse battery staple',
          accountId: accountA,
          deviceId: deviceA,
          devicePublicKey: allZeroX25519PublicKey,
          encryptedAccountDataKeyEnvelope: envelopeA,
        ),
        throwsA(isA<AuthScopeException>()),
      );
      expect(store.serialized, isNull);
    });

    test('login persists one complete active-account context atomically',
        () async {
      final api = FakeAuthApi()..nextContext = contextA();
      final store = MemoryAuthContextStore();
      final repository = AuthRepository(api: api, store: store);

      final active = await repository.login(
        password: 'correct horse battery staple',
        deviceId: deviceA,
      );

      expect(active, contextA());
      expect(repository.activeContext, contextA());
      expect(store.writeCount, 1);
      expect(store.serialized, jsonEncode(contextA().toJson()));
      expect(store.serialized, isNot(contains('recovery')));
    });

    test('pairing persists account tokens device and envelope together',
        () async {
      final api = FakeAuthApi()..nextContext = contextA(deviceId: deviceB);
      final store = MemoryAuthContextStore();
      final repository = AuthRepository(api: api, store: store);

      final active = await repository.pair(
        code: '123456',
        deviceId: deviceB,
        devicePublicKey: 'bmV3LWRldmljZS1wdWJsaWMta2V5',
      );

      expect(active.deviceId, deviceB);
      expect(active.encryptedAccountDataKeyEnvelope, envelopeA);
      expect(store.writeCount, 1);
      expect(store.readBack(), active);
    });

    test('refresh fails closed when the server changes account ownership',
        () async {
      final store = MemoryAuthContextStore()..seed(contextA());
      final api = FakeAuthApi()
        ..nextContext = contextA(accountId: accountB, deviceId: deviceA);
      final repository = AuthRepository(api: api, store: store);
      await repository.restoreActiveContext();

      await expectLater(
          repository.refresh(), throwsA(isA<AuthScopeException>()));

      expect(repository.activeContext, isNull);
      expect(store.serialized, isNull);
    });

    test('refresh 401 clears stale in-memory and persisted auth context',
        () async {
      final store = MemoryAuthContextStore()..seed(contextA());
      final api = FakeAuthApi()
        ..refreshError = const AuthApiException(401, 'revoked');
      final repository = AuthRepository(api: api, store: store);
      await repository.restoreActiveContext();

      await expectLater(
        repository.refresh(),
        throwsA(isA<AuthApiException>()),
      );

      expect(repository.activeContext, isNull);
      expect(store.serialized, isNull);
    });

    test('logout removes the whole active context', () async {
      final store = MemoryAuthContextStore()..seed(contextA());
      final repository = AuthRepository(api: FakeAuthApi(), store: store);
      await repository.restoreActiveContext();

      await repository.logout();

      expect(repository.activeContext, isNull);
      expect(store.serialized, isNull);
      expect(store.deleteCount, 1);
    });

    test('secure-store deletion failure still clears in-memory auth context',
        () async {
      final store = MemoryAuthContextStore()
        ..seed(contextA())
        ..deleteError = StateError('secure storage unavailable');
      final repository = AuthRepository(api: FakeAuthApi(), store: store);
      await repository.restoreActiveContext();

      await expectLater(repository.logout(), throwsStateError);

      expect(repository.activeContext, isNull);
      expect(store.serialized, isNotNull);
    });

    test('revoking the active device also clears local active context',
        () async {
      final store = MemoryAuthContextStore()..seed(contextA());
      final api = FakeAuthApi();
      final repository = AuthRepository(api: api, store: store);
      await repository.restoreActiveContext();

      await repository.revokeDevice(deviceA);

      expect(api.revokedDeviceId, deviceA);
      expect(repository.activeContext, isNull);
      expect(store.serialized, isNull);
    });

    test('revocation 401 clears stale active context', () async {
      final store = MemoryAuthContextStore()..seed(contextA());
      final api = FakeAuthApi()
        ..revokeError = const AuthApiException(401, 'revoked');
      final repository = AuthRepository(api: api, store: store);
      await repository.restoreActiveContext();

      await expectLater(
        repository.revokeDevice(deviceB),
        throwsA(isA<AuthApiException>()),
      );

      expect(repository.activeContext, isNull);
      expect(store.serialized, isNull);
    });
  });

  test('HTTP auth API rejects cleartext non-loopback origins', () {
    expect(
      () => HttpAuthApi(baseUri: Uri.parse('http://api.example.test')),
      throwsArgumentError,
    );
    final loopbackApi =
        HttpAuthApi(baseUri: Uri.parse('http://127.0.0.1:8000'));
    loopbackApi.close();
  });

  group('device enrollment envelope', () {
    test('device agreement key can be created before pairing reveals account',
        () async {
      final targetStore = MemorySecureKeyStore();
      final targetBeforePairing = DeviceEnrollmentCrypto(
        accountId: accountB,
        keyStoreAccountId: deviceB,
        store: targetStore,
      );
      final source = DeviceEnrollmentCrypto(
        accountId: accountA,
        store: MemorySecureKeyStore(),
      );
      final envelope = await source.sealAccountDataKey(
        accountDataKey: SecretKey(List<int>.filled(32, 7)),
        targetDeviceId: deviceB,
        targetDevicePublicKey: await targetBeforePairing.publicKeyBase64(),
      );

      final targetAfterPairing = DeviceEnrollmentCrypto(
        accountId: accountA,
        keyStoreAccountId: deviceB,
        store: targetStore,
      );
      final opened = await targetAfterPairing.openAccountDataKeyEnvelope(
        envelope,
        targetDeviceId: deviceB,
      );

      expect(await opened.extractBytes(), List<int>.filled(32, 7));
    });

    test('envelope sealing rejects all-zero and low-order target public keys',
        () async {
      final source = DeviceEnrollmentCrypto(
        accountId: accountA,
        store: MemorySecureKeyStore(),
      );
      final accountDataKey = SecretKey(List<int>.filled(32, 7));

      for (final publicKey in <String>[
        allZeroX25519PublicKey,
        lowOrderX25519PublicKey,
      ]) {
        await expectLater(
          source.sealAccountDataKey(
            accountDataKey: accountDataKey,
            targetDeviceId: deviceB,
            targetDevicePublicKey: publicKey,
          ),
          throwsA(isA<DeviceEnrollmentException>()),
        );
      }
    });

    test('account data key opens only on the enrolled target device', () async {
      final sourceStore = MemorySecureKeyStore();
      final targetStore = MemorySecureKeyStore();
      final source = DeviceEnrollmentCrypto(
        accountId: accountA,
        store: sourceStore,
      );
      final target = DeviceEnrollmentCrypto(
        accountId: accountA,
        store: targetStore,
      );
      final accountDataKey =
          SecretKey(List<int>.generate(32, (index) => index));

      final envelope = await source.sealAccountDataKey(
        accountDataKey: accountDataKey,
        targetDeviceId: deviceB,
        targetDevicePublicKey: await target.publicKeyBase64(),
      );
      final opened = await target.openAccountDataKeyEnvelope(
        envelope,
        targetDeviceId: deviceB,
      );

      expect(await opened.extractBytes(), await accountDataKey.extractBytes());

      final otherTarget = DeviceEnrollmentCrypto(
        accountId: accountA,
        store: MemorySecureKeyStore(),
      );
      await expectLater(
        otherTarget.openAccountDataKeyEnvelope(
          envelope,
          targetDeviceId: deviceB,
        ),
        throwsA(isA<SecretBoxAuthenticationError>()),
      );
    });

    test('envelope account and target device identifiers are authenticated',
        () async {
      final source = DeviceEnrollmentCrypto(
        accountId: accountA,
        store: MemorySecureKeyStore(),
      );
      final targetStore = MemorySecureKeyStore();
      final target = DeviceEnrollmentCrypto(
        accountId: accountA,
        store: targetStore,
      );
      final envelope = await source.sealAccountDataKey(
        accountDataKey: SecretKey(List<int>.filled(32, 7)),
        targetDeviceId: deviceB,
        targetDevicePublicKey: await target.publicKeyBase64(),
      );

      await expectLater(
        target.openAccountDataKeyEnvelope(envelope, targetDeviceId: deviceA),
        throwsA(isA<SecretBoxAuthenticationError>()),
      );
      await expectLater(
        DeviceEnrollmentCrypto(accountId: accountB, store: targetStore)
            .openAccountDataKeyEnvelope(envelope, targetDeviceId: deviceB),
        throwsA(isA<SecretBoxAuthenticationError>()),
      );
    });
  });

  group('recovery key', () {
    test('recovery export restores locally for the same account only',
        () async {
      final source = KeyManager(
        accountId: accountA,
        store: MemorySecureKeyStore(),
      );
      final original = await source.createAccountDataKey();
      final recoveryKey = await source.exportRecoveryKey();
      final restored = KeyManager(
        accountId: accountA,
        store: MemorySecureKeyStore(),
      );

      await restored.restoreRecoveryKey(recoveryKey);

      expect(
        await restored.loadAccountDataKey().then((key) => key.extractBytes()),
        await original.extractBytes(),
      );
      await expectLater(
        KeyManager(accountId: accountB, store: MemorySecureKeyStore())
            .restoreRecoveryKey(recoveryKey),
        throwsA(isA<KeyRecoveryException>()),
      );
    });
  });

  testWidgets('pairing screen validates six digits and enrolls the device',
      (tester) async {
    final api = FakeAuthApi()..nextContext = contextA(deviceId: deviceB);
    final repository = AuthRepository(
      api: api,
      store: MemoryAuthContextStore(),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: PairingScreen(
          repository: repository,
          deviceId: deviceB,
          devicePublicKey: 'bmV3LWRldmljZS1wdWJsaWMta2V5',
        ),
      ),
    );

    await tester.enterText(find.byKey(const Key('pairing-code-field')), '123');
    await tester.tap(find.text('Pair device'));
    await tester.pump();
    expect(find.text('Enter the 6-digit pairing code.'), findsOneWidget);
    expect(api.pairCallCount, 0);

    await tester.enterText(
        find.byKey(const Key('pairing-code-field')), '123456');
    await tester.tap(find.text('Pair device'));
    await tester.pumpAndSettle();

    expect(api.pairCallCount, 1);
    expect(find.text('Device enrolled securely.'), findsOneWidget);
  });

  testWidgets('recovery screen warns that a lost key is non-recoverable',
      (tester) async {
    final controller = FakeRecoveryKeyController('studyflow-recovery-key');
    await tester.pumpWidget(
      MaterialApp(home: RecoveryKeyScreen(controller: controller)),
    );

    expect(
      find.text(
        'If this recovery key is lost, encrypted account data cannot be recovered.',
      ),
      findsOneWidget,
    );
    expect(find.text('studyflow-recovery-key'), findsNothing);

    await tester.tap(find.byType(Checkbox));
    await tester.pump();
    await tester.tap(find.text('Show recovery key once'));
    await tester.pumpAndSettle();

    expect(controller.exportCount, 1);
    expect(find.text('studyflow-recovery-key'), findsOneWidget);
    expect(find.text('This key is shown only for this recovery step.'),
        findsOneWidget);
  });
}

AuthContext contextA(
        {String accountId = accountA, String deviceId = deviceA}) =>
    AuthContext(
      accountId: accountId,
      deviceId: deviceId,
      accessToken: 'access-token-for-$deviceId',
      refreshToken: 'refresh-token-for-$deviceId',
      encryptedAccountDataKeyEnvelope: envelopeA,
    );

class FakeAuthApi implements AuthApi {
  AuthContext? nextContext;
  AuthApiException? refreshError;
  AuthApiException? revokeError;
  int bootstrapCallCount = 0;
  String? lastBootstrapToken;
  int pairCallCount = 0;
  String? revokedDeviceId;

  AuthContext get _response => nextContext ?? contextA();

  @override
  Future<AuthContext> bootstrap({
    required String bootstrapToken,
    required String password,
    required String accountId,
    required String deviceId,
    required String devicePublicKey,
    required String encryptedAccountDataKeyEnvelope,
  }) async {
    bootstrapCallCount += 1;
    lastBootstrapToken = bootstrapToken;
    return _response;
  }

  @override
  Future<AuthContext> login(
          {required String password, required String deviceId}) async =>
      _response;

  @override
  Future<AuthContext> pair({
    required String code,
    required String deviceId,
    required String devicePublicKey,
  }) async {
    pairCallCount += 1;
    return _response;
  }

  @override
  Future<AuthContext> refresh({required String refreshToken}) async {
    final error = refreshError;
    if (error != null) {
      throw error;
    }
    return _response;
  }

  @override
  Future<PairingCodeResult> createPairingCode({
    required String accessToken,
    required String targetDeviceId,
    required String targetDevicePublicKey,
    required String encryptedAccountDataKeyEnvelope,
  }) async =>
      PairingCodeResult(
        code: '123456',
        expiresAt: DateTime.utc(2026, 8, 11, 3, 10),
      );

  @override
  Future<void> revokeDevice({
    required String accessToken,
    required String deviceId,
  }) async {
    final error = revokeError;
    if (error != null) {
      throw error;
    }
    revokedDeviceId = deviceId;
  }
}

class MemoryAuthContextStore implements AuthContextStore {
  String? serialized;
  int writeCount = 0;
  int deleteCount = 0;
  Object? deleteError;

  void seed(AuthContext context) => serialized = jsonEncode(context.toJson());

  AuthContext? readBack() =>
      serialized == null ? null : AuthContext.fromJson(jsonDecode(serialized!));

  @override
  Future<void> delete() async {
    deleteCount += 1;
    final error = deleteError;
    if (error != null) {
      throw error;
    }
    serialized = null;
  }

  @override
  Future<AuthContext?> read() async => readBack();

  @override
  Future<void> write(AuthContext context) async {
    writeCount += 1;
    serialized = jsonEncode(context.toJson());
  }
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

class FakeRecoveryKeyController implements RecoveryKeyController {
  FakeRecoveryKeyController(this.recoveryKey);

  final String recoveryKey;
  int exportCount = 0;

  @override
  Future<String> exportRecoveryKey() async {
    exportCount += 1;
    return recoveryKey;
  }

  @override
  Future<void> restoreRecoveryKey(String recoveryKey) async {}
}
