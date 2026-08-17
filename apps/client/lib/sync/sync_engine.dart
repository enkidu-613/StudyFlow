import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:studyflow/auth/auth_repository.dart';
import 'package:studyflow/storage/app_database.dart';
import 'package:studyflow/sync/sync_api.dart';
import 'package:studyflow/sync/sync_logger.dart';
import 'package:studyflow/sync/sync_status.dart';
import 'package:studyflow_domain/domain.dart';
import 'package:studyflow_sync_contract/sync_contract.dart';

export 'sync_logger.dart';

const Set<String> _taskFields = <String>{
  'title',
  'description',
  'estimatedMinutes',
  'priority',
  'status',
  'tags',
  'repeatRule',
};

final class SyncEngine {
  SyncEngine({
    required SyncApi api,
    required AuthContext authContext,
    required AccountScopedStore store,
    SyncLogger? logger,
    this.refreshAuthContext,
    this.batchSize = 50,
  })  : _api = api,
        _authContext = authContext,
        _store = store,
        _logger = logger ?? const NoopSyncLogger(),
        _status =
            ValueNotifier<SyncStatus>(const SyncStatus.idle(pendingCount: 0)) {
    if (store.activeAccountId != authContext.userId) {
      throw const AuthScopeException(
        'Sync storage does not match the authenticated account.',
      );
    }
    if (batchSize < 1 || batchSize > 200) {
      throw ArgumentError.value(
          batchSize, 'batchSize', 'must be 1 through 200');
    }
  }

  final SyncApi _api;
  AuthContext _authContext;
  final AccountScopedStore _store;
  final SyncLogger _logger;
  final Future<AuthContext> Function()? refreshAuthContext;
  final int batchSize;
  final ValueNotifier<SyncStatus> _status;

  ValueListenable<SyncStatus> get status => _status;

  Future<int> pendingCount() => _store.operations.pendingCount();

  Future<SyncRunResult> runOnce() => _runOnce(allowAuthenticationRefresh: true);

  void replaceAuthContext(AuthContext authContext) {
    if (authContext.userId != _store.activeAccountId) {
      throw const AuthScopeException(
        'Refreshed credentials do not match the active sync account.',
      );
    }
    _authContext = authContext;
  }

  Future<SyncRunResult> _runOnce({
    required bool allowAuthenticationRefresh,
  }) async {
    final queuedBefore = await pendingCount();
    _status.value = SyncStatus.syncing(pendingCount: queuedBefore);
    var pushedCount = 0;
    var cursor = await _store.operations.lastCommittedCursor();
    try {
      final pending = await _store.operations.pending(batchSize);
      _log(
        SyncLogEventKind.started,
        operationIds: pending.map((operation) => operation.operationId),
        pendingCount: queuedBefore,
        cursor: cursor,
      );
      if (pending.isNotEmpty) {
        final taskFieldsByOperation = await _taskFieldsByOperation(pending);
        final pushResult = await _api.push(
          authContext: _authContext,
          operations: pending.map(_toContract).toList(growable: false),
        );
        final acknowledged = <String>{
          ...pushResult.accepted,
          ...pushResult.duplicates,
        };
        _validatePushAcknowledgement(pending, pushResult);
        if (pushResult.rejected.isNotEmpty) {
          throw const SyncSchemaFailure(
            'The server rejected one or more operations.',
          );
        }
        await _store.operations.removeAcknowledged(
          acknowledged,
          taskFieldsByOperation: taskFieldsByOperation,
        );
        pushedCount = acknowledged.length;
        _log(
          SyncLogEventKind.pushSucceeded,
          operationIds: acknowledged,
          pushedCount: pushedCount,
          pendingCount: queuedBefore - pushedCount,
        );
      }

      final pullResult = await _api.pull(
        authContext: _authContext,
        after: cursor,
        limit: batchSize,
      );
      final applied = await _store.operations.applyPullPage(
        operations: pullResult.operations.map(_fromContract).toList(),
        nextCursor: pullResult.nextCursor,
        resolve: _resolvePull,
      );
      cursor = pullResult.nextCursor;
      final remaining = await pendingCount();
      _log(
        SyncLogEventKind.pullApplied,
        operationIds:
            pullResult.operations.map((operation) => operation.operationId),
        pulledCount: applied.appliedCount,
        pendingCount: remaining,
        cursor: cursor,
      );
      _status.value = SyncStatus.idle(pendingCount: remaining);
      return SyncRunResult(
        outcome: SyncRunOutcome.succeeded,
        pushedCount: pushedCount,
        pulledCount: applied.appliedCount,
        pendingCount: remaining,
        cursor: cursor,
      );
    } on SyncOfflineFailure {
      return _failureResult(
        SyncStatusKind.offline,
        SyncFailureCategory.network,
        pushedCount,
        cursor,
      );
    } on SyncNetworkFailure {
      return _failureResult(
        SyncStatusKind.failed,
        SyncFailureCategory.network,
        pushedCount,
        cursor,
      );
    } on SyncAuthenticationFailure {
      final refresh = refreshAuthContext;
      if (allowAuthenticationRefresh && refresh != null) {
        try {
          replaceAuthContext(await refresh());
          return _runOnce(allowAuthenticationRefresh: false);
        } on Object {
          // A rejected or unusable refresh token is surfaced as the existing
          // authentication failure state, without introducing a retry loop.
        }
      }
      return _failureResult(
        SyncStatusKind.failed,
        SyncFailureCategory.authentication,
        pushedCount,
        cursor,
      );
    } on SyncConflictFailure {
      return _failureResult(
        SyncStatusKind.failed,
        SyncFailureCategory.protocol,
        pushedCount,
        cursor,
      );
    } on SyncProtocolFailure {
      return _failureResult(
        SyncStatusKind.failed,
        SyncFailureCategory.protocol,
        pushedCount,
        cursor,
      );
    } on SyncSchemaFailure {
      return _failureResult(
        SyncStatusKind.failed,
        SyncFailureCategory.schema,
        pushedCount,
        cursor,
      );
    }
  }

  void _validatePushAcknowledgement(
    List<Operation> pending,
    SyncPushResult result,
  ) {
    final pendingIds =
        pending.map((operation) => operation.operationId).toSet();
    final accepted = result.accepted.toSet();
    final duplicates = result.duplicates.toSet();
    final rejected = result.rejected.toSet();
    final acknowledged = <String>{...accepted, ...duplicates};
    if (accepted.intersection(duplicates).isNotEmpty ||
        accepted.intersection(rejected).isNotEmpty ||
        duplicates.intersection(rejected).isNotEmpty ||
        result.accepted.length != accepted.length ||
        result.duplicates.length != duplicates.length ||
        result.rejected.length != rejected.length ||
        acknowledged.length + rejected.length != pendingIds.length ||
        !pendingIds.containsAll(<String>{...acknowledged, ...rejected})) {
      throw const SyncProtocolFailure(
        'Synchronization acknowledgement does not match the pending queue.',
      );
    }
  }

  Future<Map<String, Set<String>>> _taskFieldsByOperation(
    List<Operation> operations,
  ) async {
    final result = <String, Set<String>>{};
    for (final operation in operations) {
      if (operation.entityType != EntityType.task.wireName) {
        continue;
      }
      final snapshot = await _store.operations.snapshotFor(operation);
      final baseVersion = snapshot.previousVersion ?? snapshot.currentVersion;
      if (baseVersion == null) {
        result[operation.operationId] = Set<String>.from(_taskFields);
        continue;
      }
      final currentJson = operation.payload;
      final baseJson = baseVersion.payload;
      result[operation.operationId] = <String>{
        for (final field in _taskFields)
          if (!_jsonValueEquals(currentJson[field], baseJson[field])) field,
      };
    }
    return result;
  }

  Future<SyncRunResult> _failureResult(
    SyncStatusKind kind,
    SyncFailureCategory category,
    int pushedCount,
    int cursor,
  ) async {
    final remaining = await pendingCount();
    _log(
      SyncLogEventKind.failed,
      pendingCount: remaining,
      cursor: cursor,
      failureCategory: category,
    );
    _status.value = SyncStatus(
      kind: kind,
      pendingCount: remaining,
      failureCategory: category,
      retry: runOnce,
    );
    return SyncRunResult(
      outcome: SyncRunOutcome.failed,
      pushedCount: pushedCount,
      pulledCount: 0,
      pendingCount: remaining,
      cursor: cursor,
      failureCategory: category,
    );
  }

  SyncOperationV2 _toContract(Operation operation) {
    if (operation.accountId != _authContext.userId) {
      throw const SyncAuthenticationFailure(
        'Queued operation does not match the active account.',
      );
    }
    return SyncOperationV2(
      operationId: operation.operationId,
      recordId: operation.recordId,
      logicalClock: operation.logicalClock,
      entityType: operation.entityType,
      payload: operation.payload,
      isTombstone: operation.isTombstone,
      schemaVersion: operation.schemaVersion,
    );
  }

  void _log(
    SyncLogEventKind kind, {
    Iterable<String> operationIds = const <String>[],
    int? pushedCount,
    int? pulledCount,
    int? pendingCount,
    int? cursor,
    SyncFailureCategory? failureCategory,
  }) {
    _logger.write(
      SyncLogEvent(
        kind: kind,
        operationIds: operationIds.toList(growable: false),
        pushedCount: pushedCount,
        pulledCount: pulledCount,
        pendingCount: pendingCount,
        cursor: cursor,
        failureCategory: failureCategory,
      ),
    );
  }

  Operation _fromContract(SyncOperationV2 operation) {
    try {
      return Operation(
        accountId: _authContext.userId,
        operationId: operation.operationId,
        recordId: operation.recordId,
        logicalClock: operation.logicalClock,
        entityType: operation.entityType,
        payload: operation.payload,
        isTombstone: operation.isTombstone,
        schemaVersion: operation.schemaVersion,
      );
    } on Object catch (error) {
      throw SyncSchemaFailure('Pulled operation was invalid.', cause: error);
    }
  }

  Future<SyncRecordMutation> _resolvePull(
    Operation operation,
    SyncRecordSnapshot snapshot,
  ) async {
    late final Map<String, Object?> remoteJson;
    try {
      remoteJson = operation.payload;
      if (operation.entityType == EntityType.task.wireName) {
        final task = Task.fromJson(remoteJson);
        if (task.id != operation.recordId) {
          throw const FormatException('Task id does not match record id.');
        }
      } else if (operation.entityType == EntityType.scheduleBlock.wireName) {
        final block = ScheduleBlock.fromJson(remoteJson);
        if (block.id != operation.recordId) {
          throw const FormatException(
            'Schedule block id does not match record id.',
          );
        }
      } else if (operation.entityType == EntityType.focusSession.wireName) {
        final session = FocusSession.fromJson(remoteJson);
        if (session.id != operation.recordId) {
          throw const FormatException(
            'Focus session id does not match record id.',
          );
        }
      } else if (operation.entityType == EntityType.checkIn.wireName) {
        final checkIn = CheckIn.fromJson(remoteJson);
        if (checkIn.id != operation.recordId) {
          throw const FormatException('Check-in id does not match record id.');
        }
      } else if (operation.entityType == EntityType.scheduleFeedback.wireName) {
        final feedback = ScheduleFeedback.fromJson(remoteJson);
        if (feedback.id != operation.recordId) {
          throw const FormatException(
            'Schedule feedback id does not match record id.',
          );
        }
      } else if (operation.entityType == EntityType.medicationPlan.wireName) {
        final plan = MedicationPlan.fromJson(remoteJson);
        if (plan.id != operation.recordId) {
          throw const FormatException('Medication plan id does not match record id.');
        }
      } else if (operation.entityType == EntityType.medicationDoseRecord.wireName) {
        final record = MedicationDoseRecord.fromJson(remoteJson);
        if (record.id != operation.recordId) {
          throw const FormatException('Medication dose record id does not match record id.');
        }
      }
    } on Object catch (error) {
      throw SyncSchemaFailure(
        'Pulled operation did not match the supported schema.',
        cause: error,
      );
    }

    if (operation.isTombstone) {
      final currentVersion = snapshot.currentVersion;
      final shouldDelete = currentVersion == null ||
          _compareStamp(operation, currentVersion) >= 0;
      return SyncRecordMutation(
        recordIdsToDelete:
            shouldDelete ? <String>[operation.recordId] : const <String>[],
        recordIncomingVersion: false,
      );
    }

    if (operation.entityType == EntityType.task.wireName &&
        snapshot.record != null) {
      return _mergeTask(operation, snapshot, remoteJson);
    }
    if (operation.entityType == EntityType.scheduleBlock.wireName &&
        snapshot.record != null) {
      return _mergeSchedule(operation, snapshot, remoteJson);
    }
    if (operation.entityType == EntityType.focusSession.wireName &&
        snapshot.record != null) {
      return _mergeFocusSession(operation, snapshot, remoteJson);
    }

    return SyncRecordMutation(
      recordsToPut: <LocalRecord>[_localRecord(operation)],
    );
  }

  Future<SyncRecordMutation> _mergeTask(
    Operation remoteOperation,
    SyncRecordSnapshot snapshot,
    Map<String, Object?> remotePayload,
  ) async {
    final localTask = Task.fromJson(_recordJson(snapshot.record!));
    final remoteTask = Task.fromJson(remotePayload);
    final localJson = localTask.toJson();
    final remoteJson = remoteTask.toJson();
    final baseJson = snapshot.previousVersion?.payload;
    final mergedJson = <String, Object?>{'id': localJson['id']};
    final acceptedFields = <String>{};
    for (final field in _taskFields) {
      final remoteChanged = baseJson == null ||
          !_jsonValueEquals(remoteJson[field], baseJson[field]);
      final currentStamp = snapshot.taskFieldVersions[field] ??
          (snapshot.currentVersion == null
              ? null
              : SyncFieldVersion(
                  logicalClock: snapshot.currentVersion!.logicalClock,
                  operationId: snapshot.currentVersion!.operationId,
                ));
      if (remoteChanged &&
          _compareTaskFieldStamp(remoteOperation, currentStamp) > 0) {
        mergedJson[field] = remoteJson[field];
        acceptedFields.add(field);
      } else {
        mergedJson[field] = localJson[field];
      }
    }
    if (acceptedFields.isEmpty) {
      return SyncRecordMutation(recordIncomingVersion: false);
    }

    final canonicalVersion = Operation(
      accountId: remoteOperation.accountId,
      operationId: remoteOperation.operationId,
      recordId: remoteOperation.recordId,
      logicalClock: remoteOperation.logicalClock,
      entityType: remoteOperation.entityType,
      payload: Task.fromJson(mergedJson).toJson(),
      isTombstone: false,
      schemaVersion: remoteOperation.schemaVersion,
    );
    return SyncRecordMutation(
      recordsToPut: <LocalRecord>[_localRecord(canonicalVersion)],
      versionOperation: canonicalVersion,
      taskFieldsToStamp: acceptedFields,
    );
  }

  Future<SyncRecordMutation> _mergeSchedule(
    Operation remoteOperation,
    SyncRecordSnapshot snapshot,
    Map<String, Object?> remoteJson,
  ) async {
    final localBlock = ScheduleBlock.fromJson(_recordJson(snapshot.record!));
    final remoteBlock = ScheduleBlock.fromJson(remoteJson);
    final localVersion = snapshot.currentVersion;
    final isSimultaneous = localVersion != null &&
        localVersion.logicalClock == remoteOperation.logicalClock &&
        localVersion.operationId != remoteOperation.operationId;
    if (isSimultaneous &&
        !_jsonValueEquals(localBlock.toJson(), remoteBlock.toJson())) {
      final conflictJson = Map<String, Object?>.from(remoteBlock.toJson())
        ..['id'] = remoteOperation.operationId;
      final conflictBlock = ScheduleBlock.fromJson(conflictJson);
      final conflictVersion = Operation(
        accountId: remoteOperation.accountId,
        operationId: remoteOperation.operationId,
        recordId: conflictBlock.id,
        logicalClock: remoteOperation.logicalClock,
        entityType: remoteOperation.entityType,
        payload: conflictBlock.toJson(),
        isTombstone: false,
        schemaVersion: remoteOperation.schemaVersion,
      );
      return SyncRecordMutation(
        recordsToPut: <LocalRecord>[_localRecord(conflictVersion)],
        versionOperation: conflictVersion,
      );
    }
    if (localVersion != null &&
        _compareStamp(remoteOperation, localVersion) < 0) {
      return SyncRecordMutation();
    }
    return SyncRecordMutation(
      recordsToPut: <LocalRecord>[_localRecord(remoteOperation)],
    );
  }

  Future<SyncRecordMutation> _mergeFocusSession(
    Operation remoteOperation,
    SyncRecordSnapshot snapshot,
    Map<String, Object?> remoteJson,
  ) async {
    final localSession = FocusSession.fromJson(_recordJson(snapshot.record!));
    final remoteSession = FocusSession.fromJson(remoteJson);
    if (!localSession.isFinished) {
      return SyncRecordMutation(
        recordsToPut: <LocalRecord>[_localRecord(remoteOperation)],
      );
    }
    if (_jsonValueEquals(localSession.toJson(), remoteSession.toJson())) {
      return SyncRecordMutation();
    }

    final conflictJson = Map<String, Object?>.from(remoteSession.toJson())
      ..['id'] = remoteOperation.operationId;
    final conflictSession = FocusSession.fromJson(conflictJson);
    final conflictVersion = Operation(
      accountId: remoteOperation.accountId,
      operationId: remoteOperation.operationId,
      recordId: conflictSession.id,
      logicalClock: remoteOperation.logicalClock,
      entityType: remoteOperation.entityType,
      payload: conflictSession.toJson(),
      isTombstone: false,
      schemaVersion: remoteOperation.schemaVersion,
    );
    return SyncRecordMutation(
      recordsToPut: <LocalRecord>[_localRecord(conflictVersion)],
      versionOperation: conflictVersion,
    );
  }

  bool _jsonValueEquals(Object? left, Object? right) =>
      jsonEncode(left) == jsonEncode(right);

  int _compareTaskFieldStamp(Operation incoming, SyncFieldVersion? current) {
    if (current == null) {
      return 1;
    }
    final clockComparison =
        incoming.logicalClock.compareTo(current.logicalClock);
    return clockComparison == 0
        ? incoming.operationId.compareTo(current.operationId)
        : clockComparison;
  }

  int _compareStamp(Operation left, Operation right) {
    final clockComparison = left.logicalClock.compareTo(right.logicalClock);
    return clockComparison != 0
        ? clockComparison
        : left.operationId.compareTo(right.operationId);
  }

  Map<String, Object?> _recordJson(LocalRecord record) {
    try {
      final payload = jsonDecode(record.payload);
      if (payload is! Map) {
        throw const FormatException('Payload must be an object.');
      }
      return payload.cast<String, Object?>();
    } on Object catch (error) {
      throw SyncSchemaFailure(
        'Local record did not match the supported schema.',
        cause: error,
      );
    }
  }

  LocalRecord _localRecord(Operation operation) => LocalRecord(
        accountId: operation.accountId,
        recordId: operation.recordId,
        entityType: _entityType(operation.entityType),
        schemaVersion: operation.schemaVersion,
        payload: jsonEncode(operation.payload),
        updatedAt: DateTime.now().toUtc(),
      );

  EntityType _entityType(String wireName) => EntityType.values.singleWhere(
        (entityType) => entityType.wireName == wireName,
      );

  void dispose() => _status.dispose();
}
