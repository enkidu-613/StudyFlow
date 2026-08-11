import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:studyflow/features/schedule/schedule_repository.dart';
import 'package:studyflow/features/tasks/task_repository.dart';
import 'package:studyflow/storage/app_database.dart';
import 'package:studyflow_domain/domain.dart';

const _accountId = '11111111-1111-4111-8111-111111111111';
const _operationId = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa';

void main() {
  late Directory temporaryDirectory;

  setUp(() async {
    temporaryDirectory =
        await Directory.systemTemp.createTemp('studyflow-repository-');
  });

  tearDown(() async {
    await temporaryDirectory.delete(recursive: true);
  });

  test('task save rolls back its record and queue entry on commit failure',
      () async {
    var injectFailure = true;
    final store = await openStore(
      temporaryDirectory,
      transactionFailureInjector: () async {
        if (injectFailure) {
          injectFailure = false;
          throw StateError('injected transaction failure');
        }
      },
    );
    addTearDown(store.close);
    final repository = TaskRepository(
      store: store,
    );

    await expectLater(
      repository.save(
        task('10000000-0000-4000-8000-000000000001'),
        write: write(),
      ),
      throwsStateError,
    );

    expect(
      await store.records(EntityType.task).get(
            accountId: _accountId,
            recordId: '10000000-0000-4000-8000-000000000001',
          ),
      isNull,
    );
    expect(await store.operations.pending(10), isEmpty);
  });

  test('schedule save rolls back its record and queue entry on commit failure',
      () async {
    var injectFailure = true;
    final store = await openStore(
      temporaryDirectory,
      transactionFailureInjector: () async {
        if (injectFailure) {
          injectFailure = false;
          throw StateError('injected transaction failure');
        }
      },
    );
    addTearDown(store.close);
    final repository = ScheduleRepository(
      store: store,
    );

    await expectLater(
      repository.save(
        scheduleBlock('20000000-0000-4000-8000-000000000001'),
        write: write(),
      ),
      throwsStateError,
    );

    expect(
      await store.records(EntityType.scheduleBlock).get(
            accountId: _accountId,
            recordId: '20000000-0000-4000-8000-000000000001',
          ),
      isNull,
    );
    expect(await store.operations.pending(10), isEmpty);
  });

  test('task operation collision rolls back B instead of splitting B and A',
      () async {
    final store = await openStore(temporaryDirectory);
    addTearDown(store.close);
    final repository = TaskRepository(
      store: store,
    );
    final taskA = task('30000000-0000-4000-8000-000000000001', title: 'A');
    final taskB = task('30000000-0000-4000-8000-000000000002', title: 'B');

    await repository.save(taskA, write: write());

    await expectLater(
      repository.save(taskB, write: write()),
      throwsA(isA<OperationIdCollisionException>()),
    );

    final restoredTask = await repository.get(taskA.id);
    expect(restoredTask, isNotNull);
    expect(restoredTask!.toJson(), taskA.toJson());
    expect(await repository.get(taskB.id), isNull);
    final pending = await store.operations.pending(10);
    expect(pending, hasLength(1));
    expect(pending.single.recordId, taskA.id);
  });
}

Future<AccountScopedStore> openStore(
  Directory baseDirectory, {
  Future<void> Function()? transactionFailureInjector,
}) =>
    AccountScopedStore.openForTesting(
      activeAccountId: _accountId,
      baseDirectory: baseDirectory,
      transactionFailureInjector: transactionFailureInjector,
    );

Task task(String id, {String title = 'Task'}) => Task(
      id: id,
      title: title,
      description: 'Description',
      estimatedMinutes: 25,
      priority: TaskPriority.normal,
      status: TaskStatus.todo,
      tags: const <String>['test'],
      repeatRule: RepeatRule.none,
    );

ScheduleBlock scheduleBlock(String id) => ScheduleBlock(
      id: id,
      start: DateTime.utc(2026, 8, 11, 8),
      end: DateTime.utc(2026, 8, 11, 9),
      kind: ScheduleBlockKind.task,
      taskId: '30000000-0000-4000-8000-000000000001',
      source: ScheduleBlockSource.manual,
      isLocked: false,
    );

Write write() => Write(
      operationId: _operationId,
      logicalClock: 1,
    );
