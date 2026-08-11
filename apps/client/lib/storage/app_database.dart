import 'dart:io';

import 'package:cryptography/cryptography.dart';
import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';

import 'tables.dart';

part 'app_database.g.dart';

abstract interface class DatabaseOpener {
  Future<QueryExecutor> open({
    required String accountId,
    required SecretKey? databaseKey,
  });
}

class EncryptedDatabaseOpener implements DatabaseOpener {
  EncryptedDatabaseOpener({required this.baseDirectory});

  static Future<EncryptedDatabaseOpener> forApplicationSupport() async {
    final supportDirectory = await getApplicationSupportDirectory();
    return EncryptedDatabaseOpener(
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
    required String accountId,
    required SecretKey? databaseKey,
  }) async {
    if (databaseKey == null) {
      throw const DatabaseRecoveryException(
        'The encrypted database key is unavailable. Restore the account key '
        'before opening local data.',
      );
    }

    final keyBytes = await databaseKey.extractBytes();
    if (keyBytes.length != 32) {
      throw const DatabaseRecoveryException(
        'The encrypted database key has an invalid length.',
      );
    }

    await baseDirectory.create(recursive: true);
    var keyHex = _toHex(keyBytes);
    return NativeDatabase(
      databaseFileFor(accountId),
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
    Tasks,
    ScheduleBlocks,
    FocusSessions,
    CheckIns,
    PendingOperations,
  ],
)
class AppDatabase extends _$AppDatabase {
  AppDatabase._(super.executor, {required this.activeAccountId});

  static Future<AppDatabase> open({
    required String activeAccountId,
    required SecretKey? databaseKey,
    required DatabaseOpener opener,
  }) async {
    final normalizedAccountId = _normalizedAccountId(activeAccountId);
    AppDatabase? database;
    try {
      final executor = await opener.open(
        accountId: normalizedAccountId,
        databaseKey: databaseKey,
      );
      database = AppDatabase._(
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

class DatabaseRecoveryException implements Exception {
  const DatabaseRecoveryException(this.message, {this.cause});

  final String message;
  final Object? cause;

  @override
  String toString() => 'DatabaseRecoveryException: $message';
}

String _normalizedAccountId(String accountId) {
  final normalized = accountId.toLowerCase();
  final uuid = RegExp(
    r'^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$',
  );
  if (!uuid.hasMatch(normalized)) {
    throw ArgumentError.value(accountId, 'accountId', 'must be a UUID');
  }
  return normalized;
}

String _toHex(List<int> bytes) =>
    bytes.map((byte) => byte.toRadixString(16).padLeft(2, '0')).join();
