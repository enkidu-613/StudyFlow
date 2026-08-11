import 'dart:convert';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:studyflow/auth/auth_repository.dart';
import 'package:studyflow/features/schedule/schedule_repository.dart';
import 'package:studyflow/features/tasks/task_repository.dart';
import 'package:studyflow/providers/app_providers.dart';
import 'package:studyflow/storage/app_database.dart';
import 'package:studyflow/sync/sync_api.dart';
import 'package:studyflow/sync/sync_engine.dart';
import 'package:studyflow/sync/sync_status.dart';
import 'package:studyflow_domain/domain.dart';
import 'package:studyflow_sync_contract/sync_contract.dart';

const _accountId = '11111111-1111-4111-8111-111111111111';
const _taskId = '33333333-3333-4333-8333-333333333333';
const _operationId = '44444444-4444-4444-8444-444444444444';

void main() {
  test('network failure leaves the operation queued and exposes retry',
      () async {
    final fixture = await testEngine(api: FailingSyncApi(failuresRemaining: 1));
    final engine = fixture.engine;

    final result = await engine.runOnce();

    expect(result.outcome, SyncRunOutcome.failed);
    expect(engine.status.value.kind, SyncStatusKind.failed);
    expect(engine.status.value.failureCategory, SyncFailureCategory.network);
    expect(engine.status.value.retry, isNotNull);
    expect(await engine.pendingCount(), 1);
  });

  test('retry pushes the retained operation before pulling', () async {
    final api = FailingSyncApi(failuresRemaining: 1);
    final fixture = await testEngine(api: api);
    final engine = fixture.engine;

    await engine.runOnce();
    final result = await engine.status.value.retry!.call();

    expect(result.outcome, SyncRunOutcome.succeeded);
    expect(api.events, <String>['push', 'push', 'pull:0']);
    expect(await engine.pendingCount(), 0);
    expect(engine.status.value.kind, SyncStatusKind.idle);
  });

  test('duplicate pulled operation is applied only once', () async {
    final api = ScriptedSyncApi();
    final fixture = await testEngine(api: api, seedPendingTask: false);
    final remoteTask = testTask(title: 'Remote algebra');
    api
      ..nextCursor = 1
      ..pulledOperations = <SyncOperationV2>[
        await fixture.contractOperation(
          operationId: '55555555-5555-4555-8555-555555555555',
          recordId: remoteTask.id,
          logicalClock: 1,
          entityType: 'task',
          payload: remoteTask.toJson(),
        ),
      ];

    final first = await fixture.engine.runOnce();
    final second = await fixture.engine.runOnce();

    expect(first.pulledCount, 1);
    expect(second.pulledCount, 0);
    expect(
        (await fixture.taskRepository.get(_taskId))!.title, 'Remote algebra');
    expect(await fixture.store.operations.lastCommittedCursor(), 1);
  });

  test('simultaneous task edits merge fields by last-write stamp', () async {
    final api = ScriptedSyncApi();
    final fixture = await testEngine(api: api);
    await fixture.engine.runOnce();

    await fixture.taskRepository.save(
      testTask(title: 'Local algebra'),
      write: Write(
        operationId: '77777777-7777-4777-8777-777777777777',
        logicalClock: 2,
      ),
    );
    final remoteTask = testTask(status: TaskStatus.completed);
    api
      ..nextCursor = 1
      ..pulledOperations = <SyncOperationV2>[
        await fixture.contractOperation(
          operationId: '88888888-8888-4888-8888-888888888888',
          recordId: remoteTask.id,
          logicalClock: 2,
          entityType: 'task',
          payload: remoteTask.toJson(),
        ),
      ];

    await fixture.engine.runOnce();

    final merged = await fixture.taskRepository.get(_taskId);
    expect(merged!.title, 'Local algebra');
    expect(merged.status, TaskStatus.completed);
  });

  test('stale task pulls never regress the payload or field stamp', () async {
    final api = PagedSyncApi();
    final fixture = await testEngine(api: api, seedPendingTask: false);
    await fixture.taskRepository.save(
      testTask(title: 'Local clock 10'),
      write: Write(
        operationId: '16161616-1616-4616-8616-161616161616',
        logicalClock: 10,
      ),
    );
    await fixture.engine.runOnce();

    api.pages = <List<SyncOperationV2>>[
      <SyncOperationV2>[
        await fixture.contractOperation(
          operationId: '17171717-1717-4717-8717-171717171717',
          recordId: _taskId,
          logicalClock: 5,
          entityType: 'task',
          payload: testTask(title: 'Remote clock 5').toJson(),
        ),
      ],
      <SyncOperationV2>[
        await fixture.contractOperation(
          operationId: '18181818-1818-4818-8818-181818181818',
          recordId: _taskId,
          logicalClock: 7,
          entityType: 'task',
          payload: testTask(title: 'Remote clock 7').toJson(),
        ),
      ],
    ];

    await fixture.engine.runOnce();
    await fixture.engine.runOnce();

    expect(
        (await fixture.taskRepository.get(_taskId))!.title, 'Local clock 10');
    final stamp = await fixture.store.operations.taskFieldVersion(
      _taskId,
      'title',
    );
    expect(stamp!.logicalClock, 10);
    expect(stamp.operationId, '16161616-1616-4616-8616-161616161616');
  });

  test(
      'lower partial merge keeps the max record stamp and blocks a stale tombstone',
      () async {
    final api = PagedSyncApi();
    final fixture = await testEngine(api: api, seedPendingTask: false);
    await fixture.taskRepository.save(
      testTask(),
      write: Write(
        operationId: '23232323-2323-4323-8323-232323232323',
        logicalClock: 1,
      ),
    );
    await fixture.engine.runOnce();

    await fixture.taskRepository.save(
      testTask(title: 'Local title at 10'),
      write: Write(
        operationId: '24242424-2424-4424-8424-242424242424',
        logicalClock: 10,
      ),
    );
    final statusAt5 = await fixture.contractOperation(
      operationId: '25252525-2525-4525-8525-252525252525',
      recordId: _taskId,
      logicalClock: 5,
      entityType: 'task',
      payload: testTask(status: TaskStatus.completed).toJson(),
    );
    final tombstoneAt7 = await fixture.contractOperation(
      operationId: '26262626-2626-4626-8626-262626262626',
      recordId: _taskId,
      logicalClock: 7,
      entityType: 'task',
      payload: testTask(status: TaskStatus.completed).toJson(),
      isTombstone: true,
    );
    api.pages = <List<SyncOperationV2>>[
      <SyncOperationV2>[statusAt5],
      <SyncOperationV2>[tombstoneAt7],
    ];

    await fixture.engine.runOnce();
    await fixture.engine.runOnce();

    final task = await fixture.taskRepository.get(_taskId);
    expect(task, isNotNull);
    expect(task!.title, 'Local title at 10');
    expect(task.status, TaskStatus.completed);
    expect(
      await fixture.store.operations.retainedTombstoneCount(_taskId),
      1,
    );
    final titleStamp = await fixture.store.operations.taskFieldVersion(
      _taskId,
      'title',
    );
    final statusStamp = await fixture.store.operations.taskFieldVersion(
      _taskId,
      'status',
    );
    expect(titleStamp!.logicalClock, 10);
    expect(titleStamp.operationId, '24242424-2424-4424-8424-242424242424');
    expect(statusStamp!.logicalClock, 5);
    final current = await fixture.store.operations.snapshotFor(
      fixture.asOperation(tombstoneAt7),
    );
    expect(current.currentVersion!.logicalClock, 10);
    expect(
      current.currentVersion!.operationId,
      '24242424-2424-4424-8424-242424242424',
    );
    expect(current.currentVersion!.isTombstone, isFalse);
  });

  test(
      'malformed push acknowledgement retains queue and exposes protocol retry',
      () async {
    final fixture = await testEngine(api: MalformedAckApi());

    final result = await fixture.engine.runOnce();

    expect(result.failureCategory, SyncFailureCategory.protocol);
    expect(fixture.engine.status.value.kind, SyncStatusKind.failed);
    expect(fixture.engine.status.value.retry, isNotNull);
    expect(await fixture.engine.pendingCount(), 1);
  });

  test('omitted push acknowledgement retains the entire queue', () async {
    final fixture = await testEngine(api: OmittedAckApi());

    final result = await fixture.engine.runOnce();

    expect(result.failureCategory, SyncFailureCategory.protocol);
    expect(await fixture.engine.pendingCount(), 1);
    expect(fixture.engine.status.value.kind, SyncStatusKind.failed);
    expect(fixture.engine.status.value.retry, isNotNull);
  });

  test('duplicate push acknowledgement ID is a protocol failure', () async {
    final fixture = await testEngine(api: DuplicateAckApi());

    final result = await fixture.engine.runOnce();

    expect(result.failureCategory, SyncFailureCategory.protocol);
    expect(await fixture.engine.pendingCount(), 1);
    expect(fixture.engine.status.value.kind, SyncStatusKind.failed);
    expect(fixture.engine.status.value.retry, isNotNull);
  });

  test('simultaneous schedule edits preserve a conflict copy', () async {
    const blockId = '99999999-9999-4999-8999-999999999999';
    const conflictOperationId = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa';
    final api = ScriptedSyncApi();
    final fixture = await testEngine(api: api, seedPendingTask: false);
    final repository = ScheduleRepository(
      store: fixture.store,
    );
    final base = testScheduleBlock(id: blockId);
    await repository.save(
      base,
      write: Write(
        operationId: 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb',
        logicalClock: 1,
      ),
    );
    await fixture.engine.runOnce();

    final local = testScheduleBlock(
      id: blockId,
      start: DateTime.utc(2026, 8, 11, 9),
      end: DateTime.utc(2026, 8, 11, 10),
    );
    await repository.save(
      local,
      write: Write(
        operationId: 'cccccccc-cccc-4ccc-8ccc-cccccccccccc',
        logicalClock: 2,
      ),
    );
    final remote = testScheduleBlock(
      id: blockId,
      end: DateTime.utc(2026, 8, 11, 9, 30),
    );
    api
      ..nextCursor = 1
      ..pulledOperations = <SyncOperationV2>[
        await fixture.contractOperation(
          operationId: conflictOperationId,
          recordId: blockId,
          logicalClock: 2,
          entityType: 'schedule_block',
          payload: remote.toJson(),
        ),
      ];

    await fixture.engine.runOnce();

    expect((await repository.get(blockId))!.toJson(), local.toJson());
    final conflict = await repository.get(conflictOperationId);
    expect(conflict, isNotNull);
    expect(conflict!.id, conflictOperationId);
    expect(conflict.start, remote.start);
    expect(conflict.end, remote.end);
  });

  test('pulled tombstone deletes the record but remains retained', () async {
    final api = ScriptedSyncApi();
    final fixture = await testEngine(api: api);
    await fixture.engine.runOnce();
    api
      ..nextCursor = 1
      ..pulledOperations = <SyncOperationV2>[
        await fixture.contractOperation(
          operationId: 'dddddddd-dddd-4ddd-8ddd-dddddddddddd',
          recordId: _taskId,
          logicalClock: 2,
          entityType: 'task',
          payload: testTask().toJson(),
          isTombstone: true,
        ),
      ];

    await fixture.engine.runOnce();
    await fixture.engine.runOnce();

    expect(await fixture.taskRepository.get(_taskId), isNull);
    expect(
      await fixture.store.operations.retainedTombstoneCount(_taskId),
      1,
    );
  });

  test('finished focus sessions are append-only', () async {
    const sessionId = 'eeeeeeee-eeee-4eee-8eee-eeeeeeeeeeee';
    const remoteOperationId = 'ffffffff-ffff-4fff-8fff-ffffffffffff';
    final api = ScriptedSyncApi();
    final fixture = await testEngine(api: api, seedPendingTask: false);
    final localSession = FocusSession(
      id: sessionId,
      taskId: _taskId,
      startedAt: DateTime.utc(2026, 8, 11, 8),
      endedAt: DateTime.utc(2026, 8, 11, 9),
      completionMethod: FocusCompletionMethod.manual,
    );
    await fixture.seedRecord(
      operationId: '12121212-1212-4212-8212-121212121212',
      recordId: sessionId,
      logicalClock: 1,
      entityType: 'focus_session',
      payload: localSession.toJson(),
    );
    await fixture.engine.runOnce();

    final remoteSession = FocusSession(
      id: sessionId,
      taskId: _taskId,
      startedAt: DateTime.utc(2026, 8, 11, 8),
      endedAt: DateTime.utc(2026, 8, 11, 10),
      completionMethod: FocusCompletionMethod.timer,
    );
    api
      ..nextCursor = 1
      ..pulledOperations = <SyncOperationV2>[
        await fixture.contractOperation(
          operationId: remoteOperationId,
          recordId: sessionId,
          logicalClock: 2,
          entityType: 'focus_session',
          payload: remoteSession.toJson(),
        ),
      ];

    await fixture.engine.runOnce();

    expect((await fixture.readFocusSession(sessionId))!.endedAt,
        localSession.endedAt);
    final conflict = await fixture.readFocusSession(remoteOperationId);
    expect(conflict, isNotNull);
    expect(conflict!.id, remoteOperationId);
    expect(conflict.endedAt, remoteSession.endedAt);
  });

  test('HTTP sync API uses bearer auth and sends plaintext JSON payloads',
      () async {
    final operation = SyncOperationV2(
      operationId: _operationId,
      recordId: _taskId,
      logicalClock: 1,
      entityType: 'task',
      payload: testTask().toJson(),
      isTombstone: false,
      schemaVersion: 1,
    );
    var requestCount = 0;
    final api = HttpSyncApi(
      baseUri: Uri.parse('https://api.studyflow.test'),
      client: MockClient((request) async {
        requestCount += 1;
        expect(request.headers['authorization'], 'Bearer access-token');
        expect(request.headers.containsKey('x-device-id'), isFalse);
        if (request.method == 'POST') {
          expect(request.url.path, '/v1/sync/push');
          expect(jsonDecode(request.body), <String, Object?>{
            'operations': <Object?>[operation.toJson()],
          });
          return http.Response(
            jsonEncode(<String, Object?>{
              'accepted': <String>[_operationId],
              'duplicates': <String>[],
              'rejected': <String>[],
            }),
            200,
          );
        }
        expect(request.url.path, '/v1/sync/pull');
        expect(request.url.queryParameters, <String, String>{
          'after': '7',
          'limit': '50',
        });
        return http.Response(
          jsonEncode(<String, Object?>{
            'next_cursor': 8,
            'operations': <Object?>[operation.toJson()],
          }),
          200,
        );
      }),
    );

    final pushed = await api.push(
      authContext: testAuthContext(),
      operations: <SyncOperationV2>[operation],
    );
    final pulled = await api.pull(
      authContext: testAuthContext(),
      after: 7,
    );

    expect(pushed.accepted, <String>[_operationId]);
    expect(pulled.nextCursor, 8);
    expect(pulled.operations.single.toJson(), operation.toJson());
    expect(requestCount, 2);
  });

  test('HTTP 409 and 422 are typed protocol/schema failures', () async {
    final responses = <http.Response>[
      http.Response('{}', 409),
      http.Response('{}', 422),
    ];
    final api = HttpSyncApi(
      baseUri: Uri.parse('https://api.studyflow.test'),
      client: MockClient((_) async => responses.removeAt(0)),
    );

    await expectLater(
      api.push(authContext: testAuthContext(), operations: const []),
      throwsA(isA<SyncConflictFailure>()),
    );
    await expectLater(
      api.push(authContext: testAuthContext(), operations: const []),
      throwsA(isA<SyncSchemaFailure>()),
    );
  });

  test('app providers expose a usable engine and its status', () async {
    final api = ScriptedSyncApi();
    final fixture = await testEngine(api: api, seedPendingTask: false);
    final container = ProviderContainer(
      overrides: <Override>[
        appSyncDependenciesProvider.overrideWithValue(
          AppSyncDependencies(
            api: api,
            authContext: testAuthContext(),
            store: fixture.store,
          ),
        ),
      ],
    );
    addTearDown(container.dispose);

    final engine = container.read(syncEngineProvider);

    expect(engine, isNotNull);
    expect(container.read(syncStatusProvider), same(engine!.status));
  });

  test('authentication failure retains the pending queue', () async {
    await expectFailureRetainsQueue(
      const SyncAuthenticationFailure('expired'),
      SyncFailureCategory.authentication,
    );
  });

  test('schema failure retains the pending queue', () async {
    await expectFailureRetainsQueue(
      const SyncSchemaFailure('invalid'),
      SyncFailureCategory.schema,
    );
  });

  test('malformed pulled payload rolls back record apply and cursor',
      () async {
    final api = ScriptedSyncApi();
    final fixture = await testEngine(api: api, seedPendingTask: false);
    api
      ..nextCursor = 1
      ..pulledOperations = <SyncOperationV2>[
        await fixture.contractOperation(
          operationId: '13131313-1313-4313-8313-131313131313',
          recordId: '15151515-1515-4515-8515-151515151515',
          logicalClock: 1,
          entityType: 'check_in',
          payload: const <String, Object?>{
            'id': '15151515-1515-4515-8515-151515151515',
          },
        ),
      ];

    final result = await fixture.engine.runOnce();

    expect(result.failureCategory, SyncFailureCategory.schema);
    expect(await fixture.taskRepository.get(_taskId), isNull);
    expect(await fixture.store.operations.lastCommittedCursor(), 0);
  });

  test('invalid later pull rolls back an earlier record write and cursor',
      () async {
    final api = ScriptedSyncApi();
    final fixture = await testEngine(api: api, seedPendingTask: false);
    api
      ..nextCursor = 9
      ..pulledOperations = <SyncOperationV2>[
        await fixture.contractOperation(
          operationId: '19191919-1919-4919-8919-191919191919',
          recordId: _taskId,
          logicalClock: 1,
          entityType: 'task',
          payload: testTask(title: 'Should roll back').toJson(),
        ),
        await fixture.contractOperation(
          operationId: '20202020-2020-4020-8020-202020202020',
          recordId: '21212121-2121-4121-8121-212121212121',
          logicalClock: 2,
          entityType: 'check_in',
          payload: const <String, Object?>{
            'id': '21212121-2121-4121-8121-212121212121',
          },
        ),
      ];

    final result = await fixture.engine.runOnce();

    expect(result.failureCategory, SyncFailureCategory.schema);
    expect(await fixture.taskRepository.get(_taskId), isNull);
    expect(await fixture.store.operations.lastCommittedCursor(), 0);
  });

  test('push success then pull failure removes acked queue but not cursor',
      () async {
    final fixture = await testEngine(api: PushThenPullFailureApi());

    final result = await fixture.engine.runOnce();

    expect(result.failureCategory, SyncFailureCategory.network);
    expect(result.pushedCount, 1);
    expect(await fixture.engine.pendingCount(), 0);
    expect(await fixture.store.operations.lastCommittedCursor(), 0);
    expect(fixture.engine.status.value.kind, SyncStatusKind.failed);
    expect(fixture.engine.status.value.retry, isNotNull);
  });

  test('cursor state is isolated between account stores', () async {
    final accountAStore = await openAccountStore(_accountId);
    const accountB = '23232323-2323-4323-8323-232323232323';
    final accountBStore = await openAccountStore(accountB);

    await accountAStore.operations.commitCursor(11);
    expect(await accountAStore.operations.lastCommittedCursor(), 11);
    expect(await accountBStore.operations.lastCommittedCursor(), 0);

    await accountBStore.operations.commitCursor(22);
    expect(await accountBStore.operations.lastCommittedCursor(), 22);
    expect(await accountAStore.operations.lastCommittedCursor(), 11);
  });

  test('captured pushed payload is plaintext JSON', () async {
    final api = ScriptedSyncApi();
    final fixture = await testEngine(api: api);

    await fixture.engine.runOnce();

    final captured = jsonDecode(
      jsonEncode(api.capturedPushes.single.toJson()),
    ) as Map<String, dynamic>;
    expect(captured, contains('payload'));
    expect(jsonEncode(captured['payload']), contains('Algebra'));
    expect(jsonEncode(captured['payload']), contains('Chapter 1'));
  });

  test('sync logging exposes metadata only, never record payloads',
      () async {
    final logger = CapturingSyncLogger();
    final fixture = await testEngine(
      api: ScriptedSyncApi(),
      logger: logger,
    );

    await fixture.engine.runOnce();

    final captured = jsonEncode(
      logger.events.map((event) => event.toJson()).toList(growable: false),
    );
    expect(captured, contains(_operationId));
    expect(captured, isNot(contains('Algebra')));
    expect(captured, isNot(contains('Chapter 1')));
  });
}

Future<void> expectFailureRetainsQueue(
  SyncApiFailure failure,
  SyncFailureCategory category,
) async {
  final fixture = await testEngine(api: AlwaysFailingSyncApi(failure));

  final result = await fixture.engine.runOnce();

  expect(result.failureCategory, category);
  expect(await fixture.engine.pendingCount(), 1);
  expect(fixture.engine.status.value.retry, isNotNull);
}

final class FailingSyncApi implements SyncApi {
  FailingSyncApi({required this.failuresRemaining});

  int failuresRemaining;
  final List<String> events = <String>[];

  @override
  Future<SyncPushResult> push({
    required AuthContext authContext,
    required List<SyncOperationV2> operations,
  }) async {
    events.add('push');
    if (failuresRemaining > 0) {
      failuresRemaining -= 1;
      throw const SyncNetworkFailure('network unavailable');
    }
    return SyncPushResult(
      accepted: operations.map((operation) => operation.operationId).toList(),
      duplicates: const <String>[],
      rejected: const <String>[],
    );
  }

  @override
  Future<SyncPullResult> pull({
    required AuthContext authContext,
    required int after,
    int limit = 50,
  }) async {
    events.add('pull:$after');
    return SyncPullResult(
      nextCursor: after,
      operations: const <SyncOperationV2>[],
    );
  }
}

final class ScriptedSyncApi implements SyncApi {
  List<SyncOperationV2> pulledOperations = <SyncOperationV2>[];
  int nextCursor = 0;
  final List<SyncOperationV2> capturedPushes = <SyncOperationV2>[];

  @override
  Future<SyncPushResult> push({
    required AuthContext authContext,
    required List<SyncOperationV2> operations,
  }) async {
    capturedPushes.addAll(operations);
    return SyncPushResult(
      accepted: operations.map((operation) => operation.operationId).toList(),
      duplicates: const <String>[],
      rejected: const <String>[],
    );
  }

  @override
  Future<SyncPullResult> pull({
    required AuthContext authContext,
    required int after,
    int limit = 50,
  }) async =>
      SyncPullResult(
        nextCursor: nextCursor,
        operations: pulledOperations,
      );
}

final class PagedSyncApi implements SyncApi {
  List<List<SyncOperationV2>> pages = <List<SyncOperationV2>>[];

  @override
  Future<SyncPushResult> push({
    required AuthContext authContext,
    required List<SyncOperationV2> operations,
  }) async =>
      SyncPushResult(
        accepted: operations.map((operation) => operation.operationId).toList(),
        duplicates: const <String>[],
        rejected: const <String>[],
      );

  @override
  Future<SyncPullResult> pull({
    required AuthContext authContext,
    required int after,
    int limit = 50,
  }) async {
    final operations = pages.isEmpty ? <SyncOperationV2>[] : pages.removeAt(0);
    return SyncPullResult(
        nextCursor: operations.isEmpty ? after : after + 1,
        operations: operations);
  }
}

final class MalformedAckApi implements SyncApi {
  @override
  Future<SyncPushResult> push({
    required AuthContext authContext,
    required List<SyncOperationV2> operations,
  }) async =>
      SyncPushResult(
        accepted: const <String>['not-a-uuid'],
        duplicates: const <String>[],
        rejected: const <String>[],
      );

  @override
  Future<SyncPullResult> pull({
    required AuthContext authContext,
    required int after,
    int limit = 50,
  }) async =>
      SyncPullResult(nextCursor: after, operations: const []);
}

final class OmittedAckApi implements SyncApi {
  @override
  Future<SyncPushResult> push({
    required AuthContext authContext,
    required List<SyncOperationV2> operations,
  }) async =>
      SyncPushResult(
        accepted: const <String>[],
        duplicates: const <String>[],
        rejected: const <String>[],
      );

  @override
  Future<SyncPullResult> pull({
    required AuthContext authContext,
    required int after,
    int limit = 50,
  }) async =>
      SyncPullResult(nextCursor: after, operations: const []);
}

final class DuplicateAckApi implements SyncApi {
  @override
  Future<SyncPushResult> push({
    required AuthContext authContext,
    required List<SyncOperationV2> operations,
  }) async =>
      SyncPushResult(
        accepted: <String>[
          operations.single.operationId,
          operations.single.operationId,
        ],
        duplicates: const <String>[],
        rejected: const <String>[],
      );

  @override
  Future<SyncPullResult> pull({
    required AuthContext authContext,
    required int after,
    int limit = 50,
  }) async =>
      SyncPullResult(nextCursor: after, operations: const []);
}

final class CapturingSyncLogger implements SyncLogger {
  final List<SyncLogEvent> events = <SyncLogEvent>[];

  @override
  void write(SyncLogEvent event) => events.add(event);
}

final class PushThenPullFailureApi implements SyncApi {
  @override
  Future<SyncPushResult> push({
    required AuthContext authContext,
    required List<SyncOperationV2> operations,
  }) async =>
      SyncPushResult(
        accepted: operations.map((operation) => operation.operationId).toList(),
        duplicates: const <String>[],
        rejected: const <String>[],
      );

  @override
  Future<SyncPullResult> pull({
    required AuthContext authContext,
    required int after,
    int limit = 50,
  }) async =>
      throw const SyncNetworkFailure('pull unavailable');
}

final class AlwaysFailingSyncApi implements SyncApi {
  const AlwaysFailingSyncApi(this.failure);

  final SyncApiFailure failure;

  @override
  Future<SyncPullResult> pull({
    required AuthContext authContext,
    required int after,
    int limit = 50,
  }) async =>
      throw failure;

  @override
  Future<SyncPushResult> push({
    required AuthContext authContext,
    required List<SyncOperationV2> operations,
  }) async =>
      throw failure;
}

Future<TestEngineFixture> testEngine({
  required SyncApi api,
  bool seedPendingTask = true,
  SyncLogger? logger,
}) async {
  final temporaryDirectory =
      await Directory.systemTemp.createTemp('studyflow-sync-engine-');
  final store = await AccountScopedStore.openForTesting(
    activeAccountId: _accountId,
    baseDirectory: temporaryDirectory,
  );
  addTearDown(() async {
    await store.close();
    await temporaryDirectory.delete(recursive: true);
  });
  final taskRepository = TaskRepository(
    store: store,
  );
  if (seedPendingTask) {
    await taskRepository.save(
      testTask(),
      write: Write(
        operationId: _operationId,
        logicalClock: 1,
      ),
    );
  }
  final engine = SyncEngine(
    api: api,
    authContext: testAuthContext(),
    store: store,
    logger: logger,
  );
  addTearDown(engine.dispose);
  return TestEngineFixture(
    engine: engine,
    store: store,
    taskRepository: taskRepository,
  );
}

Future<AccountScopedStore> openAccountStore(String accountId) async {
  final directory =
      await Directory.systemTemp.createTemp('studyflow-account-scope-');
  final store = await AccountScopedStore.openForTesting(
    activeAccountId: accountId,
    baseDirectory: directory,
  );
  addTearDown(() async {
    await store.close();
    await directory.delete(recursive: true);
  });
  return store;
}

AuthContext testAuthContext() => AuthContext(
      userId: _accountId,
      email: 'user@example.com',
      accessToken: 'access-token',
      refreshToken: 'refresh-token',
      expiresIn: 900,
    );

Task testTask({
  String id = _taskId,
  String title = 'Algebra',
  TaskStatus status = TaskStatus.todo,
}) =>
    Task(
      id: id,
      title: title,
      description: 'Chapter 1',
      estimatedMinutes: 25,
      priority: TaskPriority.normal,
      status: status,
      tags: const <String>['math'],
      repeatRule: RepeatRule.none,
    );

ScheduleBlock testScheduleBlock({
  required String id,
  DateTime? start,
  DateTime? end,
}) =>
    ScheduleBlock(
      id: id,
      start: start ?? DateTime.utc(2026, 8, 11, 8),
      end: end ?? DateTime.utc(2026, 8, 11, 9),
      kind: ScheduleBlockKind.task,
      taskId: _taskId,
      source: ScheduleBlockSource.manual,
      isLocked: false,
    );

final class TestEngineFixture {
  const TestEngineFixture({
    required this.engine,
    required this.store,
    required this.taskRepository,
  });

  final SyncEngine engine;
  final AccountScopedStore store;
  final TaskRepository taskRepository;

  Future<SyncOperationV2> contractOperation({
    required String operationId,
    required String recordId,
    required int logicalClock,
    required String entityType,
    required Map<String, Object?> payload,
    bool isTombstone = false,
  }) async =>
      SyncOperationV2(
        operationId: operationId,
        recordId: recordId,
        logicalClock: logicalClock,
        entityType: entityType,
        payload: payload,
        isTombstone: isTombstone,
        schemaVersion: 1,
      );

  Operation asOperation(SyncOperationV2 operation) => Operation(
        accountId: _accountId,
        operationId: operation.operationId,
        recordId: operation.recordId,
        logicalClock: operation.logicalClock,
        entityType: operation.entityType,
        payload: operation.payload,
        isTombstone: operation.isTombstone,
        schemaVersion: operation.schemaVersion,
      );

  Future<void> seedRecord({
    required String operationId,
    required String recordId,
    required int logicalClock,
    required String entityType,
    required Map<String, Object?> payload,
  }) async {
    final operation = Operation(
      accountId: _accountId,
      operationId: operationId,
      recordId: recordId,
      logicalClock: logicalClock,
      entityType: entityType,
      payload: payload,
      isTombstone: false,
      schemaVersion: 1,
    );
    await store.transaction((transaction) async {
      await transaction.putRecord(
        LocalRecord(
          accountId: _accountId,
          recordId: recordId,
          entityType: EntityType.values.singleWhere(
            (value) => value.wireName == entityType,
          ),
          schemaVersion: 1,
          payload: jsonEncode(payload),
          updatedAt: DateTime.now().toUtc(),
        ),
      );
      await transaction.enqueue(operation);
    });
  }

  Future<FocusSession?> readFocusSession(String recordId) async {
    final record = await store.records(EntityType.focusSession).get(
          accountId: _accountId,
          recordId: recordId,
        );
    if (record == null) {
      return null;
    }
    return FocusSession.fromJson(
      (jsonDecode(record.payload) as Map<String, dynamic>)
          .cast<String, Object?>(),
    );
  }
}
