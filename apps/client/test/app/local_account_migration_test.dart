import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:studyflow/app/local_account_migration.dart';
import 'package:studyflow/app/studyflow_workspace.dart';
import 'package:studyflow/storage/app_database.dart';

void main() {
  test(
      'imports old-account records without copying its pending operation queue',
      () async {
    final directory = await Directory.systemTemp.createTemp('studyflow-move-');
    addTearDown(() => directory.delete(recursive: true));
    const oldAccountId = '3dabd4f5-8b36-4f8a-98d4-d62542e27483';
    const currentAccountId = 'bdb4d8af-23fb-4d59-b652-9c5ea5a52f68';
    final source = await AccountScopedStore.openForTesting(
      activeAccountId: oldAccountId,
      baseDirectory: directory,
    );
    await source.transaction((transaction) => transaction.putRecord(
          LocalRecord(
            accountId: oldAccountId,
            recordId: '11111111-1111-4111-8111-111111111111',
            entityType: EntityType.scheduleBlock,
            schemaVersion: 1,
            payload: jsonEncode(<String, Object?>{'id': 'legacy-block'}),
            updatedAt: DateTime.utc(2026, 8, 17),
          ),
        ));
    await source.close();
    final target = await StudyFlowWorkspace.openForTesting(
      accountId: currentAccountId,
      baseDirectory: directory,
    );
    addTearDown(target.close);
    final service = LocalAccountMigrationService(
      target: target,
      baseDirectoryProvider: () async => directory,
    );

    final candidates = await service.discover();
    final result = await service.importCandidate(candidates.single);

    expect(result.importedCount, 1);
    expect(
      await target.store.records(EntityType.scheduleBlock).list(
            accountId: currentAccountId,
          ),
      hasLength(1),
    );
    expect(await target.pendingCount(), 1);
  });
}
