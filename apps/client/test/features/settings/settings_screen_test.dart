import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:studyflow/app/studyflow_workspace.dart';
import 'package:studyflow/auth/recovery_key_screen.dart';
import 'package:studyflow/features/settings/settings_screen.dart';
import 'package:studyflow/security/key_manager.dart';
import 'package:studyflow/sync/sync_status.dart';

void main() {
  late Directory directory;
  late StudyFlowWorkspace workspace;

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('studyflow-settings-');
    workspace = await StudyFlowWorkspace.openForTesting(
      keyManager: KeyManager(
        accountId: 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',
        store: MemorySecureKeyStore(),
      ),
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

  testWidgets('settings opens the account recovery key screen', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: SettingsScreen(
          workspace: workspace,
          recoveryController:
              KeyManagerRecoveryKeyController(workspace.keyManager),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('open-recovery-screen')));
    await tester.pumpAndSettle();

    expect(find.text('Recovery key'), findsOneWidget);
    expect(find.text('Show recovery key once'), findsOneWidget);
  });
}

final class MemorySecureKeyStore implements SecureKeyStore {
  final Map<String, String> values = <String, String>{};

  @override
  Future<String?> read({
    required String accountId,
    required StoredKeyName keyName,
  }) async {
    final value = values['$accountId:${keyName.name}'];
    return value == null ? null : utf8.decode(base64Decode(value));
  }

  @override
  Future<void> write({
    required String accountId,
    required StoredKeyName keyName,
    required String value,
  }) async {
    values['$accountId:${keyName.name}'] = base64Encode(utf8.encode(value));
  }
}
