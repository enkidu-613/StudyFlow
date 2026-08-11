import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';

part 'app_database.g.dart';
part 'operation_dao.dart';
part 'tables.dart';

@DriftDatabase(
  tables: <Type>[
    _Tasks,
    _ScheduleBlocks,
    _FocusSessions,
    _CheckIns,
    _PendingOperations,
  ],
)
class _AccountDatabase extends _$_AccountDatabase {
  _AccountDatabase._(super.executor, {required this.activeAccountId});

  static Future<_AccountDatabase> open({
    required String activeAccountId,
    required Directory baseDirectory,
  }) async {
    final normalizedAccountId = _normalizedAccountId(activeAccountId);
    await baseDirectory.create(recursive: true);
    final database = _AccountDatabase._(
      NativeDatabase(
        File(
          path.join(
            baseDirectory.path,
            'studyflow-$normalizedAccountId.sqlite3',
          ),
        ),
        logStatements: false,
      ),
      activeAccountId: normalizedAccountId,
    );
    try {
      await database.customSelect('SELECT 1;').getSingle();
      return database;
    } on Object catch (error) {
      await database.close();
      throw DatabaseRecoveryException(
        'Local data could not be opened. The database file may be corrupt.',
        cause: error,
      );
    }
  }

  final String activeAccountId;

  @override
  int get schemaVersion => 1;

  @override
  MigrationStrategy get migration => MigrationStrategy(
        onCreate: (Migrator migrator) => migrator.createAll(),
      );
}

class AccountScopedStore {
  AccountScopedStore._(
    _AccountDatabase database, {
    Future<void> Function()? transactionFailureInjector,
  })  : _transactionFailureInjector = transactionFailureInjector,
        _database = database,
        activeAccountId = database.activeAccountId,
        operations = OperationDao._(database);

  static Future<AccountScopedStore> open({
    required String activeAccountId,
  }) async {
    final supportDirectory = await getApplicationSupportDirectory();
    return _open(
      activeAccountId: activeAccountId,
      baseDirectory: Directory(
        path.join(supportDirectory.path, 'plaintext'),
      ),
    );
  }

  @visibleForTesting
  static Future<AccountScopedStore> openForTesting({
    required String activeAccountId,
    required Directory baseDirectory,
    Future<void> Function()? transactionFailureInjector,
  }) =>
      _open(
        activeAccountId: activeAccountId,
        baseDirectory: baseDirectory,
        transactionFailureInjector: transactionFailureInjector,
      );

  static Future<AccountScopedStore> _open({
    required String activeAccountId,
    required Directory baseDirectory,
    Future<void> Function()? transactionFailureInjector,
  }) async {
    final normalizedAccountId = _normalizedAccountId(activeAccountId);
    return AccountScopedStore._(
      await _AccountDatabase.open(
        activeAccountId: normalizedAccountId,
        baseDirectory: baseDirectory,
      ),
      transactionFailureInjector: transactionFailureInjector,
    );
  }

  final _AccountDatabase _database;
  final Future<void> Function()? _transactionFailureInjector;
  final String activeAccountId;
  final OperationDao operations;

  RecordRepository records(EntityType entityType) =>
      RecordRepository._(_database, entityType);

  Future<T> transaction<T>(
    Future<T> Function(AccountScopedTransaction transaction) action,
  ) async {
    return _database.transaction(() async {
      final result = await action(AccountScopedTransaction._(_database));
      await _transactionFailureInjector?.call();
      return result;
    });
  }

  Future<void> close() => _database.close();
}

enum EntityType {
  task('task', 'tasks'),
  scheduleBlock('schedule_block', 'schedule_blocks'),
  focusSession('focus_session', 'focus_sessions'),
  checkIn('check_in', 'check_ins');

  const EntityType(this.wireName, this.tableName);

  final String wireName;
  final String tableName;
}

class LocalRecord {
  LocalRecord({
    required String accountId,
    required String recordId,
    required this.entityType,
    required this.schemaVersion,
    required this.payload,
    required this.updatedAt,
  })  : accountId = _normalizedUuid(accountId, 'accountId'),
        recordId = _normalizedUuid(recordId, 'recordId') {
    if (schemaVersion != 1) {
      throw ArgumentError.value(
        schemaVersion,
        'schemaVersion',
        'must be the supported schema version 1',
      );
    }
    if (payload.isEmpty) {
      throw ArgumentError.value(
        payload,
        'payload',
        'must not be empty JSON text',
      );
    }
  }

  final String accountId;
  final String recordId;
  final EntityType entityType;
  final int schemaVersion;
  final String payload;
  final DateTime updatedAt;

  @override
  bool operator ==(Object other) =>
      other is LocalRecord &&
      accountId == other.accountId &&
      recordId == other.recordId &&
      entityType == other.entityType &&
      schemaVersion == other.schemaVersion &&
      payload == other.payload &&
      updatedAt == other.updatedAt;

  @override
  int get hashCode => Object.hash(
        accountId,
        recordId,
        entityType,
        schemaVersion,
        payload,
        updatedAt,
      );
}

final class AccountScopedTransaction {
  AccountScopedTransaction._(this._database);

  final _AccountDatabase _database;

  Future<void> putRecord(LocalRecord record) async {
    _checkAccount(record.accountId);

    await _database.customStatement(
      'INSERT INTO ${record.entityType.tableName} '
      '(account_id, record_id, schema_version, payload, updated_at) '
      'VALUES (?, ?, ?, ?, ?) '
      'ON CONFLICT(account_id, record_id) DO UPDATE SET '
      'schema_version = excluded.schema_version, '
      'payload = excluded.payload, '
      'updated_at = excluded.updated_at',
      <Object?>[
        record.accountId,
        record.recordId,
        record.schemaVersion,
        record.payload,
        record.updatedAt.millisecondsSinceEpoch,
      ],
    );
  }

  Future<void> enqueue(Operation operation) async {
    if (operation.accountId != _database.activeAccountId) {
      throw const OperationAccountScopeException(
        'Operation account does not match the active account.',
      );
    }

    final existingRow = await _database.customSelect(
      'SELECT account_id, operation_id, record_id, logical_clock, '
      'entity_type, payload, is_tombstone, schema_version '
      'FROM pending_operations '
      'WHERE account_id = ? AND operation_id = ?',
      variables: <Variable<Object>>[
        Variable<String>(operation.accountId),
        Variable<String>(operation.operationId),
      ],
    ).getSingleOrNull();
    if (existingRow != null) {
      final existing = Operation(
        accountId: existingRow.read<String>('account_id'),
        operationId: existingRow.read<String>('operation_id'),
        recordId: existingRow.read<String>('record_id'),
        logicalClock: existingRow.read<int>('logical_clock'),
        entityType: existingRow.read<String>('entity_type'),
        payload: _decodePayload(existingRow.read<String>('payload')),
        isTombstone: existingRow.read<int>('is_tombstone') != 0,
        schemaVersion: existingRow.read<int>('schema_version'),
      );
      if (existing == operation) {
        return;
      }
      throw OperationIdCollisionException(operation.operationId);
    }

    await _database.into(_database.pendingOperations).insert(
          _PendingOperationsCompanion.insert(
            accountId: operation.accountId,
            operationId: operation.operationId,
            recordId: operation.recordId,
            logicalClock: operation.logicalClock,
            entityType: operation.entityType,
            payload: _encodePayload(operation.payload),
            isTombstone: operation.isTombstone ? 1 : 0,
            schemaVersion: operation.schemaVersion,
            queuedAt: DateTime.now().toUtc(),
          ),
        );
  }

  void _checkAccount(String accountId) {
    if (accountId != _database.activeAccountId) {
      throw const StorageAccountScopeException(
        'Record account does not match the active account.',
      );
    }
  }
}

class RecordRepository {
  RecordRepository._(this._database, this.entityType);

  final _AccountDatabase _database;
  final EntityType entityType;

  Future<void> put(LocalRecord record) async {
    if (record.entityType != entityType) {
      throw ArgumentError.value(
        record.entityType,
        'record.entityType',
        'must match the repository entity type',
      );
    }

    await _database.transaction(() async {
      await AccountScopedTransaction._(_database).putRecord(record);
    });
  }

  Future<LocalRecord?> get({
    required String accountId,
    required String recordId,
  }) async {
    final normalizedAccountId = _normalizedAccountId(accountId);
    _checkAccount(normalizedAccountId);
    final normalizedRecordId = _normalizedUuid(recordId, 'recordId');

    return _database.transaction(() async {
      final row = await _database.customSelect(
        'SELECT account_id, record_id, schema_version, payload, updated_at '
        'FROM ${entityType.tableName} WHERE account_id = ? AND record_id = ?',
        variables: <Variable<Object>>[
          Variable<String>(normalizedAccountId),
          Variable<String>(normalizedRecordId),
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
    });
  }

  Future<List<LocalRecord>> list({required String accountId}) async {
    final normalizedAccountId = _normalizedUuid(accountId, 'accountId');
    _checkAccount(normalizedAccountId);

    return _database.transaction(() async {
      final rows = await _database.customSelect(
        'SELECT account_id, record_id, schema_version, payload, updated_at '
        'FROM ${entityType.tableName} '
        'WHERE account_id = ? ORDER BY updated_at ASC',
        variables: <Variable<Object>>[
          Variable<String>(normalizedAccountId),
        ],
      ).get();
      return rows
          .map(
            (row) => LocalRecord(
              accountId: row.read<String>('account_id'),
              recordId: row.read<String>('record_id'),
              entityType: entityType,
              schemaVersion: row.read<int>('schema_version'),
              payload: row.read<String>('payload'),
              updatedAt: DateTime.fromMillisecondsSinceEpoch(
                row.read<int>('updated_at'),
                isUtc: true,
              ),
            ),
          )
          .toList(growable: false);
    });
  }

  void _checkAccount(String accountId) {
    if (accountId != _database.activeAccountId) {
      throw const StorageAccountScopeException(
        'Record account does not match the active account.',
      );
    }
  }
}

class DatabaseRecoveryException implements Exception {
  const DatabaseRecoveryException(this.message, {this.cause});

  final String message;
  final Object? cause;

  @override
  String toString() => 'DatabaseRecoveryException: $message';
}

class StorageAccountScopeException implements Exception {
  const StorageAccountScopeException(this.message);

  final String message;

  @override
  String toString() => 'StorageAccountScopeException: $message';
}

String _normalizedAccountId(String accountId) =>
    _normalizedUuid(accountId, 'accountId');
