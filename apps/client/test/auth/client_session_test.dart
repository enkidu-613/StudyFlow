import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart';
import 'package:http/testing.dart';
import 'package:studyflow/app/studyflow_workspace.dart';
import 'package:studyflow/auth/auth_repository.dart';
import 'package:studyflow/auth/client_session.dart';
import 'package:studyflow/sync/sync_status.dart';

const _accountId = '11111111-1111-4111-8111-111111111111';

void main() {
  test('scheduled token refresh updates the credentials used by sync',
      () async {
    final directory = await Directory.systemTemp.createTemp('studyflow-auth-');
    addTearDown(() => directory.delete(recursive: true));
    final authApi = SessionAuthApi()
      ..nextContext = authContext(accessToken: 'refreshed-access-token');
    final store = MemoryAuthContextStore()..seed(authContext());
    final repository = AuthRepository(api: authApi, store: store);
    await repository.restoreActiveContext();
    final timerFactory = CapturingTimerFactory();
    final authorizationHeaders = <String>[];
    final session = await ClientSession.openAuthenticated(
      authContext: authContext(),
      apiBaseUri: Uri.parse('https://api.studyflow.test'),
      authRepository: repository,
      httpClient: MockClient((request) async {
        authorizationHeaders.add(request.headers['authorization'] ?? '');
        return httpJson(<String, Object?>{
          'next_cursor': 0,
          'operations': const <Object?>[],
        });
      }),
      workspaceOpener: (context) => StudyFlowWorkspace.openForTesting(
        accountId: context.userId,
        baseDirectory: directory,
      ),
      tokenRefreshTimerFactory: timerFactory.call,
    );
    addTearDown(session.close);

    timerFactory.timer.fire();
    await Future<void>.delayed(Duration.zero);
    authorizationHeaders.clear();

    final result = await session.syncNow();

    expect(authApi.refreshCalls, 1);
    expect(result!.outcome, SyncRunOutcome.succeeded);
    expect(authorizationHeaders, everyElement('Bearer refreshed-access-token'));
  });

  test('rejected scheduled refresh clears credentials and expires session',
      () async {
    final directory = await Directory.systemTemp.createTemp('studyflow-auth-');
    addTearDown(() => directory.delete(recursive: true));
    final authApi = SessionAuthApi()
      ..refreshError = const AuthApiException(401, 'revoked', 'Unauthorized.');
    final store = MemoryAuthContextStore()..seed(authContext());
    final repository = AuthRepository(api: authApi, store: store);
    await repository.restoreActiveContext();
    final timerFactory = CapturingTimerFactory();
    var expired = false;
    final session = await ClientSession.openAuthenticated(
      authContext: authContext(),
      apiBaseUri: Uri.parse('https://api.studyflow.test'),
      authRepository: repository,
      httpClient: MockClient((_) async => httpJson(<String, Object?>{
            'next_cursor': 0,
            'operations': const <Object?>[],
          })),
      workspaceOpener: (context) => StudyFlowWorkspace.openForTesting(
        accountId: context.userId,
        baseDirectory: directory,
      ),
      tokenRefreshTimerFactory: timerFactory.call,
      onSessionExpired: () async => expired = true,
    );
    addTearDown(session.close);

    timerFactory.timer.fire();
    await Future<void>.delayed(Duration.zero);

    expect(authApi.refreshCalls, 1);
    expect(repository.activeContext, isNull);
    expect(expired, isTrue);
  });
}

AuthContext authContext({String accessToken = 'access-token'}) => AuthContext(
      userId: _accountId,
      email: 'user@example.com',
      accessToken: accessToken,
      refreshToken: 'refresh-token',
      expiresIn: 900,
    );

httpJson(Map<String, Object?> value) =>
    Response(jsonEncode(value), 200, headers: const <String, String>{
      'content-type': 'application/json',
    });

final class SessionAuthApi implements AuthApi {
  AuthContext? nextContext;
  AuthApiException? refreshError;
  int refreshCalls = 0;

  @override
  Future<AuthContext> login(
          {required String email, required String password}) async =>
      nextContext ?? authContext();

  @override
  Future<AuthContext> refresh({required String refreshToken}) async {
    refreshCalls += 1;
    final error = refreshError;
    if (error != null) {
      throw error;
    }
    return nextContext ?? authContext();
  }

  @override
  Future<AuthContext> register({
    required String email,
    required String password,
  }) async =>
      nextContext ?? authContext();

  @override
  Future<void> logout({required String refreshToken}) async {}
}

final class MemoryAuthContextStore implements AuthContextStore {
  AuthContext? value;

  void seed(AuthContext context) => value = context;

  @override
  Future<void> delete() async => value = null;

  @override
  Future<AuthContext?> read() async => value;

  @override
  Future<void> write(AuthContext context) async => value = context;
}

final class CapturingTimerFactory {
  late CapturingTimer timer;

  Timer call(Duration duration, void Function() callback) {
    timer = CapturingTimer(callback);
    return timer;
  }
}

final class CapturingTimer implements Timer {
  CapturingTimer(this._callback);

  final void Function() _callback;
  bool _active = true;

  @override
  bool get isActive => _active;

  @override
  int get tick => 0;

  @override
  void cancel() => _active = false;

  void fire() {
    if (_active) {
      _callback();
    }
  }
}
