import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:studyflow/app/studyflow_workspace.dart';
import 'package:studyflow/features/settings/settings_screen.dart';
import 'package:studyflow/sync/sync_status.dart';
import '../../helpers/l10n_test_app.dart';

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

    await pumpWithL10n(
      tester,
      SettingsScreen(
        workspace: workspace,
        syncStatus: status,
        onSync: () async {
          syncCalls += 1;
          status.value = const SyncStatus.idle(pendingCount: 0);
          return null;
        },
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

  testWidgets('settings shows up-to-date when nothing is pending',
      (tester) async {
    final status = ValueNotifier<SyncStatus>(
      const SyncStatus.idle(pendingCount: 0),
    );

    await pumpWithL10n(
      tester,
      SettingsScreen(
        workspace: workspace,
        syncStatus: status,
      ),
      locale: const Locale('en'),
    );
    await tester.pumpAndSettle();

    expect(find.text('Up to date'), findsNWidgets(2));
    expect(find.text('Pending sync'), findsNothing);
    status.dispose();
  });

  testWidgets('settings shows pending count when changes are queued',
      (tester) async {
    final status = ValueNotifier<SyncStatus>(
      const SyncStatus.idle(pendingCount: 3),
    );

    await pumpWithL10n(
      tester,
      SettingsScreen(
        workspace: workspace,
        syncStatus: status,
      ),
      locale: const Locale('en'),
    );
    await tester.pumpAndSettle();

    expect(find.text('Pending sync'), findsOneWidget);
    expect(find.text('3 changes pending'), findsOneWidget);
    status.dispose();
  });

  testWidgets('settings shows failure category and retry', (tester) async {
    final status = ValueNotifier<SyncStatus>(
      const SyncStatus(
        kind: SyncStatusKind.failed,
        pendingCount: 1,
        failureCategory: SyncFailureCategory.network,
      ),
    );

    await pumpWithL10n(
      tester,
      SettingsScreen(
        workspace: workspace,
        syncStatus: status,
        onSync: () async => null,
      ),
      locale: const Locale('en'),
    );
    await tester.pumpAndSettle();

    expect(find.text('Sync failed: network'), findsOneWidget);
    expect(find.byKey(const Key('sync-now-button')), findsOneWidget);
    status.dispose();
  });

  testWidgets('settings shows the server failure detail', (tester) async {
    final status = ValueNotifier<SyncStatus>(
      const SyncStatus(
        kind: SyncStatusKind.failed,
        pendingCount: 0,
        failureCategory: SyncFailureCategory.schema,
        failureMessage: 'entityType: Input should be a valid option',
      ),
    );

    await pumpWithL10n(
      tester,
      SettingsScreen(
        workspace: workspace,
        syncStatus: status,
      ),
      locale: const Locale('en'),
    );
    await tester.pumpAndSettle();

    expect(
      find.text('entityType: Input should be a valid option'),
      findsOneWidget,
    );
    status.dispose();
  });

  testWidgets('settings no longer offers a recovery key export',
      (tester) async {
    await pumpWithL10n(
      tester,
      SettingsScreen(workspace: workspace),
    );
    await tester.pumpAndSettle();

    expect(find.text('Account recovery key'), findsNothing);
    expect(find.byKey(const Key('open-recovery-screen')), findsNothing);
  });
}
