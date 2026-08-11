part of 'app_database.dart';

class EncryptedOperation {
  EncryptedOperation({
    required String accountId,
    required String operationId,
    required String recordId,
    required String deviceId,
    required this.logicalClock,
    required this.entityType,
    required List<int> payloadNonce,
    required List<int> payloadCiphertext,
    required this.isTombstone,
    required this.schemaVersion,
  })  : accountId = _normalizedUuid(accountId, 'accountId'),
        operationId = _normalizedUuid(operationId, 'operationId'),
        recordId = _normalizedUuid(recordId, 'recordId'),
        deviceId = _normalizedUuid(deviceId, 'deviceId'),
        _payloadNonce = Uint8List.fromList(payloadNonce),
        _payloadCiphertext = Uint8List.fromList(payloadCiphertext) {
    if (logicalClock < 0) {
      throw ArgumentError.value(
        logicalClock,
        'logicalClock',
        'must be non-negative',
      );
    }
    if (!_entityTypes.contains(entityType)) {
      throw ArgumentError.value(
        entityType,
        'entityType',
        'must be a supported encrypted entity type',
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
    if (schemaVersion != 1) {
      throw ArgumentError.value(
        schemaVersion,
        'schemaVersion',
        'must be the supported schema version 1',
      );
    }
  }

  final String accountId;
  final String operationId;
  final String recordId;
  final String deviceId;
  final int logicalClock;
  final String entityType;
  final Uint8List _payloadNonce;
  final Uint8List _payloadCiphertext;
  final bool isTombstone;
  final int schemaVersion;

  Uint8List get payloadNonce => Uint8List.fromList(_payloadNonce);
  Uint8List get payloadCiphertext => Uint8List.fromList(_payloadCiphertext);

  @override
  bool operator ==(Object other) =>
      other is EncryptedOperation &&
      accountId == other.accountId &&
      operationId == other.operationId &&
      recordId == other.recordId &&
      deviceId == other.deviceId &&
      logicalClock == other.logicalClock &&
      entityType == other.entityType &&
      _bytesEqual(_payloadNonce, other._payloadNonce) &&
      _bytesEqual(_payloadCiphertext, other._payloadCiphertext) &&
      isTombstone == other.isTombstone &&
      schemaVersion == other.schemaVersion;

  @override
  int get hashCode => Object.hash(
        accountId,
        operationId,
        recordId,
        deviceId,
        logicalClock,
        entityType,
        Object.hashAll(_payloadNonce),
        Object.hashAll(_payloadCiphertext),
        isTombstone,
        schemaVersion,
      );
}

class OperationDao {
  OperationDao._(this._database);

  final _AccountDatabase _database;

  Future<void> enqueue(EncryptedOperation operation) async {
    await _database.transaction(() async {
      await AccountScopedTransaction._(_database).enqueue(operation);
    });
  }

  Future<List<EncryptedOperation>> pending(int limit) async {
    if (limit <= 0) {
      throw ArgumentError.value(limit, 'limit', 'must be positive');
    }

    return _database.transaction(() async {
      final query = _database.select(_database.pendingOperations)
        ..where(
          (row) => row.accountId.equals(_database.activeAccountId),
        )
        ..orderBy(<OrderingTerm Function(_PendingOperations)>[
          (row) => OrderingTerm.asc(row.logicalClock),
          (row) => OrderingTerm.asc(row.operationId),
        ])
        ..limit(limit);
      final rows = await query.get();
      return rows
          .map(
            (row) => EncryptedOperation(
              accountId: row.accountId,
              operationId: row.operationId,
              recordId: row.recordId,
              deviceId: row.deviceId,
              logicalClock: row.logicalClock,
              entityType: row.entityType,
              payloadNonce: row.payloadNonce,
              payloadCiphertext: row.payloadCiphertext,
              isTombstone: row.isTombstone,
              schemaVersion: row.schemaVersion,
            ),
          )
          .toList(growable: false);
    });
  }
}

class OperationAccountScopeException implements Exception {
  const OperationAccountScopeException(this.message);

  final String message;

  @override
  String toString() => 'OperationAccountScopeException: $message';
}

class OperationIdCollisionException implements Exception {
  const OperationIdCollisionException(this.operationId);

  final String operationId;

  @override
  String toString() =>
      'OperationIdCollisionException: operation id is already used by '
      'different operation bytes: $operationId';
}

const Set<String> _entityTypes = <String>{
  'task',
  'schedule_block',
  'focus_session',
  'check_in',
};

String _normalizedUuid(String value, String fieldName) {
  final normalized = value.toLowerCase();
  final uuid = RegExp(
    r'^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$',
  );
  if (!uuid.hasMatch(normalized)) {
    throw ArgumentError.value(value, fieldName, 'must be a UUID');
  }
  return normalized;
}

bool _bytesEqual(List<int> left, List<int> right) {
  if (left.length != right.length) {
    return false;
  }
  for (var index = 0; index < left.length; index++) {
    if (left[index] != right[index]) {
      return false;
    }
  }
  return true;
}
