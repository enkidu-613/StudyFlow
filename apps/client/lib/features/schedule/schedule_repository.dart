import 'dart:convert';

import 'package:studyflow/features/tasks/task_repository.dart';
import 'package:studyflow/security/payload_cipher.dart';
import 'package:studyflow/storage/app_database.dart';
import 'package:studyflow_domain/domain.dart';

final class ScheduleRepository {
  ScheduleRepository({
    required AccountScopedStore store,
    required PayloadCipher cipher,
  })  : _store = store,
        _cipher = cipher;

  static const int _schemaVersion = 1;

  final AccountScopedStore _store;
  final PayloadCipher _cipher;

  Future<void> save(
    ScheduleBlock block, {
    required EncryptedWrite write,
    DateTime? updatedAt,
  }) async {
    final associatedData = _associatedData(block.id);
    final encrypted = await _cipher.encrypt(
      utf8.encode(jsonEncode(block.toJson())),
      associatedData,
    );
    final record = EncryptedLocalRecord(
      accountId: _store.activeAccountId,
      recordId: block.id,
      entityType: EncryptedEntityType.scheduleBlock,
      schemaVersion: _schemaVersion,
      payloadNonce: encrypted.nonce,
      payloadCiphertext: encrypted.ciphertext,
      updatedAt: (updatedAt ?? DateTime.now()).toUtc(),
    );
    final operation = EncryptedOperation(
      accountId: _store.activeAccountId,
      operationId: write.operationId,
      recordId: block.id,
      deviceId: write.deviceId,
      logicalClock: write.logicalClock,
      entityType: EncryptedEntityType.scheduleBlock.wireName,
      payloadNonce: encrypted.nonce,
      payloadCiphertext: encrypted.ciphertext,
      isTombstone: false,
      schemaVersion: _schemaVersion,
    );

    await _store.transaction((transaction) async {
      await transaction.putRecord(record);
      await transaction.enqueue(operation);
    });
  }

  Future<ScheduleBlock?> get(String blockId) async {
    final record = await _store.records(EncryptedEntityType.scheduleBlock).get(
          accountId: _store.activeAccountId,
          recordId: blockId,
        );
    if (record == null) {
      return null;
    }
    return _read(record);
  }

  Future<List<ScheduleBlock>> list() async {
    final records = await _store
        .records(EncryptedEntityType.scheduleBlock)
        .list(accountId: _store.activeAccountId);
    final blocks = <ScheduleBlock>[];
    for (final record in records) {
      blocks.add(await _read(record));
    }
    blocks.sort((left, right) => left.start.compareTo(right.start));
    return blocks;
  }

  Future<ScheduleBlock> _read(EncryptedLocalRecord record) async {
    final plaintext = await _cipher.decrypt(
      EncryptedPayload(
        nonce: record.payloadNonce,
        ciphertext: record.payloadCiphertext,
      ),
      _associatedData(record.recordId),
    );
    final block = ScheduleBlock.fromJson(
      (jsonDecode(utf8.decode(plaintext)) as Map<String, dynamic>)
          .cast<String, Object?>(),
    );
    if (block.id != record.recordId) {
      throw const FormatException(
        'Encrypted schedule record id does not match payload id.',
      );
    }
    return block;
  }

  PayloadAssociatedData _associatedData(String recordId) =>
      PayloadAssociatedData(
        accountId: _store.activeAccountId,
        recordId: recordId,
        schemaVersion: _schemaVersion,
        entityType: EncryptedEntityType.scheduleBlock.wireName,
      );
}
