import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:studyflow/app/studyflow_workspace.dart';
import 'package:studyflow/auth/auth_repository.dart';
import 'package:studyflow/auth/auth_screen.dart';
import 'package:studyflow/auth/client_auth_controller.dart';
import 'package:studyflow/auth/client_session.dart';
import 'package:studyflow/auth/device_identity.dart';
import 'package:studyflow/auth/recovery_key_screen.dart';
import 'package:studyflow/config/client_config.dart';
import 'package:studyflow/features/focus/focus_screen.dart';
import 'package:studyflow/features/home/home_screen.dart';
import 'package:studyflow/features/schedule/schedule_screen.dart';
import 'package:studyflow/features/settings/settings_screen.dart';
import 'package:studyflow/features/shell/studyflow_shell.dart';
import 'package:studyflow/features/tasks/task_list_screen.dart';
import 'package:studyflow/security/key_manager.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final apiBaseUri = ClientConfig.fromDartDefines().apiBaseUri;
  if (apiBaseUri == null) {
    final session = await ClientSession.openLocal();
    runApp(StudyFlowApp(session: session));
    return;
  }

  final authApi = HttpAuthApi(baseUri: apiBaseUri);
  final authRepository = AuthRepository(
    api: authApi,
    store: FlutterSecureAuthContextStore(),
  );
  final keyStore = FlutterSecureKeyStore();
  final controller = ClientAuthController(
    repository: authRepository,
    deviceIdentity: DeviceIdentity(
      store: FlutterSecureDeviceIdentityStore(),
    ),
    keyStore: keyStore,
  );
  runApp(
    StudyFlowRoot(
      apiBaseUri: apiBaseUri,
      authApi: authApi,
      authRepository: authRepository,
      controller: controller,
      keyStore: keyStore,
    ),
  );
}

final class StudyFlowRoot extends StatefulWidget {
  const StudyFlowRoot({
    required this.apiBaseUri,
    required this.authApi,
    required this.authRepository,
    required this.controller,
    required this.keyStore,
    super.key,
  });

  final Uri apiBaseUri;
  final HttpAuthApi authApi;
  final AuthRepository authRepository;
  final ClientAuthController controller;
  final SecureKeyStore keyStore;

  @override
  State<StudyFlowRoot> createState() => _StudyFlowRootState();
}

final class _StudyFlowRootState extends State<StudyFlowRoot> {
  ClientSession? _session;
  String? _recoveryAccountId;
  String? _message;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    unawaited(_restoreSession());
  }

  @override
  void dispose() {
    final session = _session;
    if (session != null) {
      unawaited(session.close());
    }
    widget.authApi.close();
    super.dispose();
  }

  Future<void> _restoreSession() async {
    AuthContext? context;
    try {
      context = await widget.authRepository.restoreActiveContext();
      if (context != null) {
        await _openSession(context);
      }
    } on Object catch (error) {
      if (mounted) {
        setState(() {
          _recoveryAccountId = context?.accountId;
          _message = 'Saved session could not be opened: $error';
        });
      }
    } finally {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  Future<void> _openSession(AuthContext context) async {
    final next = await ClientSession.openAuthenticated(
      authContext: context,
      apiBaseUri: widget.apiBaseUri,
      authRepository: widget.authRepository,
      secureKeyStore: widget.keyStore,
      deviceEnrollmentKeyNamespace: context.deviceId,
    );
    final previous = _session;
    _session = next;
    await previous?.close();
    if (mounted) {
      setState(() => _message = null);
    }
  }

  Future<void> _authenticate(Future<AuthContext> Function() action) async {
    final context = await action();
    await _openSession(context);
  }

  Future<void> _recover(String recoveryKey) async {
    final accountId = _recoveryAccountId;
    if (accountId == null) {
      throw StateError('No saved account is available for recovery.');
    }
    await widget.controller.restoreRecoveryKey(
      accountId: accountId,
      recoveryKey: recoveryKey,
    );
    final context = await widget.authRepository.restoreActiveContext();
    if (context == null || context.accountId != accountId) {
      throw StateError('Saved account context is unavailable.');
    }
    await _openSession(context);
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const MaterialApp(
        home: Scaffold(body: Center(child: CircularProgressIndicator())),
      );
    }
    final session = _session;
    if (session != null) {
      return StudyFlowApp(session: session);
    }
    return MaterialApp(
      home: AuthScreen(
        initialMessage: _message,
        onLogin: (password) => _authenticate(
          () => widget.controller.login(password: password),
        ),
        onBootstrap: (token, password) => _authenticate(
          () => widget.controller.bootstrap(
            bootstrapToken: token,
            password: password,
          ),
        ),
        onPair: (code) => _authenticate(
          () => widget.controller.pair(code: code),
        ),
        recoveryAccountId: _recoveryAccountId,
        onRecovery: _recoveryAccountId == null ? null : _recover,
      ),
    );
  }
}

class StudyFlowApp extends StatelessWidget {
  const StudyFlowApp({this.workspace, this.session, super.key});

  final StudyFlowWorkspace? workspace;
  final ClientSession? session;

  @override
  Widget build(BuildContext context) {
    final activeWorkspace = workspace ?? session?.workspace;
    return MaterialApp.router(
      title: 'StudyFlow',
      theme: ThemeData(
        colorSchemeSeed: const Color(0xFF356B8C),
        useMaterial3: true,
      ),
      routerConfig: activeWorkspace == null
          ? _placeholderRouter
          : _buildRouter(activeWorkspace),
    );
  }

  GoRouter _buildRouter(StudyFlowWorkspace workspace) => GoRouter(
        initialLocation: '/today',
        routes: <RouteBase>[
          ShellRoute(
            builder: (context, state, child) =>
                StudyFlowShell(workspace: workspace, child: child),
            routes: <RouteBase>[
              GoRoute(
                path: '/today',
                builder: (context, state) => HomeScreen(workspace: workspace),
              ),
              GoRoute(
                path: '/tasks',
                builder: (context, state) =>
                    TaskListScreen(workspace: workspace),
              ),
              GoRoute(
                path: '/schedule',
                builder: (context, state) =>
                    ScheduleScreen(workspace: workspace),
              ),
              GoRoute(
                path: '/focus',
                builder: (context, state) => FocusScreen(workspace: workspace),
              ),
              GoRoute(
                path: '/settings',
                builder: (context, state) => SettingsScreen(
                  workspace: workspace,
                  recoveryController:
                      KeyManagerRecoveryKeyController(workspace.keyManager),
                  syncStatus: session?.syncEngine?.status,
                  onSync: session?.syncNow,
                ),
              ),
            ],
          ),
        ],
      );
}

final GoRouter _placeholderRouter = GoRouter(
  routes: <RouteBase>[
    GoRoute(
      path: '/',
      builder: (context, state) => const Scaffold(
        body: Center(child: Text('StudyFlow')),
      ),
    ),
  ],
);
