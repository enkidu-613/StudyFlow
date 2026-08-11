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

    await _store.records(EncryptedEntityType.scheduleBlock).put(record);
    await _store.operations.enqueue(
      EncryptedOperation(
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
      ),
    );
  }

  Future<ScheduleBlock?> get(String blockId) async {
    final record = await _store.records(EncryptedEntityType.scheduleBlock).get(
          accountId: _store.activeAccountId,
          recordId: blockId,
        );
    if (record == null) {
      return null;
    }
    final plaintext = await _cipher.decrypt(
      EncryptedPayload(
        nonce: record.payloadNonce,
        ciphertext: record.payloadCiphertext,
      ),
      _associatedData(blockId),
    );
    final block = ScheduleBlock.fromJson(
      (jsonDecode(utf8.decode(plaintext)) as Map<String, dynamic>)
          .cast<String, Object?>(),
    );
    if (block.id != blockId) {
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
