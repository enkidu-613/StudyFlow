import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:studyflow/features/schedule/schedule_repository.dart';
import 'package:studyflow/features/tasks/task_repository.dart';
import 'package:studyflow/security/key_manager.dart';
import 'package:studyflow/security/payload_cipher.dart';
import 'package:studyflow/storage/app_database.dart';
import 'package:studyflow_domain/domain.dart';

const _accountId = '11111111-1111-4111-8111-111111111111';
const _deviceId = 'cccccccc-cccc-4ccc-8ccc-cccccccccccc';
const _operationId = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa';

void main() {
  late Directory temporaryDirectory;
  late MemorySecureKeyStore keyStore;
  late KeyManager keyManager;

  setUp(() async {
    temporaryDirectory =
        await Directory.systemTemp.createTemp('studyflow-repository-');
    keyStore = MemorySecureKeyStore();
    keyManager = KeyManager(accountId: _accountId, store: keyStore);
    await keyManager.createAccountDataKey();
  });

  tearDown(() async {
    await temporaryDirectory.delete(recursive: true);
  });

  test('task save rolls back its record and queue entry on commit failure',
      () async {
    var injectFailure = true;
    final store = await openStore(
      keyManager,
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
      cipher: PayloadCipher(keyManager),
    );

    await expectLater(
      repository.save(
        task('10000000-0000-4000-8000-000000000001'),
        write: write(),
      ),
      throwsStateError,
    );

    expect(
      await store.records(EncryptedEntityType.task).get(
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
      keyManager,
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
      cipher: PayloadCipher(keyManager),
    );

    await expectLater(
      repository.save(
        scheduleBlock('20000000-0000-4000-8000-000000000001'),
        write: write(),
      ),
      throwsStateError,
    );

    expect(
      await store.records(EncryptedEntityType.scheduleBlock).get(
            accountId: _accountId,
            recordId: '20000000-0000-4000-8000-000000000001',
          ),
      isNull,
    );
    expect(await store.operations.pending(10), isEmpty);
  });

  test('task operation collision rolls back B instead of splitting B and A',
      () async {
    final store = await openStore(keyManager, temporaryDirectory);
    addTearDown(store.close);
    final repository = TaskRepository(
      store: store,
      cipher: PayloadCipher(keyManager),
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
  KeyManager keyManager,
  Directory baseDirectory, {
  Future<void> Function()? transactionFailureInjector,
}) =>
    AccountScopedStore.openForTesting(
      activeAccountId: _accountId,
      keyManager: keyManager,
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

EncryptedWrite write() => EncryptedWrite(
      operationId: _operationId,
      deviceId: _deviceId,
      logicalClock: 1,
    );

class MemorySecureKeyStore implements SecureKeyStore {
  final Map<String, String> _values = <String, String>{};

  @override
  Future<String?> read({
    required String accountId,
    required StoredKeyName keyName,
  }) async =>
      _values['$accountId:${keyName.name}'];

  @override
  Future<void> write({
    required String accountId,
    required StoredKeyName keyName,
    required String value,
  }) async {
    _values['$accountId:${keyName.name}'] = value;
  }
}
