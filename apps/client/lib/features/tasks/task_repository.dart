import 'dart:convert';

import 'package:studyflow/security/payload_cipher.dart';
import 'package:studyflow/storage/app_database.dart';
import 'package:studyflow_domain/domain.dart';

final class EncryptedWrite {
  EncryptedWrite({
    required this.operationId,
    required this.deviceId,
    required this.logicalClock,
  }) {
    if (logicalClock < 0) {
      throw ArgumentError.value(
          logicalClock, 'logicalClock', 'must be non-negative');
    }
  }

  final String operationId;
  final String deviceId;
  final int logicalClock;
}

final class TaskRepository {
  TaskRepository({
    required AccountScopedStore store,
    required PayloadCipher cipher,
  })  : _store = store,
        _cipher = cipher;

  static const int _schemaVersion = 1;

  final AccountScopedStore _store;
  final PayloadCipher _cipher;

  Future<void> save(
    Task task, {
    required EncryptedWrite write,
    DateTime? updatedAt,
  }) async {
    final associatedData = _associatedData(task.id);
    final encrypted = await _cipher.encrypt(
      utf8.encode(jsonEncode(task.toJson())),
      associatedData,
    );
    final record = EncryptedLocalRecord(
      accountId: _store.activeAccountId,
      recordId: task.id,
      entityType: EncryptedEntityType.task,
      schemaVersion: _schemaVersion,
      payloadNonce: encrypted.nonce,
      payloadCiphertext: encrypted.ciphertext,
      updatedAt: (updatedAt ?? DateTime.now()).toUtc(),
    );
    final operation = EncryptedOperation(
      accountId: _store.activeAccountId,
      operationId: write.operationId,
      recordId: task.id,
      deviceId: write.deviceId,
      logicalClock: write.logicalClock,
      entityType: EncryptedEntityType.task.wireName,
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

  Future<Task?> get(String taskId) async {
    final record = await _store.records(EncryptedEntityType.task).get(
          accountId: _store.activeAccountId,
          recordId: taskId,
        );
    if (record == null) {
      return null;
    }
    final plaintext = await _cipher.decrypt(
      EncryptedPayload(
        nonce: record.payloadNonce,
        ciphertext: record.payloadCiphertext,
      ),
      _associatedData(taskId),
    );
    final task = Task.fromJson(
      (jsonDecode(utf8.decode(plaintext)) as Map<String, dynamic>)
          .cast<String, Object?>(),
    );
    if (task.id != taskId) {
      throw const FormatException(
          'Encrypted task record id does not match payload id.');
    }
    return task;
  }

  PayloadAssociatedData _associatedData(String recordId) =>
      PayloadAssociatedData(
        accountId: _store.activeAccountId,
        recordId: recordId,
        schemaVersion: _schemaVersion,
        entityType: EncryptedEntityType.task.wireName,
      );
}
