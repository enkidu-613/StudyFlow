import 'dart:async';

import 'package:http/http.dart' as http;

import '../app/studyflow_workspace.dart';
import '../sync/sync_api.dart';
import '../sync/sync_engine.dart';
import '../sync/sync_status.dart';
import 'auth_repository.dart';

final class ClientSession {
  ClientSession._({
    required this.workspace,
    this.authRepository,
    this.syncApi,
    this.syncEngine,
    required Timer Function(Duration, void Function()) tokenRefreshTimerFactory,
    this.onSessionExpired,
  }) : _tokenRefreshTimerFactory = tokenRefreshTimerFactory;

  final StudyFlowWorkspace workspace;
  final AuthRepository? authRepository;
  final HttpSyncApi? syncApi;
  final SyncEngine? syncEngine;
  final Timer Function(Duration, void Function()) _tokenRefreshTimerFactory;
  final Future<void> Function()? onSessionExpired;
  Timer? _tokenRefreshTimer;
  bool _sessionExpired = false;

  static Future<ClientSession> openAuthenticated({
    required AuthContext authContext,
    required Uri apiBaseUri,
    AuthRepository? authRepository,
    http.Client? httpClient,
    Future<StudyFlowWorkspace> Function(AuthContext)? workspaceOpener,
    Timer Function(Duration, void Function())? tokenRefreshTimerFactory,
    Future<void> Function()? onSessionExpired,
  }) async {
    final workspace = await (workspaceOpener ??
        (context) => StudyFlowWorkspace.openAuthenticated(
              authContext: context,
            ))(
      authContext,
    );
    final syncApi = HttpSyncApi(
      baseUri: apiBaseUri,
      client: httpClient,
    );
    late final ClientSession session;
    final syncEngine = SyncEngine(
      api: syncApi,
      authContext: authContext,
      store: workspace.store,
      refreshAuthContext:
          authRepository == null ? null : () => session._refreshForSync(),
    );
    session = ClientSession._(
      workspace: workspace,
      authRepository: authRepository,
      syncApi: syncApi,
      syncEngine: syncEngine,
      tokenRefreshTimerFactory: tokenRefreshTimerFactory ?? Timer.new,
      onSessionExpired: onSessionExpired,
    );
    session._scheduleTokenRefresh(authContext);
    unawaited(session.syncNow());
    return session;
  }

  Future<SyncRunResult?> syncNow() async {
    final engine = syncEngine;
    if (engine == null) {
      return null;
    }
    final result = await engine.runOnce();
    // A pull can add or update medication plans after the workspace was
    // opened. Re-arm both local and native reminders against the merged data.
    try {
      await workspace.alarms.resync();
      await workspace.medicationAlarms.resync();
    } on Object {
      // Alarm registration must not turn a successful data sync into a sync
      // failure. The next app open or manual refresh will retry it.
    }
    return result;
  }

  Future<AuthContext> _refreshForSync() async {
    final refreshed = await _refreshAuthentication();
    _scheduleTokenRefresh(refreshed);
    return refreshed;
  }

  Future<void> _refreshProactively() async {
    try {
      final refreshed = await _refreshAuthentication();
      syncEngine?.replaceAuthContext(refreshed);
      _scheduleTokenRefresh(refreshed);
    } on Object {
      // The next sync will show its existing network/authentication status.
    }
  }

  Future<AuthContext> _refreshAuthentication() async {
    final repository = authRepository;
    if (repository == null) {
      throw const AuthScopeException('No authentication repository is active.');
    }
    try {
      return await repository.refresh();
    } on AuthApiException catch (error) {
      if (error.statusCode == 401) {
        await _expireSession();
      }
      rethrow;
    }
  }

  void _scheduleTokenRefresh(AuthContext context) {
    _tokenRefreshTimer?.cancel();
    final secondsUntilRefresh = context.expiresIn - 60;
    final delay =
        Duration(seconds: secondsUntilRefresh > 0 ? secondsUntilRefresh : 1);
    _tokenRefreshTimer = _tokenRefreshTimerFactory(
      delay,
      () => unawaited(_refreshProactively()),
    );
  }

  Future<void> _expireSession() async {
    if (_sessionExpired) {
      return;
    }
    _sessionExpired = true;
    _tokenRefreshTimer?.cancel();
    await onSessionExpired?.call();
  }

  Future<void> close() async {
    _tokenRefreshTimer?.cancel();
    syncEngine?.dispose();
    syncApi?.close();
    await workspace.close();
  }
}
