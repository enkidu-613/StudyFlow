import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:go_router/go_router.dart';
import 'package:studyflow/app/studyflow_workspace.dart';
import 'package:studyflow/auth/auth_repository.dart';
import 'package:studyflow/auth/auth_screen.dart';
import 'package:studyflow/auth/client_auth_controller.dart';
import 'package:studyflow/auth/client_session.dart';
import 'package:studyflow/config/client_config.dart';
import 'package:studyflow/config/locale_preference.dart';
import 'package:studyflow/features/focus/focus_screen.dart';
import 'package:studyflow/features/home/home_screen.dart';
import 'package:studyflow/features/schedule/schedule_screen.dart';
import 'package:studyflow/features/settings/settings_screen.dart';
import 'package:studyflow/features/shell/studyflow_shell.dart';
import 'package:studyflow/features/tasks/task_list_screen.dart';
import 'package:studyflow/l10n/app_localizations.dart';
import 'package:studyflow/l10n/l10n_extension.dart';

const List<LocalizationsDelegate<dynamic>> _localizationsDelegates = <
    LocalizationsDelegate<dynamic>>[
  AppLocalizations.delegate,
  GlobalMaterialLocalizations.delegate,
  GlobalWidgetsLocalizations.delegate,
  GlobalCupertinoLocalizations.delegate,
];

const List<Locale> _supportedLocales = <Locale>[
  Locale('zh'),
  Locale('en'),
];

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
    return MaterialApp(
      localizationsDelegates: _localizationsDelegates,
      supportedLocales: _supportedLocales,
      home: Scaffold(
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: <Widget>[
                const Icon(Icons.settings_ethernet, size: 48),
                const SizedBox(height: 16),
                Text(
                  context.l10n.configErrorTitle,
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  context.l10n.configErrorBody,
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
    this.localeStore,
    super.key,
  });

  final Uri apiBaseUri;
  final HttpAuthApi authApi;
  final AuthRepository authRepository;
  final ClientAuthController controller;
  final LocalePreferenceStore? localeStore;

  @override
  State<StudyFlowRoot> createState() => _StudyFlowRootState();
}

final class _StudyFlowRootState extends State<StudyFlowRoot> {
  ClientSession? _session;
  AuthInitialMessage? _initialMessageKind;
  Locale? _locale;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    unawaited(_restoreLocale());
    unawaited(_restoreSession());
  }

  Future<void> _restoreLocale() async {
    final store = widget.localeStore ?? SecureLocalePreferenceStore();
    try {
      final tag = await store.read();
      if (tag == 'zh' || tag == 'en') {
        if (mounted) {
          setState(() => _locale = Locale(tag!));
        }
      }
    } on Object {
      // Fall back to the system locale on storage errors.
    }
  }

  Future<void> _setLocale(String? tag) async {
    final store = widget.localeStore ?? SecureLocalePreferenceStore();
    await store.write(tag);
    if (mounted) {
      setState(() => _locale = tag == null ? null : Locale(tag));
    }
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
    } on Object {
      if (mounted) {
        setState(() => _initialMessageKind = AuthInitialMessage.restoreFailed);
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
    } on AuthApiException {
      await widget.authRepository.logout();
      if (mounted) {
        setState(
          () => _initialMessageKind = AuthInitialMessage.sessionExpired,
        );
      }
      return null;
    } on Object {
      await widget.authRepository.logout();
      if (mounted) {
        setState(
          () => _initialMessageKind =
              AuthInitialMessage.restoreFailedAndSignIn,
        );
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
      setState(() => _initialMessageKind = null);
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
      setState(() => _initialMessageKind = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return MaterialApp(
        localizationsDelegates: _localizationsDelegates,
        supportedLocales: _supportedLocales,
        locale: _locale,
        home: const Scaffold(
          body: Center(child: CircularProgressIndicator()),
        ),
      );
    }
    final session = _session;
    if (session != null) {
      return StudyFlowApp(
        session: session,
        onLogout: _logout,
        locale: _locale,
        onLocaleChanged: _setLocale,
      );
    }
    return MaterialApp(
      localizationsDelegates: _localizationsDelegates,
      supportedLocales: _supportedLocales,
      locale: _locale,
      home: AuthScreen(
        initialMessageKind: _initialMessageKind,
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
  const StudyFlowApp({
    this.workspace,
    this.session,
    this.onLogout,
    this.locale,
    this.onLocaleChanged,
    super.key,
  });

  final StudyFlowWorkspace? workspace;
  final ClientSession? session;
  final Future<void> Function()? onLogout;
  final Locale? locale;
  final Future<void> Function(String? tag)? onLocaleChanged;

  @override
  Widget build(BuildContext context) {
    final activeWorkspace = workspace ?? session?.workspace;
    return MaterialApp.router(
      title: 'StudyFlow',
      localizationsDelegates: _localizationsDelegates,
      supportedLocales: _supportedLocales,
      locale: locale,
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
                  locale: locale,
                  onLocaleChanged: onLocaleChanged,
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
