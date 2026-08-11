import 'auth_repository.dart';

final class ClientAuthController {
  ClientAuthController({required AuthRepository repository})
      : _repository = repository;

  final AuthRepository _repository;

  Future<AuthContext> register({
    required String email,
    required String password,
  }) =>
      _repository.register(email: email, password: password);

  Future<AuthContext> login({
    required String email,
    required String password,
  }) =>
      _repository.login(email: email, password: password);

  Future<AuthContext?> restoreActiveContext() =>
      _repository.restoreActiveContext();

  Future<AuthContext> refresh() => _repository.refresh();

  Future<void> logout() => _repository.logout();
}
