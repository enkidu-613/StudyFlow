import 'dart:convert';
import 'dart:io';

import 'package:cryptography/cryptography.dart';
import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';

import '../security/key_manager.dart';

part 'app_database.g.dart';
part 'operation_dao.dart';
part 'tables.dart';

final class _AccountDatabaseKey {
  _AccountDatabaseKey({required this.accountId, required SecretKey key})
      : _key = key;

  final String accountId;
  final SecretKey _key;

  Future<List<int>> extractBytes() => _key.extractBytes();
}

abstract interface class _DatabaseOpener {
  Future<QueryExecutor> open({
    required _AccountDatabaseKey databaseKey,
  });
}

class _EncryptedDatabaseOpener implements _DatabaseOpener {
  _EncryptedDatabaseOpener({required this.baseDirectory});

  static Future<_EncryptedDatabaseOpener> forApplicationSupport() async {
    final supportDirectory = await getApplicationSupportDirectory();
    return _EncryptedDatabaseOpener(
      baseDirectory: Directory(path.join(supportDirectory.path, 'encrypted')),
    );
  }

  final Directory baseDirectory;

  File databaseFileFor(String accountId) {
    final normalizedAccountId = _normalizedAccountId(accountId);
    return File(
      path.join(baseDirectory.path, 'studyflow-$normalizedAccountId.sqlite3'),
    );
  }

  @override
  Future<QueryExecutor> open({
    required _AccountDatabaseKey databaseKey,
  }) async {
    final extractedKeyBytes = await databaseKey.extractBytes();
    if (extractedKeyBytes.length != 32) {
      throw const DatabaseRecoveryException(
        'The encrypted database key has an invalid length.',
      );
    }

    await baseDirectory.create(recursive: true);
    final keyBytes = Uint8List.fromList(extractedKeyBytes);
    var keyHex = _toHex(keyBytes);
    keyBytes.fillRange(0, keyBytes.length, 0);
    return NativeDatabase(
      databaseFileFor(databaseKey.accountId),
      logStatements: false,
      setup: (database) {
        final setupKeyHex = keyHex;
        try {
          final availableCiphers = database.select('PRAGMA cipher;');
          if (availableCiphers.isEmpty ||
              availableCiphers.first.values.isEmpty) {
            throw const DatabaseRecoveryException(
              'Encrypted SQLite support is unavailable in this build.',
            );
          }
          database.execute("PRAGMA cipher = 'chacha20';");
          database.execute("PRAGMA hexkey = '$setupKeyHex';");
          database.execute('PRAGMA memory_security = ON;');
          database.select('SELECT count(*) FROM sqlite_master;');
        } finally {
          keyHex = '';
        }
      },
    );
  }
}

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
    required _AccountDatabaseKey databaseKey,
    required _DatabaseOpener opener,
  }) async {
    final normalizedAccountId = _normalizedAccountId(activeAccountId);
    if (databaseKey.accountId != normalizedAccountId) {
      throw const StorageAccountScopeException(
        'Database key account does not match the active account.',
      );
    }

    _AccountDatabase? database;
    try {
      final executor = await opener.open(databaseKey: databaseKey);
      database = _AccountDatabase._(
        executor,
        activeAccountId: normalizedAccountId,
      );
      await database.customSelect('SELECT 1;').getSingle();
      return database;
    } on DatabaseRecoveryException {
      await database?.close();
      rethrow;
    } catch (error) {
      await database?.close();
      throw DatabaseRecoveryException(
        'Encrypted local data could not be opened. Restore the correct '
        'account key or recover the local database.',
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
  AccountScopedStore._(_AccountDatabase database)
      : _database = database,
        activeAccountId = database.activeAccountId,
        operations = OperationDao._(database);

  static Future<AccountScopedStore> open({
    required String activeAccountId,
    required KeyManager keyManager,
  }) async {
    return _open(
      activeAccountId: activeAccountId,
      keyManager: keyManager,
      opener: await _EncryptedDatabaseOpener.forApplicationSupport(),
    );
  }

  @visibleForTesting
  static Future<AccountScopedStore> openForTesting({
    required String activeAccountId,
    required KeyManager keyManager,
    required Directory baseDirectory,
  }) =>
      _open(
        activeAccountId: activeAccountId,
        keyManager: keyManager,
        opener: _EncryptedDatabaseOpener(baseDirectory: baseDirectory),
      );

  static Future<AccountScopedStore> _open({
    required String activeAccountId,
    required KeyManager keyManager,
    required _DatabaseOpener opener,
  }) async {
    final normalizedAccountId = _normalizedAccountId(activeAccountId);
    if (keyManager.accountId != normalizedAccountId) {
      throw const StorageAccountScopeException(
        'Key manager account does not match the active account.',
      );
    }

    final databaseKey = await _deriveDatabaseKey(keyManager);
    if (databaseKey.accountId != normalizedAccountId) {
      throw const StorageAccountScopeException(
        'Derived database key does not match the active account.',
      );
    }
    return AccountScopedStore._(
      await _AccountDatabase.open(
        activeAccountId: normalizedAccountId,
        databaseKey: databaseKey,
        opener: opener,
      ),
    );
  }

  final _AccountDatabase _database;
  final String activeAccountId;
  final OperationDao operations;

  EncryptedRecordRepository records(EncryptedEntityType entityType) =>
      EncryptedRecordRepository._(_database, entityType);

  Future<void> close() => _database.close();
}

enum EncryptedEntityType {
  task('task', 'tasks'),
  scheduleBlock('schedule_block', 'schedule_blocks'),
  focusSession('focus_session', 'focus_sessions'),
  checkIn('check_in', 'check_ins');

  const EncryptedEntityType(this.wireName, this.tableName);

  final String wireName;
  final String tableName;
}

class EncryptedLocalRecord {
  EncryptedLocalRecord({
    required String accountId,
    required String recordId,
    required this.entityType,
    required this.schemaVersion,
    required List<int> payloadNonce,
    required List<int> payloadCiphertext,
    required this.updatedAt,
  })  : accountId = _normalizedUuid(accountId, 'accountId'),
        recordId = _normalizedUuid(recordId, 'recordId'),
        _payloadNonce = Uint8List.fromList(payloadNonce),
        _payloadCiphertext = Uint8List.fromList(payloadCiphertext) {
    if (schemaVersion != 1) {
      throw ArgumentError.value(
        schemaVersion,
        'schemaVersion',
        'must be the supported schema version 1',
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
  }

  final String accountId;
  final String recordId;
  final EncryptedEntityType entityType;
  final int schemaVersion;
  final Uint8List _payloadNonce;
  final Uint8List _payloadCiphertext;
  final DateTime updatedAt;

  Uint8List get payloadNonce => Uint8List.fromList(_payloadNonce);
  Uint8List get payloadCiphertext => Uint8List.fromList(_payloadCiphertext);

  @override
  bool operator ==(Object other) =>
      other is EncryptedLocalRecord &&
      accountId == other.accountId &&
      recordId == other.recordId &&
      entityType == other.entityType &&
      schemaVersion == other.schemaVersion &&
      _bytesEqual(_payloadNonce, other._payloadNonce) &&
      _bytesEqual(_payloadCiphertext, other._payloadCiphertext) &&
      updatedAt == other.updatedAt;

  @override
  int get hashCode => Object.hash(
        accountId,
        recordId,
        entityType,
        schemaVersion,
        Object.hashAll(_payloadNonce),
        Object.hashAll(_payloadCiphertext),
        updatedAt,
      );
}

class EncryptedRecordRepository {
  EncryptedRecordRepository._(this._database, this.entityType);

  final _AccountDatabase _database;
  final EncryptedEntityType entityType;

  Future<void> put(EncryptedLocalRecord record) async {
    _checkAccount(record.accountId);
    if (record.entityType != entityType) {
      throw ArgumentError.value(
        record.entityType,
        'record.entityType',
        'must match the repository entity type',
      );
    }

    await _database.transaction(() async {
      await _database.customStatement(
        'INSERT INTO ${entityType.tableName} '
        '(account_id, record_id, schema_version, payload_nonce, '
        'payload_ciphertext, updated_at) VALUES (?, ?, ?, ?, ?, ?) '
        'ON CONFLICT(account_id, record_id) DO UPDATE SET '
        'schema_version = excluded.schema_version, '
        'payload_nonce = excluded.payload_nonce, '
        'payload_ciphertext = excluded.payload_ciphertext, '
        'updated_at = excluded.updated_at',
        <Object?>[
          record.accountId,
          record.recordId,
          record.schemaVersion,
          record.payloadNonce,
          record.payloadCiphertext,
          record.updatedAt.millisecondsSinceEpoch,
        ],
      );
    });
  }

  Future<EncryptedLocalRecord?> get({
    required String accountId,
    required String recordId,
  }) async {
    final normalizedAccountId = _normalizedAccountId(accountId);
    _checkAccount(normalizedAccountId);
    final normalizedRecordId = _normalizedUuid(recordId, 'recordId');

    return _database.transaction(() async {
      final row = await _database.customSelect(
        'SELECT account_id, record_id, schema_version, payload_nonce, '
        'payload_ciphertext, updated_at FROM ${entityType.tableName} '
        'WHERE account_id = ? AND record_id = ?',
        variables: <Variable<Object>>[
          Variable<String>(normalizedAccountId),
          Variable<String>(normalizedRecordId),
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

Future<_AccountDatabaseKey> _deriveDatabaseKey(KeyManager keyManager) async {
  final accountDataKey = await keyManager.loadAccountDataKey();
  final derivedKey =
      await Hkdf(hmac: Hmac.sha256(), outputLength: 32).deriveKey(
    secretKey: accountDataKey,
    nonce: utf8.encode('StudyFlow database key salt v1'),
    info: utf8.encode(keyManager.accountId),
  );
  return _AccountDatabaseKey(
    accountId: keyManager.accountId,
    key: derivedKey,
  );
}

String _toHex(List<int> bytes) =>
    bytes.map((byte) => byte.toRadixString(16).padLeft(2, '0')).join();
