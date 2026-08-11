import 'package:flutter_test/flutter_test.dart';
import 'package:studyflow/auth/auth_repository.dart';
import 'package:studyflow/auth/client_auth_controller.dart';

const userIdA = '11111111-1111-4111-8111-111111111111';

void main() {
  test('register delegates to the repository and returns the context',
      () async {
    final repository = AuthRepository(
      api: RecordingAuthApi(),
      store: MemoryAuthContextStore(),
    );
    final controller = ClientAuthController(repository: repository);

    final context = await controller.register(
      email: 'user@example.com',
      password: 'correct horse battery staple',
    );

    expect(context.userId, userIdA);
    expect(repository.activeContext, isNotNull);
  });

  test('login delegates to the repository and persists the context',
      () async {
    final repository = AuthRepository(
      api: RecordingAuthApi(),
      store: MemoryAuthContextStore(),
    );
    final controller = ClientAuthController(repository: repository);

    final context = await controller.login(
      email: 'user@example.com',
      password: 'correct horse battery staple',
    );

    expect(context.email, 'user@example.com');
    expect(repository.activeContext, context);
  });

  test('restore, refresh and logout delegate to the repository', () async {
    final store = MemoryAuthContextStore()..value = context();
    final repository = AuthRepository(
      api: RecordingAuthApi(),
      store: store,
    );
    final controller = ClientAuthController(repository: repository);

    expect(await controller.restoreActiveContext(), isNotNull);
    final refreshed = await controller.refresh();
    expect(refreshed.userId, userIdA);
    await controller.logout();
    expect(repository.activeContext, isNull);
  });
}

AuthContext context() => AuthContext(
      userId: userIdA,
      email: 'user@example.com',
      accessToken: 'access-token',
      refreshToken: 'refresh-token',
      expiresIn: 900,
    );

final class RecordingAuthApi implements AuthApi {
  @override
  Future<AuthContext> register({
    required String email,
    required String password,
  }) async =>
      context();

  @override
  Future<AuthContext> login({
    required String email,
    required String password,
  }) async =>
      context();

  @override
  Future<AuthContext> refresh({required String refreshToken}) async =>
      context();

  @override
  Future<void> logout({required String refreshToken}) async {}
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
