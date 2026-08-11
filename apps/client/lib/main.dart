import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:studyflow/app/studyflow_workspace.dart';
import 'package:studyflow/auth/auth_repository.dart';
import 'package:studyflow/auth/auth_screen.dart';
import 'package:studyflow/auth/client_auth_controller.dart';
import 'package:studyflow/auth/client_session.dart';
import 'package:studyflow/config/client_config.dart';
import 'package:studyflow/features/focus/focus_screen.dart';
import 'package:studyflow/features/home/home_screen.dart';
import 'package:studyflow/features/schedule/schedule_screen.dart';
import 'package:studyflow/features/settings/settings_screen.dart';
import 'package:studyflow/features/shell/studyflow_shell.dart';
import 'package:studyflow/features/tasks/task_list_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final apiBaseUri = ClientConfig.fromDartDefines().apiBaseUri;
  if (apiBaseUri == null) {
    runApp(const StudyFlowConfigErrorApp());
    return;
  }

  final authApi = HttpAuthApi(baseUri: apiBaseUri);
  final authRepository = AuthRepository(
    api: authApi,
    store: FlutterSecureAuthContextStore(),
  );
  final controller = ClientAuthController(repository: authRepository);
  runApp(
    StudyFlowRoot(
      apiBaseUri: apiBaseUri,
      authApi: authApi,
      authRepository: authRepository,
      controller: controller,
    ),
  );
}

final class StudyFlowConfigErrorApp extends StatelessWidget {
  const StudyFlowConfigErrorApp({super.key});

  @override
  Widget build(BuildContext context) {
    return const MaterialApp(
      home: Scaffold(
        body: Center(
          child: Padding(
            padding: EdgeInsets.all(24),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: <Widget>[
                Icon(Icons.settings_ethernet, size: 48),
                SizedBox(height: 16),
                Text(
                  'API 地址未配置',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                ),
                SizedBox(height: 8),
                Text(
                  '请使用 --dart-define=STUDYFLOW_API_BASE_URL=https://api.example.com 启动客户端。',
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

final class StudyFlowRoot extends StatefulWidget {
  const StudyFlowRoot({
    required this.apiBaseUri,
    required this.authApi,
    required this.authRepository,
    required this.controller,
    super.key,
  });

  final Uri apiBaseUri;
  final HttpAuthApi authApi;
  final AuthRepository authRepository;
  final ClientAuthController controller;

  @override
  State<StudyFlowRoot> createState() => _StudyFlowRootState();
}

final class _StudyFlowRootState extends State<StudyFlowRoot> {
  ClientSession? _session;
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
        final refreshed = await _refreshOrClear(context);
        if (refreshed != null) {
          await _openSession(refreshed);
        }
      }
    } on Object catch (error) {
      if (mounted) {
        setState(() => _message = '无法恢复上次会话：$error');
      }
    } finally {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  Future<AuthContext?> _refreshOrClear(AuthContext context) async {
    try {
      return await widget.authRepository.refresh();
    } on AuthApiException catch (error) {
      await widget.authRepository.logout();
      if (mounted) {
        setState(() => _message = '登录已过期，请重新登录（${error.message}）');
      }
      return null;
    } on Object catch (error) {
      await widget.authRepository.logout();
      if (mounted) {
        setState(() => _message = '无法恢复上次会话，请重新登录：$error');
      }
      return null;
    }
  }

  Future<void> _openSession(AuthContext context) async {
    final next = await ClientSession.openAuthenticated(
      authContext: context,
      apiBaseUri: widget.apiBaseUri,
      authRepository: widget.authRepository,
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

  Future<void> _logout() async {
    final previous = _session;
    _session = null;
    await previous?.close();
    await widget.authRepository.logout();
    if (mounted) {
      setState(() => _message = null);
    }
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
      return StudyFlowApp(
        session: session,
        onLogout: _logout,
      );
    }
    return MaterialApp(
      home: AuthScreen(
        initialMessage: _message,
        onLogin: (email, password) => _authenticate(
          () => widget.controller.login(email: email, password: password),
        ),
        onRegister: (email, password) => _authenticate(
          () => widget.controller.register(email: email, password: password),
        ),
      ),
    );
  }
}

class StudyFlowApp extends StatelessWidget {
  const StudyFlowApp({this.workspace, this.session, this.onLogout, super.key});

  final StudyFlowWorkspace? workspace;
  final ClientSession? session;
  final Future<void> Function()? onLogout;

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
                  syncStatus: session?.syncEngine?.status,
                  onSync: session?.syncNow,
                  onLogout: onLogout,
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
