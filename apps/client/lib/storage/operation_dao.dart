part of 'app_database.dart';

class Operation {
  Operation({
    required String accountId,
    required String operationId,
    required String recordId,
    required this.logicalClock,
    required this.entityType,
    required Map<String, Object?> payload,
    required this.isTombstone,
    required this.schemaVersion,
  })  : accountId = _normalizedUuid(accountId, 'accountId'),
        operationId = _normalizedUuid(operationId, 'operationId'),
        recordId = _normalizedUuid(recordId, 'recordId'),
        _payload = Map<String, Object?>.unmodifiable(payload) {
    if (logicalClock < 0) {
      throw ArgumentError.value(
        logicalClock,
        'logicalClock',
        'must be non-negative',
      );
    }
    if (!_entityTypes.contains(entityType)) {
      throw ArgumentError.value(
        entityType,
        'entityType',
        'must be a supported entity type',
      );
    }
    if (_payload.isEmpty && !isTombstone) {
      throw ArgumentError.value(
        payload,
        'payload',
        'must not be empty for non-tombstone operations',
      );
    }
    if (schemaVersion != 1) {
      throw ArgumentError.value(
        schemaVersion,
        'schemaVersion',
        'must be the supported schema version 1',
      );
    }
  }

  final String accountId;
  final String operationId;
  final String recordId;
  final int logicalClock;
  final String entityType;
  final Map<String, Object?> _payload;
  final bool isTombstone;
  final int schemaVersion;

  Map<String, Object?> get payload => Map<String, Object?>.unmodifiable(_payload);

  @override
  bool operator ==(Object other) =>
      other is Operation &&
      accountId == other.accountId &&
      operationId == other.operationId &&
      recordId == other.recordId &&
      logicalClock == other.logicalClock &&
      entityType == other.entityType &&
      _encodePayload(_payload) == _encodePayload(other._payload) &&
      isTombstone == other.isTombstone &&
      schemaVersion == other.schemaVersion;

  @override
  int get hashCode => Object.hash(
        accountId,
        operationId,
        recordId,
        logicalClock,
        entityType,
        _encodePayload(_payload),
        isTombstone,
        schemaVersion,
      );
}

class OperationDao {
  OperationDao._(this._database);

  final _AccountDatabase _database;

  Future<void> enqueue(Operation operation) async {
    await _database.transaction(() async {
      await AccountScopedTransaction._(_database).enqueue(operation);
    });
  }

  Future<List<Operation>> pending(int limit) async {
    if (limit <= 0) {
      throw ArgumentError.value(limit, 'limit', 'must be positive');
    }

    return _database.transaction(() async {
      final query = _database.select(_database.pendingOperations)
        ..where(
          (row) => row.accountId.equals(_database.activeAccountId),
        )
        ..orderBy(<OrderingTerm Function(_PendingOperations)>[
          (row) => OrderingTerm.asc(row.logicalClock),
          (row) => OrderingTerm.asc(row.operationId),
        ])
        ..limit(limit);
      final rows = await query.get();
      return rows
          .map(
            (row) => Operation(
              accountId: row.accountId,
              operationId: row.operationId,
              recordId: row.recordId,
              logicalClock: row.logicalClock,
              entityType: row.entityType,
              payload: _decodePayload(row.payload),
              isTombstone: row.isTombstone != 0,
              schemaVersion: row.schemaVersion,
            ),
          )
          .toList(growable: false);
    });
  }

  Future<int> pendingCount() async {
    final count = _database.pendingOperations.accountId.count();
    final query = _database.selectOnly(_database.pendingOperations)
      ..addColumns(<Expression<Object>>[count])
      ..where(
        _database.pendingOperations.accountId.equals(_database.activeAccountId),
      );
    return (await query.getSingle()).read(count) ?? 0;
  }

  Future<void> removeAcknowledged(
    Set<String> operationIds, {
    Map<String, Set<String>> taskFieldsByOperation =
        const <String, Set<String>>{},
  }) async {
    if (operationIds.isEmpty) {
      return;
    }
    final normalizedIds = operationIds
        .map((operationId) => _normalizedUuid(operationId, 'operationId'))
        .toSet();
    await _database.transaction(() async {
      await _ensureAppliedOperationsTable();
      await _ensureRecordVersionsTable();
      await _ensureTaskFieldVersionsTable();
      final acknowledgedRows = await (_database.select(
        _database.pendingOperations,
      )
            ..where(
              (row) =>
                  row.accountId.equals(_database.activeAccountId) &
                  row.operationId.isIn(normalizedIds),
            )
            ..orderBy(<OrderingTerm Function(_PendingOperations)>[
              (row) => OrderingTerm.asc(row.logicalClock),
              (row) => OrderingTerm.asc(row.operationId),
            ]))
          .get();
      for (final row in acknowledgedRows) {
        await _database.customStatement(
          'INSERT OR IGNORE INTO sync_applied_operations '
          '(account_id, operation_id) VALUES (?, ?)',
          <Object?>[row.accountId, row.operationId],
        );
        await _recordVersion(
          Operation(
            accountId: row.accountId,
            operationId: row.operationId,
            recordId: row.recordId,
            logicalClock: row.logicalClock,
            entityType: row.entityType,
            payload: _decodePayload(row.payload),
            isTombstone: row.isTombstone != 0,
            schemaVersion: row.schemaVersion,
          ),
          taskFields: taskFieldsByOperation[row.operationId],
        );
      }
      await (_database.delete(_database.pendingOperations)
            ..where(
              (row) =>
                  row.accountId.equals(_database.activeAccountId) &
                  row.operationId.isIn(normalizedIds),
            ))
          .go();
    });
  }

  Future<int> lastCommittedCursor() async {
    await _ensureSyncCursorTable();
    final row = await _database.customSelect(
      'SELECT cursor FROM sync_cursors WHERE account_id = ?',
      variables: <Variable<Object>>[
        Variable<String>(_database.activeAccountId),
      ],
    ).getSingleOrNull();
    return row?.read<int>('cursor') ?? 0;
  }

  Future<int> retainedTombstoneCount(String recordId) async {
    final normalizedRecordId = _normalizedUuid(recordId, 'recordId');
    await _ensureTombstonesTable();
    final row = await _database.customSelect(
      'SELECT COUNT(*) AS tombstone_count FROM sync_tombstones '
      'WHERE account_id = ? AND record_id = ?',
      variables: <Variable<Object>>[
        Variable<String>(_database.activeAccountId),
        Variable<String>(normalizedRecordId),
      ],
    ).getSingle();
    return row.read<int>('tombstone_count');
  }

  Future<SyncFieldVersion?> taskFieldVersion(
    String recordId,
    String fieldName,
  ) async {
    final normalizedRecordId = _normalizedUuid(recordId, 'recordId');
    if (!_taskFields.contains(fieldName)) {
      throw ArgumentError.value(fieldName, 'fieldName', 'is not a task field');
    }
    await _ensureTaskFieldVersionsTable();
    final row = await _database.customSelect(
      'SELECT logical_clock, operation_id '
      'FROM sync_task_field_versions '
      'WHERE account_id = ? AND record_id = ? AND field_name = ?',
      variables: <Variable<Object>>[
        Variable<String>(_database.activeAccountId),
        Variable<String>(normalizedRecordId),
        Variable<String>(fieldName),
      ],
    ).getSingleOrNull();
    if (row == null) {
      return null;
    }
    return SyncFieldVersion(
      logicalClock: row.read<int>('logical_clock'),
      operationId: row.read<String>('operation_id'),
    );
  }

  Future<SyncRecordSnapshot> snapshotFor(Operation operation) async {
    await _ensureRecordVersionsTable();
    await _ensureTaskFieldVersionsTable();
    final entityType = _entityTypeFor(operation.entityType);
    final versions = await _readVersions(operation.recordId);
    return SyncRecordSnapshot(
      record: await _readRecord(entityType, operation.recordId),
      currentVersion: versions.isEmpty ? null : versions.first,
      previousVersion: versions.length < 2 ? null : versions[1],
      taskFieldVersions: await _readTaskFieldVersions(operation.recordId),
    );
  }

  Future<void> commitCursor(int cursor) async {
    if (cursor < 0) {
      throw ArgumentError.value(cursor, 'cursor', 'must be nonnegative');
    }
    await _database.transaction(() async {
      await _ensureSyncCursorTable();
      final current = await _database.customSelect(
        'SELECT cursor FROM sync_cursors WHERE account_id = ?',
        variables: <Variable<Object>>[
          Variable<String>(_database.activeAccountId),
        ],
      ).getSingleOrNull();
      final currentCursor = current?.read<int>('cursor') ?? 0;
      if (cursor < currentCursor) {
        throw StateError('A sync cursor cannot move backwards.');
      }
      await _database.customStatement(
        'INSERT INTO sync_cursors (account_id, cursor) VALUES (?, ?) '
        'ON CONFLICT(account_id) DO UPDATE SET cursor = excluded.cursor',
        <Object?>[_database.activeAccountId, cursor],
      );
    });
  }

  Future<SyncPullApplyResult> applyPullPage({
    required List<Operation> operations,
    required int nextCursor,
    required Future<SyncRecordMutation> Function(
      Operation operation,
      SyncRecordSnapshot snapshot,
    ) resolve,
  }) async {
    if (nextCursor < 0) {
      throw ArgumentError.value(
          nextCursor, 'nextCursor', 'must be nonnegative');
    }
    return _database.transaction(() async {
      await _ensureAppliedOperationsTable();
      await _ensureRecordVersionsTable();
      await _ensureTombstonesTable();
      await _ensureSyncCursorTable();
      await _ensureTaskFieldVersionsTable();
      var appliedCount = 0;
      for (final operation in operations) {
        if (operation.accountId != _database.activeAccountId) {
          throw const OperationAccountScopeException(
            'Pulled operation account does not match the active account.',
          );
        }
        final alreadyApplied = await _database.customSelect(
          'SELECT 1 FROM sync_applied_operations '
          'WHERE account_id = ? AND operation_id = ?',
          variables: <Variable<Object>>[
            Variable<String>(operation.accountId),
            Variable<String>(operation.operationId),
          ],
        ).getSingleOrNull();
        if (alreadyApplied != null) {
          continue;
        }

        final entityType = _entityTypeFor(operation.entityType);
        final versions = await _readVersions(operation.recordId);
        final snapshot = SyncRecordSnapshot(
          record: await _readRecord(entityType, operation.recordId),
          currentVersion: versions.isEmpty ? null : versions.first,
          previousVersion: versions.length < 2 ? null : versions[1],
          taskFieldVersions: await _readTaskFieldVersions(operation.recordId),
        );
        final mutation = await resolve(operation, snapshot);
        for (final record in mutation.recordsToPut) {
          await AccountScopedTransaction._(_database).putRecord(record);
        }
        for (final recordId in mutation.recordIdsToDelete) {
          await _database.customStatement(
            'DELETE FROM ${entityType.tableName} '
            'WHERE account_id = ? AND record_id = ?',
            <Object?>[_database.activeAccountId, recordId],
          );
        }
        if (mutation.recordIncomingVersion) {
          await _recordVersion(
            mutation.versionOperation ?? operation,
            taskFields: mutation.taskFieldsToStamp,
          );
        }
        if (operation.isTombstone) {
          await _retainTombstone(operation);
        }
        await _database.customStatement(
          'INSERT INTO sync_applied_operations '
          '(account_id, operation_id) VALUES (?, ?)',
          <Object?>[operation.accountId, operation.operationId],
        );
        appliedCount += 1;
      }
      await _writeCursor(nextCursor);
      return SyncPullApplyResult(appliedCount: appliedCount);
    });
  }

  Future<LocalRecord?> _readRecord(
    EntityType entityType,
    String recordId,
  ) async {
    final row = await _database.customSelect(
      'SELECT account_id, record_id, schema_version, payload, updated_at '
      'FROM ${entityType.tableName} '
      'WHERE account_id = ? AND record_id = ?',
      variables: <Variable<Object>>[
        Variable<String>(_database.activeAccountId),
        Variable<String>(recordId),
      ],
    ).getSingleOrNull();
    if (row == null) {
      return null;
    }
    return LocalRecord(
      accountId: row.read<String>('account_id'),
      recordId: row.read<String>('record_id'),
      entityType: entityType,
      schemaVersion: row.read<int>('schema_version'),
      payload: row.read<String>('payload'),
      updatedAt: DateTime.fromMillisecondsSinceEpoch(
        row.read<int>('updated_at'),
        isUtc: true,
      ),
    );
  }

  Future<List<Operation>> _readVersions(String recordId) async {
    final rows = await _database.customSelect(
      'SELECT account_id, operation_id, record_id, logical_clock, '
      'entity_type, payload, is_tombstone, schema_version '
      'FROM sync_record_versions '
      'WHERE account_id = ? AND record_id = ? '
      'ORDER BY logical_clock DESC, operation_id DESC LIMIT 2',
      variables: <Variable<Object>>[
        Variable<String>(_database.activeAccountId),
        Variable<String>(recordId),
      ],
    ).get();
    return rows
        .map(
          (row) => Operation(
            accountId: row.read<String>('account_id'),
            operationId: row.read<String>('operation_id'),
            recordId: row.read<String>('record_id'),
            logicalClock: row.read<int>('logical_clock'),
            entityType: row.read<String>('entity_type'),
            payload: _decodePayload(row.read<String>('payload')),
            isTombstone: row.read<int>('is_tombstone') != 0,
            schemaVersion: row.read<int>('schema_version'),
          ),
        )
        .toList(growable: false);
  }

  Future<Map<String, SyncFieldVersion>> _readTaskFieldVersions(
    String recordId,
  ) async {
    final rows = await _database.customSelect(
      'SELECT field_name, logical_clock, operation_id '
      'FROM sync_task_field_versions '
      'WHERE account_id = ? AND record_id = ?',
      variables: <Variable<Object>>[
        Variable<String>(_database.activeAccountId),
        Variable<String>(recordId),
      ],
    ).get();
    return <String, SyncFieldVersion>{
      for (final row in rows)
        row.read<String>('field_name'): SyncFieldVersion(
          logicalClock: row.read<int>('logical_clock'),
          operationId: row.read<String>('operation_id'),
        ),
    };
  }

  Future<void> _recordVersion(
    Operation operation, {
    Set<String>? taskFields,
  }) async {
    await _database.customStatement(
      'INSERT OR IGNORE INTO sync_record_versions '
      '(account_id, operation_id, record_id, logical_clock, entity_type, '
      'payload, is_tombstone, schema_version) VALUES (?, ?, ?, ?, ?, ?, ?, ?)',
      <Object?>[
        operation.accountId,
        operation.operationId,
        operation.recordId,
        operation.logicalClock,
        operation.entityType,
        _encodePayload(operation.payload),
        operation.isTombstone ? 1 : 0,
        operation.schemaVersion,
      ],
    );
    if (operation.entityType == 'task') {
      final fields = taskFields ?? _taskFields;
      for (final fieldName in fields) {
        if (!_taskFields.contains(fieldName)) {
          throw ArgumentError.value(
            fieldName,
            'taskFields',
            'is not a supported task field',
          );
        }
        final current = await _database.customSelect(
          'SELECT logical_clock, operation_id FROM sync_task_field_versions '
          'WHERE account_id = ? AND record_id = ? AND field_name = ?',
          variables: <Variable<Object>>[
            Variable<String>(operation.accountId),
            Variable<String>(operation.recordId),
            Variable<String>(fieldName),
          ],
        ).getSingleOrNull();
        if (current != null &&
            _compareFieldStamp(
                  operation.logicalClock,
                  operation.operationId,
                  current.read<int>('logical_clock'),
                  current.read<String>('operation_id'),
                ) <=
                0) {
          continue;
        }
        await _database.customStatement(
          'INSERT INTO sync_task_field_versions '
          '(account_id, record_id, field_name, logical_clock, operation_id) '
          'VALUES (?, ?, ?, ?, ?) '
          'ON CONFLICT(account_id, record_id, field_name) DO UPDATE SET '
          'logical_clock = excluded.logical_clock, '
          'operation_id = excluded.operation_id',
          <Object?>[
            operation.accountId,
            operation.recordId,
            fieldName,
            operation.logicalClock,
            operation.operationId,
          ],
        );
      }
    }
  }

  Future<void> _retainTombstone(Operation operation) =>
      _database.customStatement(
        'INSERT OR IGNORE INTO sync_tombstones '
        '(account_id, operation_id, record_id, logical_clock, entity_type, '
        'payload, schema_version) VALUES (?, ?, ?, ?, ?, ?, ?)',
        <Object?>[
          operation.accountId,
          operation.operationId,
          operation.recordId,
          operation.logicalClock,
          operation.entityType,
          _encodePayload(operation.payload),
          operation.schemaVersion,
        ],
      );

  Future<void> _writeCursor(int cursor) async {
    final current = await _database.customSelect(
      'SELECT cursor FROM sync_cursors WHERE account_id = ?',
      variables: <Variable<Object>>[
        Variable<String>(_database.activeAccountId),
      ],
    ).getSingleOrNull();
    final currentCursor = current?.read<int>('cursor') ?? 0;
    if (cursor < currentCursor) {
      throw StateError('A sync cursor cannot move backwards.');
    }
    await _database.customStatement(
      'INSERT INTO sync_cursors (account_id, cursor) VALUES (?, ?) '
      'ON CONFLICT(account_id) DO UPDATE SET cursor = excluded.cursor',
      <Object?>[_database.activeAccountId, cursor],
    );
  }

  Future<void> _ensureSyncCursorTable() => _database.customStatement(
        'CREATE TABLE IF NOT EXISTS sync_cursors ('
        'account_id TEXT PRIMARY KEY NOT NULL, '
        'cursor INTEGER NOT NULL CHECK(cursor >= 0))',
      );

  Future<void> _ensureAppliedOperationsTable() => _database.customStatement(
        'CREATE TABLE IF NOT EXISTS sync_applied_operations ('
        'account_id TEXT NOT NULL, operation_id TEXT NOT NULL, '
        'PRIMARY KEY(account_id, operation_id))',
      );

  Future<void> _ensureRecordVersionsTable() => _database.customStatement(
        'CREATE TABLE IF NOT EXISTS sync_record_versions ('
        'local_sequence INTEGER PRIMARY KEY AUTOINCREMENT, '
        'account_id TEXT NOT NULL, operation_id TEXT NOT NULL, '
        'record_id TEXT NOT NULL, logical_clock INTEGER NOT NULL, '
        'entity_type TEXT NOT NULL, payload TEXT NOT NULL, '
        'is_tombstone INTEGER NOT NULL, schema_version INTEGER NOT NULL, '
        'UNIQUE(account_id, operation_id))',
      );

  Future<void> _ensureTombstonesTable() => _database.customStatement(
        'CREATE TABLE IF NOT EXISTS sync_tombstones ('
        'account_id TEXT NOT NULL, operation_id TEXT NOT NULL, '
        'record_id TEXT NOT NULL, logical_clock INTEGER NOT NULL, '
        'entity_type TEXT NOT NULL, payload TEXT NOT NULL, '
        'schema_version INTEGER NOT NULL, '
        'PRIMARY KEY(account_id, operation_id))',
      );

  Future<void> _ensureTaskFieldVersionsTable() => _database.customStatement(
        'CREATE TABLE IF NOT EXISTS sync_task_field_versions ('
        'account_id TEXT NOT NULL, record_id TEXT NOT NULL, '
        'field_name TEXT NOT NULL, logical_clock INTEGER NOT NULL, '
        'operation_id TEXT NOT NULL, '
        'PRIMARY KEY(account_id, record_id, field_name))',
      );
}

final class SyncFieldVersion {
  const SyncFieldVersion({
    required this.logicalClock,
    required this.operationId,
  });

  final int logicalClock;
  final String operationId;
}

final class SyncRecordSnapshot {
  const SyncRecordSnapshot({
    required this.record,
    required this.currentVersion,
    required this.previousVersion,
    required this.taskFieldVersions,
  });

  final LocalRecord? record;
  final Operation? currentVersion;
  final Operation? previousVersion;
  final Map<String, SyncFieldVersion> taskFieldVersions;
}

final class SyncRecordMutation {
  SyncRecordMutation({
    Iterable<LocalRecord> recordsToPut = const <LocalRecord>[],
    Iterable<String> recordIdsToDelete = const <String>[],
    this.recordIncomingVersion = true,
    this.versionOperation,
    this.taskFieldsToStamp,
  })  : recordsToPut = List<LocalRecord>.unmodifiable(recordsToPut),
        recordIdsToDelete = List<String>.unmodifiable(recordIdsToDelete);

  final List<LocalRecord> recordsToPut;
  final List<String> recordIdsToDelete;
  final bool recordIncomingVersion;
  final Operation? versionOperation;
  final Set<String>? taskFieldsToStamp;
}

final class SyncPullApplyResult {
  const SyncPullApplyResult({required this.appliedCount});

  final int appliedCount;
}

EntityType _entityTypeFor(String wireName) => EntityType.values.singleWhere(
      (entityType) => entityType.wireName == wireName,
      orElse: () => throw ArgumentError.value(
        wireName,
        'wireName',
        'must be a supported entity type',
      ),
    );

class OperationAccountScopeException implements Exception {
  const OperationAccountScopeException(this.message);

  final String message;

  @override
  String toString() => 'OperationAccountScopeException: $message';
}

class OperationIdCollisionException implements Exception {
  const OperationIdCollisionException(this.operationId);

  final String operationId;

  @override
  String toString() =>
      'OperationIdCollisionException: operation id is already used by '
      'different operation bytes: $operationId';
}

const Set<String> _entityTypes = <String>{
  'task',
  'schedule_block',
  'focus_session',
  'check_in',
  'schedule_feedback',
  'medication_plan',
  'medication_dose_record',
};

const Set<String> _taskFields = <String>{
  'title',
  'description',
  'estimatedMinutes',
  'priority',
  'status',
  'tags',
  'repeatRule',
};

int _compareFieldStamp(
  int leftClock,
  String leftOperation,
  int rightClock,
  String rightOperation,
) {
  final clockComparison = leftClock.compareTo(rightClock);
  return clockComparison == 0
      ? leftOperation.compareTo(rightOperation)
      : clockComparison;
}

String _normalizedUuid(String value, String fieldName) {
  final normalized = value.toLowerCase();
  final uuid = RegExp(
    r'^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$',
  );
  if (!uuid.hasMatch(normalized)) {
    throw ArgumentError.value(value, fieldName, 'must be a UUID');
  }
  return normalized;
}

String _encodePayload(Map<String, Object?> payload) => jsonEncode(payload);

Map<String, Object?> _decodePayload(String payload) =>
    (jsonDecode(payload) as Map<String, dynamic>).cast<String, Object?>();
