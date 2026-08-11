part of 'app_database.dart';

class EncryptedOperation {
  EncryptedOperation({
    required String accountId,
    required String operationId,
    required String recordId,
    required String deviceId,
    required this.logicalClock,
    required this.entityType,
    required List<int> payloadNonce,
    required List<int> payloadCiphertext,
    required this.isTombstone,
    required this.schemaVersion,
  })  : accountId = _normalizedUuid(accountId, 'accountId'),
        operationId = _normalizedUuid(operationId, 'operationId'),
        recordId = _normalizedUuid(recordId, 'recordId'),
        deviceId = _normalizedUuid(deviceId, 'deviceId'),
        _payloadNonce = Uint8List.fromList(payloadNonce),
        _payloadCiphertext = Uint8List.fromList(payloadCiphertext) {
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
        'must be a supported encrypted entity type',
      );
    }
    if (_payloadNonce.length != 24) {
      throw ArgumentError.value(
        payloadNonce.length,
        'payloadNonce',
        'must contain a 24-byte XChaCha20 nonce',
      );
    }
    if (_payloadCiphertext.length < 16) {
      throw ArgumentError.value(
        payloadCiphertext.length,
        'payloadCiphertext',
        'must contain ciphertext and a Poly1305 tag',
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
  final String deviceId;
  final int logicalClock;
  final String entityType;
  final Uint8List _payloadNonce;
  final Uint8List _payloadCiphertext;
  final bool isTombstone;
  final int schemaVersion;

  Uint8List get payloadNonce => Uint8List.fromList(_payloadNonce);
  Uint8List get payloadCiphertext => Uint8List.fromList(_payloadCiphertext);

  @override
  bool operator ==(Object other) =>
      other is EncryptedOperation &&
      accountId == other.accountId &&
      operationId == other.operationId &&
      recordId == other.recordId &&
      deviceId == other.deviceId &&
      logicalClock == other.logicalClock &&
      entityType == other.entityType &&
      _bytesEqual(_payloadNonce, other._payloadNonce) &&
      _bytesEqual(_payloadCiphertext, other._payloadCiphertext) &&
      isTombstone == other.isTombstone &&
      schemaVersion == other.schemaVersion;

  @override
  int get hashCode => Object.hash(
        accountId,
        operationId,
        recordId,
        deviceId,
        logicalClock,
        entityType,
        Object.hashAll(_payloadNonce),
        Object.hashAll(_payloadCiphertext),
        isTombstone,
        schemaVersion,
      );
}

class OperationDao {
  OperationDao._(this._database);

  final _AccountDatabase _database;

  Future<void> enqueue(EncryptedOperation operation) async {
    await _database.transaction(() async {
      await AccountScopedTransaction._(_database).enqueue(operation);
    });
  }

  Future<List<EncryptedOperation>> pending(int limit) async {
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
            (row) => EncryptedOperation(
              accountId: row.accountId,
              operationId: row.operationId,
              recordId: row.recordId,
              deviceId: row.deviceId,
              logicalClock: row.logicalClock,
              entityType: row.entityType,
              payloadNonce: row.payloadNonce,
              payloadCiphertext: row.payloadCiphertext,
              isTombstone: row.isTombstone,
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
          EncryptedOperation(
            accountId: row.accountId,
            operationId: row.operationId,
            recordId: row.recordId,
            deviceId: row.deviceId,
            logicalClock: row.logicalClock,
            entityType: row.entityType,
            payloadNonce: row.payloadNonce,
            payloadCiphertext: row.payloadCiphertext,
            isTombstone: row.isTombstone,
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
      'SELECT logical_clock, device_id, operation_id '
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
      deviceId: row.read<String>('device_id'),
      operationId: row.read<String>('operation_id'),
    );
  }

  Future<SyncRecordSnapshot> snapshotFor(EncryptedOperation operation) async {
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
    required List<EncryptedOperation> operations,
    required int nextCursor,
    required Future<SyncRecordMutation> Function(
      EncryptedOperation operation,
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

  Future<EncryptedLocalRecord?> _readRecord(
    EncryptedEntityType entityType,
    String recordId,
  ) async {
    final row = await _database.customSelect(
      'SELECT account_id, record_id, schema_version, payload_nonce, '
      'payload_ciphertext, updated_at FROM ${entityType.tableName} '
      'WHERE account_id = ? AND record_id = ?',
      variables: <Variable<Object>>[
        Variable<String>(_database.activeAccountId),
        Variable<String>(recordId),
      ],
    ).getSingleOrNull();
    if (row == null) {
      return null;
    }
    return EncryptedLocalRecord(
      accountId: row.read<String>('account_id'),
      recordId: row.read<String>('record_id'),
      entityType: entityType,
      schemaVersion: row.read<int>('schema_version'),
      payloadNonce: row.read<Uint8List>('payload_nonce'),
      payloadCiphertext: row.read<Uint8List>('payload_ciphertext'),
      updatedAt: DateTime.fromMillisecondsSinceEpoch(
        row.read<int>('updated_at'),
        isUtc: true,
      ),
    );
  }

  Future<List<EncryptedOperation>> _readVersions(String recordId) async {
    final rows = await _database.customSelect(
      'SELECT account_id, operation_id, record_id, device_id, logical_clock, '
      'entity_type, payload_nonce, payload_ciphertext, is_tombstone, '
      'schema_version FROM sync_record_versions '
      'WHERE account_id = ? AND record_id = ? '
      'ORDER BY logical_clock DESC, device_id DESC, operation_id DESC LIMIT 2',
      variables: <Variable<Object>>[
        Variable<String>(_database.activeAccountId),
        Variable<String>(recordId),
      ],
    ).get();
    return rows
        .map(
          (row) => EncryptedOperation(
            accountId: row.read<String>('account_id'),
            operationId: row.read<String>('operation_id'),
            recordId: row.read<String>('record_id'),
            deviceId: row.read<String>('device_id'),
            logicalClock: row.read<int>('logical_clock'),
            entityType: row.read<String>('entity_type'),
            payloadNonce: row.read<Uint8List>('payload_nonce'),
            payloadCiphertext: row.read<Uint8List>('payload_ciphertext'),
            isTombstone: row.read<bool>('is_tombstone'),
            schemaVersion: row.read<int>('schema_version'),
          ),
        )
        .toList(growable: false);
  }

  Future<Map<String, SyncFieldVersion>> _readTaskFieldVersions(
    String recordId,
  ) async {
    final rows = await _database.customSelect(
      'SELECT field_name, logical_clock, device_id, operation_id '
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
          deviceId: row.read<String>('device_id'),
          operationId: row.read<String>('operation_id'),
        ),
    };
  }

  Future<void> _recordVersion(
    EncryptedOperation operation, {
    Set<String>? taskFields,
  }) async {
    await _database.customStatement(
      'INSERT OR IGNORE INTO sync_record_versions '
      '(account_id, operation_id, record_id, device_id, logical_clock, '
      'entity_type, payload_nonce, payload_ciphertext, is_tombstone, '
      'schema_version) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)',
      <Object?>[
        operation.accountId,
        operation.operationId,
        operation.recordId,
        operation.deviceId,
        operation.logicalClock,
        operation.entityType,
        operation.payloadNonce,
        operation.payloadCiphertext,
        operation.isTombstone,
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
          'SELECT logical_clock, device_id FROM sync_task_field_versions '
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
                  operation.deviceId,
                  current.read<int>('logical_clock'),
                  current.read<String>('device_id'),
                ) <=
                0) {
          continue;
        }
        await _database.customStatement(
          'INSERT INTO sync_task_field_versions '
          '(account_id, record_id, field_name, logical_clock, device_id, '
          'operation_id) VALUES (?, ?, ?, ?, ?, ?) '
          'ON CONFLICT(account_id, record_id, field_name) DO UPDATE SET '
          'logical_clock = excluded.logical_clock, '
          'device_id = excluded.device_id, operation_id = excluded.operation_id',
          <Object?>[
            operation.accountId,
            operation.recordId,
            fieldName,
            operation.logicalClock,
            operation.deviceId,
            operation.operationId,
          ],
        );
      }
    }
  }

  Future<void> _retainTombstone(EncryptedOperation operation) =>
      _database.customStatement(
        'INSERT OR IGNORE INTO sync_tombstones '
        '(account_id, operation_id, record_id, device_id, logical_clock, '
        'entity_type, payload_nonce, payload_ciphertext, schema_version) '
        'VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)',
        <Object?>[
          operation.accountId,
          operation.operationId,
          operation.recordId,
          operation.deviceId,
          operation.logicalClock,
          operation.entityType,
          operation.payloadNonce,
          operation.payloadCiphertext,
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
        'record_id TEXT NOT NULL, device_id TEXT NOT NULL, '
        'logical_clock INTEGER NOT NULL, entity_type TEXT NOT NULL, '
        'payload_nonce BLOB NOT NULL, payload_ciphertext BLOB NOT NULL, '
        'is_tombstone INTEGER NOT NULL, schema_version INTEGER NOT NULL, '
        'UNIQUE(account_id, operation_id))',
      );

  Future<void> _ensureTombstonesTable() => _database.customStatement(
        'CREATE TABLE IF NOT EXISTS sync_tombstones ('
        'account_id TEXT NOT NULL, operation_id TEXT NOT NULL, '
        'record_id TEXT NOT NULL, device_id TEXT NOT NULL, '
        'logical_clock INTEGER NOT NULL, entity_type TEXT NOT NULL, '
        'payload_nonce BLOB NOT NULL, payload_ciphertext BLOB NOT NULL, '
        'schema_version INTEGER NOT NULL, '
        'PRIMARY KEY(account_id, operation_id))',
      );

  Future<void> _ensureTaskFieldVersionsTable() => _database.customStatement(
        'CREATE TABLE IF NOT EXISTS sync_task_field_versions ('
        'account_id TEXT NOT NULL, record_id TEXT NOT NULL, '
        'field_name TEXT NOT NULL, logical_clock INTEGER NOT NULL, '
        'device_id TEXT NOT NULL, operation_id TEXT NOT NULL, '
        'PRIMARY KEY(account_id, record_id, field_name))',
      );
}

final class SyncFieldVersion {
  const SyncFieldVersion({
    required this.logicalClock,
    required this.deviceId,
    required this.operationId,
  });

  final int logicalClock;
  final String deviceId;
  final String operationId;
}

final class SyncRecordSnapshot {
  const SyncRecordSnapshot({
    required this.record,
    required this.currentVersion,
    required this.previousVersion,
    required this.taskFieldVersions,
  });

  final EncryptedLocalRecord? record;
  final EncryptedOperation? currentVersion;
  final EncryptedOperation? previousVersion;
  final Map<String, SyncFieldVersion> taskFieldVersions;
}

final class SyncRecordMutation {
  SyncRecordMutation({
    Iterable<EncryptedLocalRecord> recordsToPut =
        const <EncryptedLocalRecord>[],
    Iterable<String> recordIdsToDelete = const <String>[],
    this.recordIncomingVersion = true,
    this.versionOperation,
    this.taskFieldsToStamp,
  })  : recordsToPut = List<EncryptedLocalRecord>.unmodifiable(recordsToPut),
        recordIdsToDelete = List<String>.unmodifiable(recordIdsToDelete);

  final List<EncryptedLocalRecord> recordsToPut;
  final List<String> recordIdsToDelete;
  final bool recordIncomingVersion;
  final EncryptedOperation? versionOperation;
  final Set<String>? taskFieldsToStamp;
}

final class SyncPullApplyResult {
  const SyncPullApplyResult({required this.appliedCount});

  final int appliedCount;
}

EncryptedEntityType _entityTypeFor(String wireName) =>
    EncryptedEntityType.values.singleWhere(
      (entityType) => entityType.wireName == wireName,
      orElse: () => throw ArgumentError.value(
        wireName,
        'wireName',
        'must be a supported encrypted entity type',
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
  String leftDevice,
  int rightClock,
  String rightDevice,
) {
  final clockComparison = leftClock.compareTo(rightClock);
  return clockComparison == 0
      ? leftDevice.compareTo(rightDevice)
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

bool _bytesEqual(List<int> left, List<int> right) {
  if (left.length != right.length) {
    return false;
  }
  for (var index = 0; index < left.length; index++) {
    if (left[index] != right[index]) {
      return false;
    }
  }
  return true;
}
