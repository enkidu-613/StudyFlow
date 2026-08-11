import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:studyflow/app/studyflow_workspace.dart';
import 'package:studyflow/features/focus/focus_screen.dart';
import 'package:studyflow/features/home/home_screen.dart';
import 'package:studyflow/features/schedule/schedule_screen.dart';
import 'package:studyflow/features/settings/settings_screen.dart';
import 'package:studyflow/features/shell/studyflow_shell.dart';
import 'package:studyflow/features/tasks/task_list_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final workspace = await StudyFlowWorkspace.openLocalShell();
  runApp(StudyFlowApp(workspace: workspace));
}

class StudyFlowApp extends StatelessWidget {
  const StudyFlowApp({this.workspace, super.key});

  final StudyFlowWorkspace? workspace;

  @override
  Widget build(BuildContext context) {
    final activeWorkspace = workspace;
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
                builder: (context, state) =>
                    SettingsScreen(workspace: workspace),
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
