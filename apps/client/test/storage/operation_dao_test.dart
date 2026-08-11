import 'dart:io';
import 'dart:typed_data';

import 'package:analyzer/dart/analysis/analysis_context_collection.dart';
import 'package:analyzer/dart/analysis/results.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:studyflow/security/key_manager.dart';
import 'package:studyflow/storage/app_database.dart';

const accountA = '11111111-1111-4111-8111-111111111111';
const accountB = '22222222-2222-4222-8222-222222222222';

void main() {
  late Directory temporaryDirectory;
  late MemorySecureKeyStore keyStore;
  late KeyManager keyManager;

  setUp(() async {
    temporaryDirectory = await Directory.systemTemp.createTemp('studyflow-db-');
    keyStore = MemorySecureKeyStore();
    keyManager = KeyManager(accountId: accountA, store: keyStore);
    await keyManager.createAccountDataKey();
  });

  tearDown(() async {
    await temporaryDirectory.delete(recursive: true);
  });

  test('pending operation survives close and reopen in encrypted storage',
      () async {
    final store = await openStore(keyManager, temporaryDirectory);
    await store.operations.enqueue(operation(accountId: accountA));
    await store.close();

    final databaseBytes = await databaseFile(temporaryDirectory).readAsBytes();
    expect(
      databaseBytes.take(16),
      isNot('SQLite format 3\u0000'.codeUnits),
    );

    final reopened = await openStore(keyManager, temporaryDirectory);
    addTearDown(reopened.close);

    expect(await reopened.operations.pending(10), <EncryptedOperation>[
      operation(accountId: accountA),
    ]);
  });

  test('duplicate operation id does not create a second local row', () async {
    final store = await openStore(keyManager, temporaryDirectory);
    addTearDown(store.close);

    await store.operations.enqueue(operation(accountId: accountA));
    await store.operations.enqueue(operation(accountId: accountA));

    expect(await store.operations.pending(10), hasLength(1));
  });

  test('encrypted operation does not expose mutable cryptographic buffers', () {
    final encryptedOperation = operation(accountId: accountA);

    encryptedOperation.payloadNonce[0] = 99;
    encryptedOperation.payloadCiphertext[0] = 99;

    expect(encryptedOperation.payloadNonce.first, 0);
    expect(encryptedOperation.payloadCiphertext.first, 255);
  });

  test('operation store rejects a write outside the active account', () async {
    final store = await openStore(keyManager, temporaryDirectory);
    addTearDown(store.close);

    await expectLater(
      store.operations.enqueue(operation(accountId: accountB)),
      throwsA(isA<OperationAccountScopeException>()),
    );
    expect(await store.operations.pending(10), isEmpty);
  });

  test('wrong or unavailable database key fails closed', () async {
    final store = await openStore(keyManager, temporaryDirectory);
    await store.operations.enqueue(operation(accountId: accountA));
    await store.close();

    final wrongKeyManager = KeyManager(
      accountId: accountA,
      store: MemorySecureKeyStore(),
    );
    await wrongKeyManager.createAccountDataKey();
    await expectLater(
      openStore(wrongKeyManager, temporaryDirectory),
      throwsA(isA<DatabaseRecoveryException>()),
    );

    final missingKeyManager = KeyManager(
      accountId: accountA,
      store: MemorySecureKeyStore(),
    );
    await expectLater(
      openStore(missingKeyManager, temporaryDirectory),
      throwsA(isA<KeyRecoveryException>()),
    );
  });

  test('database key cannot be bound to a different active account', () async {
    final accountBManager = KeyManager(accountId: accountB, store: keyStore);
    await accountBManager.createAccountDataKey();

    await expectLater(
      AccountScopedStore.openForTesting(
        activeAccountId: accountA,
        keyManager: accountBManager,
        baseDirectory: temporaryDirectory,
      ),
      throwsA(isA<StorageAccountScopeException>()),
    );
    expect(databaseFile(temporaryDirectory).existsSync(), isFalse);
  });

  test('public storage API cannot compile a raw SQL opener bypass', () async {
    final probe = File(
      '${Directory.current.path}/.dart_tool/'
      'task4_public_api_probe_${DateTime.now().microsecondsSinceEpoch}.dart',
    );
    await probe.writeAsString(r'''
import 'dart:io';

import 'package:drift/drift.dart' as drift;
import 'package:studyflow/security/key_manager.dart';
import 'package:studyflow/storage/app_database.dart' as storage;

Future<drift.QueryExecutor> bypass(AccountDatabaseKey key) {
  final storage.DatabaseOpener opener = storage.EncryptedDatabaseOpener(
    baseDirectory: Directory.systemTemp,
  );
  return opener.open(databaseKey: key);
}

Future<drift.QueryExecutor> obtainAndBypass(KeyManager manager) async {
  return bypass(await manager.loadDatabaseKey());
}
''');
    addTearDown(() async {
      if (await probe.exists()) {
        await probe.delete();
      }
    });

    final analysisContexts = AnalysisContextCollection(
      includedPaths: <String>[probe.path],
      sdkPath: _dartSdkPath(),
    );
    addTearDown(analysisContexts.dispose);
    final result = await analysisContexts
        .contextFor(probe.path)
        .currentSession
        .getResolvedUnit(probe.path);

    expect(result, isA<ResolvedUnitResult>());
    final diagnostics = (result as ResolvedUnitResult)
        .diagnostics
        .map(
          (diagnostic) => diagnostic.problemMessage.messageText(
            includeUrl: false,
          ),
        )
        .join('\n');
    expect(diagnostics, isNotEmpty,
        reason: 'A production caller compiled a raw QueryExecutor bypass.');
    expect(diagnostics, contains('AccountDatabaseKey'));
    expect(diagnostics, contains('DatabaseOpener'));
    expect(diagnostics, contains('EncryptedDatabaseOpener'));
    expect(diagnostics, contains('loadDatabaseKey'));
  });

  test('all encrypted record stores reject cross-account writes and reads',
      () async {
    final store = await openStore(keyManager, temporaryDirectory);
    addTearDown(store.close);
    final recordIds = <String>[
      '10000000-0000-4000-8000-000000000001',
      '10000000-0000-4000-8000-000000000002',
      '10000000-0000-4000-8000-000000000003',
      '10000000-0000-4000-8000-000000000004',
    ];

    for (var index = 0; index < EncryptedEntityType.values.length; index++) {
      final entityType = EncryptedEntityType.values[index];
      final repository = store.records(entityType);
      final activeRecord = encryptedRecord(
        accountId: accountA,
        recordId: recordIds[index],
        entityType: entityType,
      );

      await repository.put(activeRecord);
      expect(
        await repository.get(
          accountId: accountA,
          recordId: recordIds[index],
        ),
        activeRecord,
      );
      await expectLater(
        repository.put(
          encryptedRecord(
            accountId: accountB,
            recordId: recordIds[index],
            entityType: entityType,
          ),
        ),
        throwsA(isA<StorageAccountScopeException>()),
      );
      await expectLater(
        repository.get(accountId: accountB, recordId: recordIds[index]),
        throwsA(isA<StorageAccountScopeException>()),
      );
    }
  });

  test('encrypted record timestamps round trip to the millisecond', () async {
    final store = await openStore(keyManager, temporaryDirectory);
    addTearDown(store.close);
    final timestamp = DateTime.utc(2026, 8, 11, 12, 34, 56, 789);
    final record = encryptedRecord(
      accountId: accountA,
      recordId: '20000000-0000-4000-8000-000000000001',
      entityType: EncryptedEntityType.task,
      updatedAt: timestamp,
    );

    await store.records(EncryptedEntityType.task).put(record);
    final stored = await store.records(EncryptedEntityType.task).get(
          accountId: accountA,
          recordId: record.recordId,
        );

    expect(stored, isNotNull);
    expect(stored!.updatedAt, timestamp);
    expect(stored.updatedAt.millisecond, 789);
  });
}

Future<AccountScopedStore> openStore(
  KeyManager keyManager,
  Directory baseDirectory,
) =>
    AccountScopedStore.openForTesting(
      activeAccountId: accountA,
      keyManager: keyManager,
      baseDirectory: baseDirectory,
    );

File databaseFile(Directory baseDirectory) =>
    File('${baseDirectory.path}/studyflow-$accountA.sqlite3');

EncryptedOperation operation({required String accountId}) => EncryptedOperation(
      accountId: accountId,
      operationId: 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',
      recordId: 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb',
      deviceId: 'cccccccc-cccc-4ccc-8ccc-cccccccccccc',
      logicalClock: 7,
      entityType: 'task',
      payloadNonce:
          Uint8List.fromList(List<int>.generate(24, (index) => index)),
      payloadCiphertext: Uint8List.fromList(
        List<int>.generate(48, (index) => 255 - index),
      ),
      isTombstone: false,
      schemaVersion: 1,
    );

EncryptedLocalRecord encryptedRecord({
  required String accountId,
  required String recordId,
  required EncryptedEntityType entityType,
  DateTime? updatedAt,
}) =>
    EncryptedLocalRecord(
      accountId: accountId,
      recordId: recordId,
      entityType: entityType,
      schemaVersion: 1,
      payloadNonce:
          Uint8List.fromList(List<int>.generate(24, (index) => index)),
      payloadCiphertext: Uint8List.fromList(
        List<int>.generate(48, (index) => 255 - index),
      ),
      updatedAt: updatedAt ?? DateTime.utc(2026, 8, 11),
    );

class MemorySecureKeyStore implements SecureKeyStore {
  final Map<String, String> _values = <String, String>{};

  @override
  Future<String?> read({
    required String accountId,
    required StoredKeyName keyName,
  }) async =>
      _values['$accountId:${keyName.name}'];

  @override
  Future<void> write({
    required String accountId,
    required StoredKeyName keyName,
    required String value,
  }) async {
    _values['$accountId:${keyName.name}'] = value;
  }
}

String _dartSdkPath() {
  var directory = File(Platform.resolvedExecutable).parent;
  while (directory.parent.path != directory.path) {
    final candidate = Directory('${directory.path}/dart-sdk');
    if (File('${candidate.path}/lib/libraries.json').existsSync()) {
      return candidate.path;
    }
    directory = directory.parent;
  }
  throw StateError('The Flutter test Dart SDK could not be located.');
}
