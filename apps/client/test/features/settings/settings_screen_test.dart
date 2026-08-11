import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:studyflow/app/studyflow_workspace.dart';
import 'package:studyflow/features/settings/settings_screen.dart';
import 'package:studyflow/sync/sync_status.dart';

void main() {
  late Directory directory;
  late StudyFlowWorkspace workspace;

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('studyflow-settings-');
    workspace = await StudyFlowWorkspace.openForTesting(
      accountId: 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',
      baseDirectory: directory,
    );
  });

  tearDown(() async {
    await workspace.close();
    await directory.delete(recursive: true);
  });

  testWidgets('settings shows live sync status and manual retry',
      (tester) async {
    final status = ValueNotifier<SyncStatus>(
      const SyncStatus.idle(pendingCount: 2),
    );
    var syncCalls = 0;

    await tester.pumpWidget(
      MaterialApp(
        home: SettingsScreen(
          workspace: workspace,
          syncStatus: status,
          onSync: () async {
            syncCalls += 1;
            status.value = const SyncStatus.idle(pendingCount: 0);
            return null;
          },
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('2'), findsOneWidget);
    expect(find.byKey(const Key('sync-now-button')), findsOneWidget);

    await tester.tap(find.byKey(const Key('sync-now-button')));
    await tester.pumpAndSettle();

    expect(syncCalls, 1);
    expect(find.text('0'), findsOneWidget);
    status.dispose();
  });

  testWidgets('settings no longer offers a recovery key export',
      (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: SettingsScreen(workspace: workspace),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Account recovery key'), findsNothing);
    expect(find.byKey(const Key('open-recovery-screen')), findsNothing);
  });
}
