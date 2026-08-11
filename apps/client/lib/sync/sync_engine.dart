import 'dart:convert';

import 'package:cryptography/cryptography.dart';
import 'package:flutter/foundation.dart';
import 'package:studyflow/auth/auth_repository.dart';
import 'package:studyflow/security/payload_cipher.dart';
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
    required PayloadCipher cipher,
    SyncLogger? logger,
    this.batchSize = 50,
  })  : _api = api,
        _authContext = authContext,
        _store = store,
        _cipher = cipher,
        _logger = logger ?? const NoopSyncLogger(),
        _status =
            ValueNotifier<SyncStatus>(const SyncStatus.idle(pendingCount: 0)) {
    if (store.activeAccountId != authContext.accountId) {
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
  final AuthContext _authContext;
  final AccountScopedStore _store;
  final PayloadCipher _cipher;
  final SyncLogger _logger;
  final int batchSize;
  final ValueNotifier<SyncStatus> _status;

  ValueListenable<SyncStatus> get status => _status;

  Future<int> pendingCount() => _store.operations.pendingCount();

  Future<SyncRunResult> runOnce() async {
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
            'The server rejected one or more encrypted operations.',
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
    } on SyncDecryptionFailure {
      return _failureResult(
        SyncStatusKind.failed,
        SyncFailureCategory.decryption,
        pushedCount,
        cursor,
      );
    }
  }

  void _validatePushAcknowledgement(
    List<EncryptedOperation> pending,
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
    List<EncryptedOperation> operations,
  ) async {
    final result = <String, Set<String>>{};
    for (final operation in operations) {
      if (operation.entityType != EncryptedEntityType.task.wireName) {
        continue;
      }
      final snapshot = await _store.operations.snapshotFor(operation);
      final baseVersion = snapshot.previousVersion ?? snapshot.currentVersion;
      if (baseVersion == null) {
        result[operation.operationId] = Set<String>.from(_taskFields);
        continue;
      }
      final currentJson = _jsonObject(await _decryptOperation(operation));
      final baseJson = _jsonObject(await _decryptOperation(baseVersion));
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

  SyncOperationV1 _toContract(EncryptedOperation operation) {
    if (operation.accountId != _authContext.accountId ||
        operation.deviceId != _authContext.deviceId) {
      throw const SyncAuthenticationFailure(
        'Queued operation does not match the active account and device.',
      );
    }
    return SyncOperationV1(
      operationId: operation.operationId,
      recordId: operation.recordId,
      deviceId: operation.deviceId,
      logicalClock: operation.logicalClock,
      entityType: operation.entityType,
      payloadNonce: base64Encode(operation.payloadNonce),
      payloadCiphertext: base64Encode(operation.payloadCiphertext),
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

  EncryptedOperation _fromContract(SyncOperationV1 operation) {
    try {
      return EncryptedOperation(
        accountId: _authContext.accountId,
        operationId: operation.operationId,
        recordId: operation.recordId,
        deviceId: operation.deviceId,
        logicalClock: operation.logicalClock,
        entityType: operation.entityType,
        payloadNonce: base64Decode(operation.payloadNonce),
        payloadCiphertext: base64Decode(operation.payloadCiphertext),
        isTombstone: operation.isTombstone,
        schemaVersion: operation.schemaVersion,
      );
    } on Object catch (error) {
      throw SyncSchemaFailure('Pulled operation was invalid.', cause: error);
    }
  }

  Future<SyncRecordMutation> _resolvePull(
    EncryptedOperation operation,
    SyncRecordSnapshot snapshot,
  ) async {
    late final Map<String, Object?> remoteJson;
    try {
      final payload =
          jsonDecode(utf8.decode(await _decryptOperation(operation)));
      if (payload is! Map) {
        throw const FormatException('Payload must be an object.');
      }
      remoteJson = payload.cast<String, Object?>();
      if (operation.entityType == EncryptedEntityType.task.wireName) {
        final task = Task.fromJson(remoteJson);
        if (task.id != operation.recordId) {
          throw const FormatException('Task id does not match record id.');
        }
      } else if (operation.entityType ==
          EncryptedEntityType.scheduleBlock.wireName) {
        final block = ScheduleBlock.fromJson(remoteJson);
        if (block.id != operation.recordId) {
          throw const FormatException(
            'Schedule block id does not match record id.',
          );
        }
      } else if (operation.entityType ==
          EncryptedEntityType.focusSession.wireName) {
        final session = FocusSession.fromJson(remoteJson);
        if (session.id != operation.recordId) {
          throw const FormatException(
            'Focus session id does not match record id.',
          );
        }
      } else if (operation.entityType == EncryptedEntityType.checkIn.wireName) {
        final checkIn = CheckIn.fromJson(remoteJson);
        if (checkIn.id != operation.recordId) {
          throw const FormatException('Check-in id does not match record id.');
        }
      }
    } on SyncDecryptionFailure {
      rethrow;
    } on Object catch (error) {
      throw SyncSchemaFailure(
        'Decrypted operation did not match the supported schema.',
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

    if (operation.entityType == EncryptedEntityType.task.wireName &&
        snapshot.record != null) {
      return _mergeTask(operation, snapshot, remoteJson);
    }
    if (operation.entityType == EncryptedEntityType.scheduleBlock.wireName &&
        snapshot.record != null) {
      return _mergeSchedule(operation, snapshot, remoteJson);
    }
    if (operation.entityType == EncryptedEntityType.focusSession.wireName &&
        snapshot.record != null) {
      return _mergeFocusSession(operation, snapshot, remoteJson);
    }

    return SyncRecordMutation(
      recordsToPut: <EncryptedLocalRecord>[_localRecord(operation)],
    );
  }

  Future<SyncRecordMutation> _mergeTask(
    EncryptedOperation remoteOperation,
    SyncRecordSnapshot snapshot,
    Map<String, Object?> remotePayload,
  ) async {
    final localTask = Task.fromJson(await _decryptRecordJson(snapshot.record!));
    final remoteTask = Task.fromJson(remotePayload);
    final localJson = localTask.toJson();
    final remoteJson = remoteTask.toJson();
    final baseJson = snapshot.previousVersion == null
        ? null
        : _jsonObject(await _decryptOperation(snapshot.previousVersion!));
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
                  deviceId: snapshot.currentVersion!.deviceId,
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

    final encrypted = await _cipher.encrypt(
      utf8.encode(jsonEncode(Task.fromJson(mergedJson).toJson())),
      _associatedData(remoteOperation),
    );
    final canonicalVersion = EncryptedOperation(
      accountId: remoteOperation.accountId,
      operationId: remoteOperation.operationId,
      recordId: remoteOperation.recordId,
      deviceId: remoteOperation.deviceId,
      logicalClock: remoteOperation.logicalClock,
      entityType: remoteOperation.entityType,
      payloadNonce: encrypted.nonce,
      payloadCiphertext: encrypted.ciphertext,
      isTombstone: false,
      schemaVersion: remoteOperation.schemaVersion,
    );
    return SyncRecordMutation(
      recordsToPut: <EncryptedLocalRecord>[_localRecord(canonicalVersion)],
      versionOperation: canonicalVersion,
      taskFieldsToStamp: acceptedFields,
    );
  }

  Future<SyncRecordMutation> _mergeSchedule(
    EncryptedOperation remoteOperation,
    SyncRecordSnapshot snapshot,
    Map<String, Object?> remoteJson,
  ) async {
    final localBlock = ScheduleBlock.fromJson(
      await _decryptRecordJson(snapshot.record!),
    );
    final remoteBlock = ScheduleBlock.fromJson(remoteJson);
    final localVersion = snapshot.currentVersion;
    final isSimultaneous = localVersion != null &&
        localVersion.deviceId != remoteOperation.deviceId &&
        localVersion.logicalClock == remoteOperation.logicalClock;
    if (isSimultaneous &&
        !_jsonValueEquals(localBlock.toJson(), remoteBlock.toJson())) {
      final conflictJson = Map<String, Object?>.from(remoteBlock.toJson())
        ..['id'] = remoteOperation.operationId;
      final conflictBlock = ScheduleBlock.fromJson(conflictJson);
      final conflictAssociatedData = PayloadAssociatedData(
        accountId: remoteOperation.accountId,
        recordId: conflictBlock.id,
        schemaVersion: remoteOperation.schemaVersion,
        entityType: remoteOperation.entityType,
      );
      final encrypted = await _cipher.encrypt(
        utf8.encode(jsonEncode(conflictBlock.toJson())),
        conflictAssociatedData,
      );
      final conflictVersion = EncryptedOperation(
        accountId: remoteOperation.accountId,
        operationId: remoteOperation.operationId,
        recordId: conflictBlock.id,
        deviceId: remoteOperation.deviceId,
        logicalClock: remoteOperation.logicalClock,
        entityType: remoteOperation.entityType,
        payloadNonce: encrypted.nonce,
        payloadCiphertext: encrypted.ciphertext,
        isTombstone: false,
        schemaVersion: remoteOperation.schemaVersion,
      );
      return SyncRecordMutation(
        recordsToPut: <EncryptedLocalRecord>[_localRecord(conflictVersion)],
        versionOperation: conflictVersion,
      );
    }
    if (localVersion != null &&
        _compareStamp(remoteOperation, localVersion) < 0) {
      return SyncRecordMutation();
    }
    return SyncRecordMutation(
      recordsToPut: <EncryptedLocalRecord>[_localRecord(remoteOperation)],
    );
  }

  Future<SyncRecordMutation> _mergeFocusSession(
    EncryptedOperation remoteOperation,
    SyncRecordSnapshot snapshot,
    Map<String, Object?> remoteJson,
  ) async {
    final localSession = FocusSession.fromJson(
      await _decryptRecordJson(snapshot.record!),
    );
    final remoteSession = FocusSession.fromJson(remoteJson);
    if (!localSession.isFinished) {
      return SyncRecordMutation(
        recordsToPut: <EncryptedLocalRecord>[_localRecord(remoteOperation)],
      );
    }
    if (_jsonValueEquals(localSession.toJson(), remoteSession.toJson())) {
      return SyncRecordMutation();
    }

    final conflictJson = Map<String, Object?>.from(remoteSession.toJson())
      ..['id'] = remoteOperation.operationId;
    final conflictSession = FocusSession.fromJson(conflictJson);
    final encrypted = await _cipher.encrypt(
      utf8.encode(jsonEncode(conflictSession.toJson())),
      PayloadAssociatedData(
        accountId: remoteOperation.accountId,
        recordId: conflictSession.id,
        schemaVersion: remoteOperation.schemaVersion,
        entityType: remoteOperation.entityType,
      ),
    );
    final conflictVersion = EncryptedOperation(
      accountId: remoteOperation.accountId,
      operationId: remoteOperation.operationId,
      recordId: conflictSession.id,
      deviceId: remoteOperation.deviceId,
      logicalClock: remoteOperation.logicalClock,
      entityType: remoteOperation.entityType,
      payloadNonce: encrypted.nonce,
      payloadCiphertext: encrypted.ciphertext,
      isTombstone: false,
      schemaVersion: remoteOperation.schemaVersion,
    );
    return SyncRecordMutation(
      recordsToPut: <EncryptedLocalRecord>[_localRecord(conflictVersion)],
      versionOperation: conflictVersion,
    );
  }

  bool _jsonValueEquals(Object? left, Object? right) =>
      jsonEncode(left) == jsonEncode(right);

  int _compareTaskFieldStamp(
    EncryptedOperation incoming,
    SyncFieldVersion? current,
  ) {
    if (current == null) {
      return 1;
    }
    final clockComparison =
        incoming.logicalClock.compareTo(current.logicalClock);
    return clockComparison == 0
        ? incoming.deviceId.compareTo(current.deviceId)
        : clockComparison;
  }

  int _compareStamp(EncryptedOperation left, EncryptedOperation right) {
    final clockComparison = left.logicalClock.compareTo(right.logicalClock);
    return clockComparison != 0
        ? clockComparison
        : left.deviceId.compareTo(right.deviceId);
  }

  Future<List<int>> _decryptOperation(EncryptedOperation operation) => _decrypt(
        EncryptedPayload(
          nonce: operation.payloadNonce,
          ciphertext: operation.payloadCiphertext,
        ),
        _associatedData(operation),
      );

  Future<Map<String, Object?>> _decryptRecordJson(
    EncryptedLocalRecord record,
  ) async =>
      _jsonObject(
        await _decrypt(
          EncryptedPayload(
            nonce: record.payloadNonce,
            ciphertext: record.payloadCiphertext,
          ),
          PayloadAssociatedData(
            accountId: record.accountId,
            recordId: record.recordId,
            schemaVersion: record.schemaVersion,
            entityType: record.entityType.wireName,
          ),
        ),
      );

  Future<List<int>> _decrypt(
    EncryptedPayload payload,
    PayloadAssociatedData associatedData,
  ) async {
    try {
      return await _cipher.decrypt(payload, associatedData);
    } on SecretBoxAuthenticationError catch (error) {
      throw SyncDecryptionFailure(
        'Pulled encrypted payload could not be authenticated.',
        cause: error,
      );
    } on FormatException catch (error) {
      throw SyncDecryptionFailure(
        'Pulled encrypted payload was malformed.',
        cause: error,
      );
    }
  }

  Map<String, Object?> _jsonObject(List<int> plaintext) {
    try {
      final payload = jsonDecode(utf8.decode(plaintext));
      if (payload is! Map) {
        throw const FormatException('Payload must be an object.');
      }
      return payload.cast<String, Object?>();
    } on SyncSchemaFailure {
      rethrow;
    } on Object catch (error) {
      throw SyncSchemaFailure(
        'Decrypted operation did not match the supported schema.',
        cause: error,
      );
    }
  }

  PayloadAssociatedData _associatedData(EncryptedOperation operation) =>
      PayloadAssociatedData(
        accountId: operation.accountId,
        recordId: operation.recordId,
        schemaVersion: operation.schemaVersion,
        entityType: operation.entityType,
      );

  EncryptedLocalRecord _localRecord(EncryptedOperation operation) =>
      EncryptedLocalRecord(
        accountId: operation.accountId,
        recordId: operation.recordId,
        entityType: _entityType(operation.entityType),
        schemaVersion: operation.schemaVersion,
        payloadNonce: operation.payloadNonce,
        payloadCiphertext: operation.payloadCiphertext,
        updatedAt: DateTime.now().toUtc(),
      );

  EncryptedEntityType _entityType(String wireName) =>
      EncryptedEntityType.values.singleWhere(
        (entityType) => entityType.wireName == wireName,
      );

  void dispose() => _status.dispose();
}
