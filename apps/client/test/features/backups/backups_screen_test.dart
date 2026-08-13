import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:studyflow/features/backups/backup_models.dart';
import 'package:studyflow/features/backups/backups_repository.dart';
import 'package:studyflow/features/backups/backups_screen.dart';
import '../../helpers/l10n_test_app.dart';

final class RecordingBackupsRepository implements BackupsRepository {
  RecordingBackupsRepository({List<BackupSummary>? initial})
      : _backups = <BackupSummary>[
          ...?initial,
        ];

  final List<BackupSummary> _backups;
  bool failCreateWithQuota = false;
  bool failLoadOffline = false;
  bool failDelete = false;
  int createCalls = 0;
  int deleteCalls = 0;
  final List<String> renamed = <String>[];

  @override
  Future<BackupSummary> create({String? name}) async {
    createCalls += 1;
    if (failCreateWithQuota) {
      throw const BackupQuotaFailure('quota');
    }
    final backup = BackupSummary(
      backupId: 'backup-${_backups.length + 1}',
      name: name ?? 'backup-${_backups.length + 1}',
      createdAt: DateTime.utc(2026, 8, 13, 4),
      sizeBytes: 1024,
      operationCount: 3,
      status: 'ready',
    );
    _backups.add(backup);
    return backup;
  }

  @override
  Future<BackupListResult> list() async {
    if (failLoadOffline) {
      throw const BackupOfflineFailure('offline');
    }
    return BackupListResult(backups: _backups);
  }

  @override
  Future<BackupSummary> rename(String backupId, String name) async {
    renamed.add(name);
    final backup = BackupSummary(
      backupId: backupId,
      name: name,
      createdAt: DateTime.utc(2026, 8, 13, 4),
      sizeBytes: 1024,
      operationCount: 3,
      status: 'ready',
    );
    final index = _backups.indexWhere((b) => b.backupId == backupId);
    if (index >= 0) {
      _backups[index] = backup;
    }
    return backup;
  }

  @override
  Future<void> delete(String backupId) async {
    deleteCalls += 1;
    if (failDelete) {
      throw const BackupNetworkFailure('delete failed');
    }
    _backups.removeWhere((b) => b.backupId == backupId);
  }

  bool failBatchDeleteOffline = false;
  int batchDeleteCalls = 0;
  final List<String> batchDeletedIds = <String>[];
  int batchNotFoundCount = 0;

  @override
  Future<BackupBatchDeleteResult> deleteMany(List<String> backupIds) async {
    batchDeleteCalls += 1;
    if (failBatchDeleteOffline) {
      throw const BackupOfflineFailure('offline');
    }
    batchDeletedIds.addAll(backupIds);
    var deleted = 0;
    for (final id in backupIds) {
      if (_backups.any((b) => b.backupId == id)) {
        deleted += 1;
      }
      _backups.removeWhere((b) => b.backupId == id);
    }
    return BackupBatchDeleteResult(
      deleted: deleted,
      notFound: List<String>.generate(
        batchNotFoundCount,
        (i) => 'missing-$i',
      ),
    );
  }
}

BackupSummary backup(String id, String name) => BackupSummary(
      backupId: id,
      name: name,
      createdAt: DateTime.utc(2026, 8, 13, 4),
      sizeBytes: 2048,
      operationCount: 5,
      status: 'ready',
    );

void main() {
  testWidgets('empty list shows empty state and create button', (tester) async {
    await pumpWithL10n(
      tester,
      BackupsScreen(repository: RecordingBackupsRepository()),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('backups-empty-state')), findsOneWidget);
    expect(find.byKey(const Key('create-backup-button')), findsOneWidget);
  });

  testWidgets('list renders backups with capacity indicator', (tester) async {
    final repository = RecordingBackupsRepository(
      initial: <BackupSummary>[backup('a', '备份A'), backup('b', '备份B')],
    );
    await pumpWithL10n(
      tester,
      BackupsScreen(repository: repository),
    );
    await tester.pumpAndSettle();

    expect(find.text('备份A'), findsOneWidget);
    expect(find.text('备份B'), findsOneWidget);
    expect(find.byKey(const Key('backup-capacity-progress')), findsOneWidget);
    expect(find.textContaining('2/5'), findsOneWidget);
  });

  testWidgets('create button is disabled at capacity', (tester) async {
    final repository = RecordingBackupsRepository(
      initial: <BackupSummary>[
        backup('a', '1'),
        backup('b', '2'),
        backup('c', '3'),
        backup('d', '4'),
        backup('e', '5'),
      ],
    );
    await pumpWithL10n(
      tester,
      BackupsScreen(repository: repository),
    );
    await tester.pumpAndSettle();

    final button = tester.widget<FilledButton>(
      find.byKey(const Key('create-backup-button')),
    );
    expect(button.onPressed, isNull);
    expect(find.textContaining('已达上限'), findsOneWidget);
  });

  testWidgets('create succeeds and refreshes list', (tester) async {
    final repository = RecordingBackupsRepository();
    await pumpWithL10n(
      tester,
      BackupsScreen(repository: repository),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('create-backup-button')));
    await tester.pumpAndSettle();

    expect(repository.createCalls, 1);
    expect(find.byKey(const Key('backups-empty-state')), findsNothing);
    expect(find.text('已创建备份'), findsOneWidget);
  });

  testWidgets('create at quota shows limit dialog', (tester) async {
    final repository = RecordingBackupsRepository()
      ..failCreateWithQuota = true;
    await pumpWithL10n(
      tester,
      BackupsScreen(repository: repository),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('create-backup-button')));
    await tester.pump();
    await tester.pump();
    await tester.pump();

    expect(find.byKey(const Key('backup-limit-dialog')), findsOneWidget);
    await tester.tap(find.byKey(const Key('backup-limit-go-delete-button')));
    await tester.pump();
    await tester.pump();
    expect(find.byKey(const Key('backup-limit-dialog')), findsNothing);
  });

  testWidgets('rename validates empty name without calling api', (tester) async {
    final repository = RecordingBackupsRepository(
      initial: <BackupSummary>[backup('a', '备份A')],
    );
    await pumpWithL10n(
      tester,
      BackupsScreen(repository: repository),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('backup-item-menu')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('backup-rename-action')));
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byKey(const Key('backup-rename-field')),
      '   ',
    );
    await tester.tap(find.byKey(const Key('backup-rename-confirm-button')));
    await tester.pumpAndSettle();

    expect(find.text('请输入备份名称'), findsOneWidget);
    expect(repository.renamed, isEmpty);
  });

  testWidgets('rename succeeds and updates the list', (tester) async {
    final repository = RecordingBackupsRepository(
      initial: <BackupSummary>[backup('a', '备份A')],
    );
    await pumpWithL10n(
      tester,
      BackupsScreen(repository: repository),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('backup-item-menu')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('backup-rename-action')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('backup-rename-field')),
      '新名字',
    );
    await tester.tap(find.byKey(const Key('backup-rename-confirm-button')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump(const Duration(milliseconds: 300));

    expect(repository.renamed, <String>['新名字']);
    expect(find.text('新名字'), findsOneWidget);
  });

  testWidgets('delete requires confirmation and removes item', (tester) async {
    final repository = RecordingBackupsRepository(
      initial: <BackupSummary>[backup('a', '备份A')],
    );
    await pumpWithL10n(
      tester,
      BackupsScreen(repository: repository),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('backup-item-menu')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('backup-delete-action')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('backup-delete-dialog')), findsOneWidget);
    await tester.tap(find.byKey(const Key('backup-delete-cancel-button')));
    await tester.pumpAndSettle();

    expect(repository.deleteCalls, 0);
    expect(find.text('备份A'), findsOneWidget);

    await tester.tap(find.byKey(const Key('backup-item-menu')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('backup-delete-action')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('backup-delete-confirm-button')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump(const Duration(milliseconds: 300));

    expect(repository.deleteCalls, 1);
    expect(find.text('备份A'), findsNothing);
    expect(find.text('已删除'), findsOneWidget);
  });

  testWidgets('offline load shows error state with retry', (tester) async {
    final repository = RecordingBackupsRepository()..failLoadOffline = true;
    await pumpWithL10n(
      tester,
      BackupsScreen(repository: repository),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('backups-error-state')), findsOneWidget);
    expect(find.text('网络连接失败，请检查网络后重试'), findsOneWidget);

    repository.failLoadOffline = false;
    await tester.tap(find.byKey(const Key('backups-retry-button')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.byKey(const Key('backups-empty-state')), findsOneWidget);
  });

  testWidgets('edit button is hidden for empty list', (tester) async {
    await pumpWithL10n(
      tester,
      BackupsScreen(repository: RecordingBackupsRepository()),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('backups-edit-button')), findsNothing);
  });

  testWidgets('edit enters selection mode with checkboxes', (tester) async {
    final repository = RecordingBackupsRepository(
      initial: <BackupSummary>[backup('a', '备份A'), backup('b', '备份B')],
    );
    await pumpWithL10n(
      tester,
      BackupsScreen(repository: repository),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('backups-edit-button')));
    await tester.pumpAndSettle();

    expect(
      find.byKey(const Key('backup-item-checkbox-a')),
      findsOneWidget,
    );
    expect(find.byKey(const Key('backup-item-menu')), findsNothing);
    expect(find.byKey(const Key('backup-batch-delete-button')), findsOneWidget);
    expect(find.byKey(const Key('create-backup-button')), findsNothing);
    expect(find.text('已选 0 项'), findsOneWidget);
  });

  testWidgets('long press enters selection mode and selects the item',
      (tester) async {
    final repository = RecordingBackupsRepository(
      initial: <BackupSummary>[backup('a', '备份A')],
    );
    await pumpWithL10n(
      tester,
      BackupsScreen(repository: repository),
    );
    await tester.pumpAndSettle();

    await tester.longPress(find.byKey(const Key('backup-item-a')));
    await tester.pumpAndSettle();

    expect(find.text('已选 1 项'), findsOneWidget);
    final checkbox = tester.widget<Checkbox>(
      find.byKey(const Key('backup-item-checkbox-a')),
    );
    expect(checkbox.value, isTrue);
  });

  testWidgets('tapping items toggles selection count', (tester) async {
    final repository = RecordingBackupsRepository(
      initial: <BackupSummary>[backup('a', 'A'), backup('b', 'B')],
    );
    await pumpWithL10n(
      tester,
      BackupsScreen(repository: repository),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('backups-edit-button')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('backup-item-a')));
    await tester.pumpAndSettle();

    expect(find.text('已选 1 项'), findsOneWidget);
    await tester.tap(find.byKey(const Key('backup-item-b')));
    await tester.pumpAndSettle();

    expect(find.text('已选 2 项'), findsOneWidget);
    await tester.tap(find.byKey(const Key('backup-item-a')));
    await tester.pumpAndSettle();

    expect(find.text('已选 1 项'), findsOneWidget);
  });

  testWidgets('select all toggles between all and none', (tester) async {
    final repository = RecordingBackupsRepository(
      initial: <BackupSummary>[backup('a', 'A'), backup('b', 'B')],
    );
    await pumpWithL10n(
      tester,
      BackupsScreen(repository: repository),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('backups-edit-button')));
    await tester.pumpAndSettle();
    expect(find.text('全选'), findsOneWidget);

    await tester.tap(find.byKey(const Key('backup-select-all-button')));
    await tester.pumpAndSettle();
    expect(find.text('已选 2 项'), findsOneWidget);
    expect(find.text('全不选'), findsOneWidget);

    await tester.tap(find.byKey(const Key('backup-select-all-button')));
    await tester.pumpAndSettle();
    expect(find.text('已选 0 项'), findsOneWidget);
    expect(find.text('全选'), findsOneWidget);
  });

  testWidgets('batch delete button disabled with empty selection',
      (tester) async {
    final repository = RecordingBackupsRepository(
      initial: <BackupSummary>[backup('a', 'A')],
    );
    await pumpWithL10n(
      tester,
      BackupsScreen(repository: repository),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('backups-edit-button')));
    await tester.pumpAndSettle();

    final button = tester.widget<FilledButton>(
      find.byKey(const Key('backup-batch-delete-button')),
    );
    expect(button.onPressed, isNull);
  });

  testWidgets('batch delete success removes backups and exits selection',
      (tester) async {
    final repository = RecordingBackupsRepository(
      initial: <BackupSummary>[backup('a', 'A'), backup('b', 'B')],
    );
    await pumpWithL10n(
      tester,
      BackupsScreen(repository: repository),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('backups-edit-button')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('backup-select-all-button')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('backup-batch-delete-button')));
    await tester.pumpAndSettle();

    expect(
      find.byKey(const Key('backup-batch-delete-dialog')),
      findsOneWidget,
    );
    await tester.tap(
      find.byKey(const Key('backup-batch-delete-confirm-button')),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump(const Duration(milliseconds: 300));

    expect(repository.batchDeletedIds, <String>['a', 'b']);
    expect(repository.batchDeleteCalls, 1);
    expect(find.text('已删除 2 个备份'), findsOneWidget);
    expect(find.byKey(const Key('backups-edit-button')), findsNothing);
    expect(find.byKey(const Key('create-backup-button')), findsOneWidget);
    expect(find.byKey(const Key('backups-empty-state')), findsOneWidget);
  });

  testWidgets('batch delete partial failure shows partial message',
      (tester) async {
    final repository = RecordingBackupsRepository(
      initial: <BackupSummary>[backup('a', 'A'), backup('b', 'B')],
    )..batchNotFoundCount = 1;
    await pumpWithL10n(
      tester,
      BackupsScreen(repository: repository),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('backups-edit-button')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('backup-select-all-button')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('backup-batch-delete-button')));
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const Key('backup-batch-delete-confirm-button')),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.textContaining('不存在'), findsOneWidget);
    expect(find.byKey(const Key('backups-edit-button')), findsNothing);
  });

  testWidgets('batch delete offline keeps selection mode', (tester) async {
    final repository = RecordingBackupsRepository(
      initial: <BackupSummary>[backup('a', 'A')],
    )..failBatchDeleteOffline = true;
    await pumpWithL10n(
      tester,
      BackupsScreen(repository: repository),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('backups-edit-button')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('backup-item-a')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('backup-batch-delete-button')));
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const Key('backup-batch-delete-confirm-button')),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('网络连接失败，请检查网络后重试'), findsOneWidget);
    expect(find.text('已选 1 项'), findsOneWidget);
    expect(find.byKey(const Key('backup-batch-delete-button')), findsOneWidget);
  });

  testWidgets('cancel exits selection mode without deleting', (tester) async {
    final repository = RecordingBackupsRepository(
      initial: <BackupSummary>[backup('a', 'A')],
    );
    await pumpWithL10n(
      tester,
      BackupsScreen(repository: repository),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('backups-edit-button')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('backup-selection-cancel-button')));
    await tester.pumpAndSettle();

    expect(repository.batchDeleteCalls, 0);
    expect(find.byKey(const Key('create-backup-button')), findsOneWidget);
    expect(find.byKey(const Key('backups-edit-button')), findsOneWidget);
  });

  testWidgets('batch delete dialog cancel does not call repository',
      (tester) async {
    final repository = RecordingBackupsRepository(
      initial: <BackupSummary>[backup('a', 'A')],
    );
    await pumpWithL10n(
      tester,
      BackupsScreen(repository: repository),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('backups-edit-button')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('backup-item-a')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('backup-batch-delete-button')));
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const Key('backup-batch-delete-cancel-button')),
    );
    await tester.pumpAndSettle();

    expect(repository.batchDeleteCalls, 0);
    expect(find.text('已选 1 项'), findsOneWidget);
  });
}
