import 'dart:io';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:studyflow/storage/app_database.dart';
import 'package:studyflow/storage/operation_dao.dart';

const accountA = '11111111-1111-4111-8111-111111111111';
const accountB = '22222222-2222-4222-8222-222222222222';

void main() {
  late Directory temporaryDirectory;
  late EncryptedDatabaseOpener opener;
  late SecretKey databaseKey;

  setUp(() async {
    temporaryDirectory = await Directory.systemTemp.createTemp('studyflow-db-');
    opener = EncryptedDatabaseOpener(baseDirectory: temporaryDirectory);
    databaseKey = SecretKey(List<int>.generate(32, (index) => index));
  });

  tearDown(() async {
    await temporaryDirectory.delete(recursive: true);
  });

  test('pending operation survives close and reopen in encrypted storage',
      () async {
    final database = await AppDatabase.open(
      activeAccountId: accountA,
      databaseKey: databaseKey,
      opener: opener,
    );
    final dao = OperationDao(database);
    await dao.enqueue(operation(accountId: accountA));
    await database.close();

    final databaseBytes = await opener.databaseFileFor(accountA).readAsBytes();
    expect(
      databaseBytes.take(16),
      isNot('SQLite format 3\u0000'.codeUnits),
    );

    final reopened = await AppDatabase.open(
      activeAccountId: accountA,
      databaseKey: databaseKey,
      opener: opener,
    );
    addTearDown(reopened.close);

    expect(await OperationDao(reopened).pending(10), <EncryptedOperation>[
      operation(accountId: accountA),
    ]);
  });

  test('duplicate operation id does not create a second local row', () async {
    final database = await AppDatabase.open(
      activeAccountId: accountA,
      databaseKey: databaseKey,
      opener: opener,
    );
    addTearDown(database.close);
    final dao = OperationDao(database);

    await dao.enqueue(operation(accountId: accountA));
    await dao.enqueue(operation(accountId: accountA));

    expect(await dao.pending(10), hasLength(1));
  });

  test('encrypted operation does not expose mutable cryptographic buffers', () {
    final encryptedOperation = operation(accountId: accountA);

    encryptedOperation.payloadNonce[0] = 99;
    encryptedOperation.payloadCiphertext[0] = 99;

    expect(encryptedOperation.payloadNonce.first, 0);
    expect(encryptedOperation.payloadCiphertext.first, 255);
  });

  test('DAO rejects an operation outside the active account', () async {
    final database = await AppDatabase.open(
      activeAccountId: accountA,
      databaseKey: databaseKey,
      opener: opener,
    );
    addTearDown(database.close);

    await expectLater(
      OperationDao(database).enqueue(operation(accountId: accountB)),
      throwsA(isA<OperationAccountScopeException>()),
    );
    expect(await OperationDao(database).pending(10), isEmpty);
  });

  test('wrong or unavailable database key raises a visible recovery error',
      () async {
    final database = await AppDatabase.open(
      activeAccountId: accountA,
      databaseKey: databaseKey,
      opener: opener,
    );
    await OperationDao(database).enqueue(operation(accountId: accountA));
    await database.close();

    await expectLater(
      AppDatabase.open(
        activeAccountId: accountA,
        databaseKey: SecretKey(List<int>.filled(32, 99)),
        opener: opener,
      ),
      throwsA(isA<DatabaseRecoveryException>()),
    );
    await expectLater(
      AppDatabase.open(
        activeAccountId: accountA,
        databaseKey: null,
        opener: opener,
      ),
      throwsA(isA<DatabaseRecoveryException>()),
    );
  });

  test('each encrypted record table is present', () async {
    final database = await AppDatabase.open(
      activeAccountId: accountA,
      databaseKey: databaseKey,
      opener: opener,
    );
    addTearDown(database.close);

    final names = await database
        .customSelect(
          "SELECT name FROM sqlite_master WHERE type = 'table' ORDER BY name",
        )
        .map((row) => row.read<String>('name'))
        .get();

    expect(
      names,
      containsAll(<String>[
        'check_ins',
        'focus_sessions',
        'pending_operations',
        'schedule_blocks',
        'tasks',
      ]),
    );
  });
}

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
