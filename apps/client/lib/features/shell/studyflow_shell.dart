import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:studyflow/app/studyflow_workspace.dart';

final class StudyFlowShell extends StatelessWidget {
  const StudyFlowShell({
    required this.workspace,
    required this.child,
    super.key,
  });

  final StudyFlowWorkspace workspace;
  final Widget child;

  static const List<String> _paths = <String>[
    '/today',
    '/tasks',
    '/schedule',
    '/focus',
    '/settings',
  ];

  @override
  Widget build(BuildContext context) {
    final location = GoRouterState.of(context).uri.path;
    final selectedIndex = _paths.indexOf(location);
    return Scaffold(
      body: child,
      bottomNavigationBar: NavigationBar(
        selectedIndex: selectedIndex < 0 ? 0 : selectedIndex,
        onDestinationSelected: (index) => context.go(_paths[index]),
        destinations: const <NavigationDestination>[
          NavigationDestination(
            icon: Icon(Icons.today_outlined),
            selectedIcon: Icon(Icons.today),
            label: 'Today',
          ),
          NavigationDestination(
            icon: Icon(Icons.checklist_outlined),
            selectedIcon: Icon(Icons.checklist),
            label: 'Tasks',
          ),
          NavigationDestination(
            icon: Icon(Icons.calendar_month_outlined),
            selectedIcon: Icon(Icons.calendar_month),
            label: 'Schedule',
          ),
          NavigationDestination(
            icon: Icon(Icons.timer_outlined),
            selectedIcon: Icon(Icons.timer),
            label: 'Focus',
          ),
          NavigationDestination(
            icon: Icon(Icons.settings_outlined),
            selectedIcon: Icon(Icons.settings),
            label: 'Settings',
          ),
        ],
      ),
    );
  }
}
