import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:studyflow/storage/app_database.dart';

const accountA = '11111111-1111-4111-8111-111111111111';
const accountB = '22222222-2222-4222-8222-222222222222';

void main() {
  late Directory temporaryDirectory;

  setUp(() async {
    temporaryDirectory = await Directory.systemTemp.createTemp('studyflow-db-');
  });

  tearDown(() async {
    await temporaryDirectory.delete(recursive: true);
  });

  test('pending operation survives close and reopen in plaintext storage',
      () async {
    final store = await openStore(temporaryDirectory);
    await store.operations.enqueue(operation(accountId: accountA));
    await store.close();

    final databaseBytes = await databaseFile(temporaryDirectory).readAsBytes();
    expect(
      databaseBytes.take(16),
      'SQLite format 3\u0000'.codeUnits,
    );

    final reopened = await openStore(temporaryDirectory);
    addTearDown(reopened.close);

    expect(await reopened.operations.pending(10), <Operation>[
      operation(accountId: accountA),
    ]);
  });

  test('duplicate operation id does not create a second local row', () async {
    final store = await openStore(temporaryDirectory);
    addTearDown(store.close);

    await store.operations.enqueue(operation(accountId: accountA));
    await store.operations.enqueue(operation(accountId: accountA));

    expect(await store.operations.pending(10), hasLength(1));
  });

  test('different bytes for a duplicate operation id are rejected', () async {
    final store = await openStore(temporaryDirectory);
    addTearDown(store.close);
    final original = operation(accountId: accountA);
    final conflicting = Operation(
      accountId: original.accountId,
      operationId: original.operationId,
      recordId: original.recordId,
      logicalClock: original.logicalClock,
      entityType: original.entityType,
      payload: <String, Object?>{'title': 'Conflicting task'},
      isTombstone: original.isTombstone,
      schemaVersion: original.schemaVersion,
    );

    await store.operations.enqueue(original);

    await expectLater(
      store.operations.enqueue(conflicting),
      throwsA(isA<OperationIdCollisionException>()),
    );
    expect(await store.operations.pending(10), <Operation>[original]);
  });

  test('operation payload is exposed as an unmodifiable map', () {
    final operation = Operation(
      accountId: accountA,
      operationId: 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',
      recordId: 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb',
      logicalClock: 7,
      entityType: 'task',
      payload: <String, Object?>{'title': 'Algebra'},
      isTombstone: false,
      schemaVersion: 1,
    );

    expect(
      () => operation.payload['title'] = 'Replaced',
      throwsUnsupportedError,
    );
  });

  test('operation store rejects a write outside the active account', () async {
    final store = await openStore(temporaryDirectory);
    addTearDown(store.close);

    await expectLater(
      store.operations.enqueue(operation(accountId: accountB)),
      throwsA(isA<OperationAccountScopeException>()),
    );
    expect(await store.operations.pending(10), isEmpty);
  });

  test('corrupt database file fails closed', () async {
    final store = await openStore(temporaryDirectory);
    await store.operations.enqueue(operation(accountId: accountA));
    await store.close();

    await databaseFile(temporaryDirectory).writeAsString('not a database');

    await expectLater(
      openStore(temporaryDirectory),
      throwsA(isA<DatabaseRecoveryException>()),
    );
  });

  test('all record stores reject cross-account writes and reads', () async {
    final store = await openStore(temporaryDirectory);
    addTearDown(store.close);
    for (var index = 0; index < EntityType.values.length; index++) {
      final entityType = EntityType.values[index];
      final repository = store.records(entityType);
      final recordId = '10000000-0000-4000-8000-'
          '${(index + 1).toString().padLeft(12, '0')}';
      final activeRecord = record(
        accountId: accountA,
        recordId: recordId,
        entityType: entityType,
      );

      await repository.put(activeRecord);
      expect(
        await repository.get(
          accountId: accountA,
          recordId: recordId,
        ),
        activeRecord,
      );
      await expectLater(
        repository.put(
          record(
            accountId: accountB,
            recordId: recordId,
            entityType: entityType,
          ),
        ),
        throwsA(isA<StorageAccountScopeException>()),
      );
      await expectLater(
        repository.get(accountId: accountB, recordId: recordId),
        throwsA(isA<StorageAccountScopeException>()),
      );
    }
  });

  test('record timestamps round trip to the millisecond', () async {
    final store = await openStore(temporaryDirectory);
    addTearDown(store.close);
    final timestamp = DateTime.utc(2026, 8, 11, 12, 34, 56, 789);
    final record = LocalRecord(
      accountId: accountA,
      recordId: '20000000-0000-4000-8000-000000000001',
      entityType: EntityType.task,
      schemaVersion: 1,
      payload: '{"title":"Algebra"}',
      updatedAt: timestamp,
    );

    await store.records(EntityType.task).put(record);
    final stored = await store.records(EntityType.task).get(
          accountId: accountA,
          recordId: record.recordId,
        );

    expect(stored, isNotNull);
    expect(stored!.updatedAt, timestamp);
    expect(stored.updatedAt.millisecond, 789);
  });
}

Future<AccountScopedStore> openStore(Directory baseDirectory) =>
    AccountScopedStore.openForTesting(
      activeAccountId: accountA,
      baseDirectory: baseDirectory,
    );

File databaseFile(Directory baseDirectory) =>
    File('${baseDirectory.path}/studyflow-$accountA.sqlite3');

Operation operation({required String accountId}) => Operation(
      accountId: accountId,
      operationId: 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',
      recordId: 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb',
      logicalClock: 7,
      entityType: 'task',
      payload: <String, Object?>{'title': 'Algebra'},
      isTombstone: false,
      schemaVersion: 1,
    );

LocalRecord record({
  required String accountId,
  required String recordId,
  required EntityType entityType,
  DateTime? updatedAt,
}) =>
    LocalRecord(
      accountId: accountId,
      recordId: recordId,
      entityType: entityType,
      schemaVersion: 1,
      payload: '{"title":"Algebra"}',
      updatedAt: updatedAt ?? DateTime.utc(2026, 8, 11),
    );
