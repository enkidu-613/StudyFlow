import 'dart:convert';

import 'package:studyflow/features/tasks/task_repository.dart';
import 'package:studyflow/security/payload_cipher.dart';
import 'package:studyflow/storage/app_database.dart';
import 'package:studyflow_domain/domain.dart';

final class CheckInRepository {
  CheckInRepository({
    required AccountScopedStore store,
    required PayloadCipher cipher,
  })  : _store = store,
        _cipher = cipher;

  static const int _schemaVersion = 1;

  final AccountScopedStore _store;
  final PayloadCipher _cipher;

  Future<void> save(
    CheckIn checkIn, {
    required EncryptedWrite write,
    DateTime? updatedAt,
  }) async {
    final associatedData = _associatedData(checkIn.id);
    final encrypted = await _cipher.encrypt(
      utf8.encode(jsonEncode(checkIn.toJson())),
      associatedData,
    );
    final record = EncryptedLocalRecord(
      accountId: _store.activeAccountId,
      recordId: checkIn.id,
      entityType: EncryptedEntityType.checkIn,
      schemaVersion: _schemaVersion,
      payloadNonce: encrypted.nonce,
      payloadCiphertext: encrypted.ciphertext,
      updatedAt: (updatedAt ?? DateTime.now()).toUtc(),
    );
    final operation = EncryptedOperation(
      accountId: _store.activeAccountId,
      operationId: write.operationId,
      recordId: checkIn.id,
      deviceId: write.deviceId,
      logicalClock: write.logicalClock,
      entityType: EncryptedEntityType.checkIn.wireName,
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

  Future<CheckIn?> get(String checkInId) async {
    final record = await _store.records(EncryptedEntityType.checkIn).get(
          accountId: _store.activeAccountId,
          recordId: checkInId,
        );
    if (record == null) {
      return null;
    }
    return _read(record);
  }

  Future<List<CheckIn>> list() async {
    final records = await _store
        .records(EncryptedEntityType.checkIn)
        .list(accountId: _store.activeAccountId);
    final checkIns = <CheckIn>[];
    for (final record in records) {
      checkIns.add(await _read(record));
    }
    checkIns.sort((left, right) => right.recordedAt.compareTo(left.recordedAt));
    return checkIns;
  }

  Future<CheckIn> _read(EncryptedLocalRecord record) async {
    final plaintext = await _cipher.decrypt(
      EncryptedPayload(
        nonce: record.payloadNonce,
        ciphertext: record.payloadCiphertext,
      ),
      _associatedData(record.recordId),
    );
    final checkIn = CheckIn.fromJson(
      (jsonDecode(utf8.decode(plaintext)) as Map<String, dynamic>)
          .cast<String, Object?>(),
    );
    if (checkIn.id != record.recordId) {
      throw const FormatException(
        'Encrypted check-in record id does not match payload id.',
      );
    }
    return checkIn;
  }

  PayloadAssociatedData _associatedData(String recordId) =>
      PayloadAssociatedData(
        accountId: _store.activeAccountId,
        recordId: recordId,
        schemaVersion: _schemaVersion,
        entityType: EncryptedEntityType.checkIn.wireName,
      );
}
