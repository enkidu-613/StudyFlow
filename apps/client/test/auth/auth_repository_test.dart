import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:studyflow/auth/auth_repository.dart';

const userIdA = '11111111-1111-4111-8111-111111111111';
const userIdB = '22222222-2222-4222-8222-222222222222';

void main() {
  group('AuthRepository', () {
    test('register persists the first authenticated account context',
        () async {
      final api = FakeAuthApi()..nextContext = contextA();
      final store = MemoryAuthContextStore();
      final repository = AuthRepository(api: api, store: store);

      final active = await repository.register(
        email: 'user@example.com',
        password: 'correct horse battery staple',
      );

      expect(active, contextA());
      expect(api.registerCallCount, 1);
      expect(api.lastEmail, 'user@example.com');
      expect(store.readBack(), active);
    });

    test('register fails closed when the server binds a different email',
        () async {
      final api = FakeAuthApi()
        ..nextContext = contextA(email: 'other@example.com');
      final store = MemoryAuthContextStore();
      final repository = AuthRepository(api: api, store: store);

      await expectLater(
        repository.register(
          email: 'user@example.com',
          password: 'correct horse battery staple',
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
        email: 'user@example.com',
        password: 'correct horse battery staple',
      );

      expect(active, contextA());
      expect(repository.activeContext, contextA());
      expect(store.writeCount, 1);
      expect(store.serialized, jsonEncode(contextA().toJson()));
    });

    test('refresh fails closed when the server changes account ownership',
        () async {
      final store = MemoryAuthContextStore()..seed(contextA());
      final api = FakeAuthApi()..nextContext = contextA(userId: userIdB);
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
        ..refreshError = const AuthApiException(401, 'revoked', 'Unauthorized.');
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

    test('restore rejects a stored context from a different user',
        () async {
      final store = MemoryAuthContextStore()..seed(contextA(userId: userIdB));
      final repository =
          AuthRepository(api: FakeAuthApi(), store: store);

      await repository.restoreActiveContext();

      expect(repository.activeContext, isNotNull);
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
}

AuthContext contextA({String userId = userIdA, String? email}) => AuthContext(
      userId: userId,
      email: email ?? 'user@example.com',
      accessToken: 'access-token-for-$userId',
      refreshToken: 'refresh-token-for-$userId',
      expiresIn: 900,
    );

class FakeAuthApi implements AuthApi {
  AuthContext? nextContext;
  AuthApiException? refreshError;
  int registerCallCount = 0;
  String? lastEmail;

  AuthContext get _response => nextContext ?? contextA();

  @override
  Future<AuthContext> register({
    required String email,
    required String password,
  }) async {
    registerCallCount += 1;
    lastEmail = email;
    return _response;
  }

  @override
  Future<AuthContext> login({
    required String email,
    required String password,
  }) async {
    lastEmail = email;
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
  Future<void> logout({required String refreshToken}) async {}
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
