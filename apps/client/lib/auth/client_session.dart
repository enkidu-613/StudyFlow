import 'dart:async';

import 'package:http/http.dart' as http;

import '../app/studyflow_workspace.dart';
import '../security/key_manager.dart';
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
  });

  final StudyFlowWorkspace workspace;
  final AuthRepository? authRepository;
  final HttpSyncApi? syncApi;
  final SyncEngine? syncEngine;

  static Future<ClientSession> openLocal() async => ClientSession._(
        workspace: await StudyFlowWorkspace.openLocalShell(),
      );

  static Future<ClientSession> openAuthenticated({
    required AuthContext authContext,
    required Uri apiBaseUri,
    AuthRepository? authRepository,
    SecureKeyStore? secureKeyStore,
    String? deviceEnrollmentKeyNamespace,
    http.Client? httpClient,
  }) async {
    final workspace = await StudyFlowWorkspace.openAuthenticated(
      authContext: authContext,
      secureKeyStore: secureKeyStore,
      deviceEnrollmentKeyNamespace: deviceEnrollmentKeyNamespace,
    );
    final syncApi = HttpSyncApi(
      baseUri: apiBaseUri,
      client: httpClient,
    );
    final syncEngine = SyncEngine(
      api: syncApi,
      authContext: authContext,
      store: workspace.store,
      cipher: workspace.cipher,
    );
    final session = ClientSession._(
      workspace: workspace,
      authRepository: authRepository,
      syncApi: syncApi,
      syncEngine: syncEngine,
    );
    unawaited(session.syncNow());
    return session;
  }

  Future<SyncRunResult?> syncNow() => syncEngine == null
      ? Future<SyncRunResult?>.value()
      : syncEngine!.runOnce();

  Future<void> close() async {
    syncEngine?.dispose();
    syncApi?.close();
    await workspace.close();
  }
}
