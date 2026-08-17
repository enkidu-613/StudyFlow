import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:studyflow/app/studyflow_workspace.dart';
import 'package:studyflow/storage/app_database.dart';

/// Imports records created under a previous device-local account into the
/// active signed-in account. It intentionally never copies pending operations
/// or SQLite files: every imported record gets a new operation for the target.
final class LocalAccountMigrationService {
  LocalAccountMigrationService({
    required StudyFlowWorkspace target,
    Future<Directory> Function()? baseDirectoryProvider,
  })  : _target = target,
        _baseDirectoryProvider = baseDirectoryProvider ?? _defaultDirectory;

  final StudyFlowWorkspace _target;
  final Future<Directory> Function() _baseDirectoryProvider;

  Future<List<LocalAccountMigrationCandidate>> discover() async {
    final directory = await _baseDirectoryProvider();
    if (!await directory.exists()) {
      return const <LocalAccountMigrationCandidate>[];
    }
    final candidates = <LocalAccountMigrationCandidate>[];
    await for (final entity in directory.list(followLinks: false)) {
      if (entity is! File) continue;
      final accountId = _accountIdFromFile(entity.path);
      if (accountId == null || accountId == _target.accountId) continue;
      try {
        final records = _readRecords(entity, accountId);
        final counts = <EntityType, int>{
          for (final type in EntityType.values) type: records[type]!.length,
        };
        final recordCount =
            counts.values.fold(0, (total, value) => total + value);
        if (recordCount > 0) {
          candidates.add(LocalAccountMigrationCandidate(
            accountId: accountId,
            recordCount: recordCount,
            counts: counts,
          ));
        }
      } on Object {
        // A corrupt or incompatible old database must not block the current
        // account. It is left untouched for manual recovery.
      }
    }
    candidates.sort((a, b) => b.recordCount.compareTo(a.recordCount));
    return candidates;
  }

  Future<LocalAccountMigrationResult> importCandidate(
    LocalAccountMigrationCandidate candidate,
  ) async {
    if (candidate.accountId == _target.accountId) {
      throw ArgumentError.value(
          candidate, 'candidate', 'must be a different account');
    }
    final directory = await _baseDirectoryProvider();
    final sourceRecords = _readRecords(
      File(path.join(
          directory.path, 'studyflow-${candidate.accountId}.sqlite3')),
      candidate.accountId,
    );
    var importedCount = 0;
    var skippedCount = 0;
    for (final type in EntityType.values) {
      final existingIds = (await _target.store.records(type).list(
                accountId: _target.accountId,
              ))
          .map((record) => record.recordId)
          .toSet();
      for (final record in sourceRecords[type]!) {
        if (!existingIds.add(record.recordId)) {
          skippedCount += 1;
          continue;
        }
        final write = await _target.nextWrite();
        final payload =
            (jsonDecode(record.payload) as Map).cast<String, Object?>();
        await _target.store.transaction((transaction) async {
          await transaction.putRecord(LocalRecord(
            accountId: _target.accountId,
            recordId: record.recordId,
            entityType: type,
            schemaVersion: record.schemaVersion,
            payload: record.payload,
            updatedAt: record.updatedAt,
          ));
          await transaction.enqueue(Operation(
            accountId: _target.accountId,
            operationId: write.operationId,
            recordId: record.recordId,
            logicalClock: write.logicalClock,
            entityType: type.wireName,
            payload: payload,
            isTombstone: false,
            schemaVersion: record.schemaVersion,
          ));
        });
        importedCount += 1;
      }
    }
    return LocalAccountMigrationResult(
      importedCount: importedCount,
      skippedCount: skippedCount,
    );
  }

  static Future<Directory> _defaultDirectory() async {
    final supportDirectory = await getApplicationSupportDirectory();
    return Directory(path.join(supportDirectory.path, 'plaintext'));
  }

  String? _accountIdFromFile(String filePath) {
    final match = RegExp(r'^studyflow-([0-9a-fA-F-]{36})\.sqlite3$')
        .firstMatch(path.basename(filePath));
    return match?.group(1)?.toLowerCase();
  }

  /// Reads the old database without constructing another Drift database.
  ///
  /// The active account continues to use Drift. The legacy file is opened in
  /// SQLite read-only mode and closed before any target-account write, so this
  /// cannot share a Drift executor or enqueue legacy operations.
  Map<EntityType, List<LocalRecord>> _readRecords(
    File databaseFile,
    String accountId,
  ) {
    final database = sqlite3.open(
      databaseFile.path,
      mode: OpenMode.readOnly,
    );
    try {
      return <EntityType, List<LocalRecord>>{
        for (final type in EntityType.values)
          type: _readType(database, type, accountId),
      };
    } finally {
      database.close();
    }
  }

  List<LocalRecord> _readType(
    Database database,
    EntityType type,
    String accountId,
  ) {
    try {
      final rows = database.select(
        'SELECT account_id, record_id, schema_version, payload, updated_at '
        'FROM ${type.tableName} WHERE account_id = ? ORDER BY updated_at ASC',
        <Object?>[accountId],
      );
      return rows
          .map(
            (row) => LocalRecord(
              accountId: row['account_id']! as String,
              recordId: row['record_id']! as String,
              entityType: type,
              schemaVersion: row['schema_version']! as int,
              payload: row['payload']! as String,
              updatedAt: DateTime.fromMillisecondsSinceEpoch(
                row['updated_at']! as int,
                isUtc: true,
              ),
            ),
          )
          .toList(growable: false);
    } on SqliteException catch (error) {
      if (error.message.contains('no such table')) {
        return const <LocalRecord>[];
      }
      rethrow;
    }
  }
}

final class LocalAccountMigrationCandidate {
  const LocalAccountMigrationCandidate({
    required this.accountId,
    required this.recordCount,
    required this.counts,
  });

  final String accountId;
  final int recordCount;
  final Map<EntityType, int> counts;

  int get scheduleCount => counts[EntityType.scheduleBlock] ?? 0;
}

final class LocalAccountMigrationResult {
  const LocalAccountMigrationResult({
    required this.importedCount,
    required this.skippedCount,
  });

  final int importedCount;
  final int skippedCount;
}
