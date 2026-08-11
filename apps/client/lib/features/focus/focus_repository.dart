import 'dart:convert';

import 'package:studyflow/features/tasks/task_repository.dart';
import 'package:studyflow/security/payload_cipher.dart';
import 'package:studyflow/storage/app_database.dart';
import 'package:studyflow_domain/domain.dart';

final class FocusRepository {
  FocusRepository({
    required AccountScopedStore store,
    required PayloadCipher cipher,
  })  : _store = store,
        _cipher = cipher;

  static const int _schemaVersion = 1;

  final AccountScopedStore _store;
  final PayloadCipher _cipher;

  Future<void> save(
    FocusSession session, {
    required EncryptedWrite write,
    DateTime? updatedAt,
  }) async {
    final associatedData = _associatedData(session.id);
    final encrypted = await _cipher.encrypt(
      utf8.encode(jsonEncode(session.toJson())),
      associatedData,
    );
    final record = EncryptedLocalRecord(
      accountId: _store.activeAccountId,
      recordId: session.id,
      entityType: EncryptedEntityType.focusSession,
      schemaVersion: _schemaVersion,
      payloadNonce: encrypted.nonce,
      payloadCiphertext: encrypted.ciphertext,
      updatedAt: (updatedAt ?? DateTime.now()).toUtc(),
    );
    final operation = EncryptedOperation(
      accountId: _store.activeAccountId,
      operationId: write.operationId,
      recordId: session.id,
      deviceId: write.deviceId,
      logicalClock: write.logicalClock,
      entityType: EncryptedEntityType.focusSession.wireName,
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

  Future<FocusSession?> get(String sessionId) async {
    final record = await _store.records(EncryptedEntityType.focusSession).get(
          accountId: _store.activeAccountId,
          recordId: sessionId,
        );
    if (record == null) {
      return null;
    }
    return _read(record);
  }

  Future<List<FocusSession>> list() async {
    final records = await _store
        .records(EncryptedEntityType.focusSession)
        .list(accountId: _store.activeAccountId);
    final sessions = <FocusSession>[];
    for (final record in records) {
      sessions.add(await _read(record));
    }
    sessions.sort((left, right) => right.startedAt.compareTo(left.startedAt));
    return sessions;
  }

  Future<FocusSession> _read(EncryptedLocalRecord record) async {
    final plaintext = await _cipher.decrypt(
      EncryptedPayload(
        nonce: record.payloadNonce,
        ciphertext: record.payloadCiphertext,
      ),
      _associatedData(record.recordId),
    );
    final session = FocusSession.fromJson(
      (jsonDecode(utf8.decode(plaintext)) as Map<String, dynamic>)
          .cast<String, Object?>(),
    );
    if (session.id != record.recordId) {
      throw const FormatException(
        'Encrypted focus record id does not match payload id.',
      );
    }
    return session;
  }

  PayloadAssociatedData _associatedData(String recordId) =>
      PayloadAssociatedData(
        accountId: _store.activeAccountId,
        recordId: recordId,
        schemaVersion: _schemaVersion,
        entityType: EncryptedEntityType.focusSession.wireName,
      );
}
