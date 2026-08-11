import 'dart:convert';

import 'sync_error.dart';

const int maxPayloadBytes = 256 * 1024;
const Set<String> supportedEntityTypes = <String>{
  'task',
  'schedule_block',
  'focus_session',
  'check_in',
};

class SyncOperationV1 {
  SyncOperationV1({
    required String operationId,
    required String recordId,
    required String deviceId,
    required this.logicalClock,
    required this.entityType,
    required this.payloadNonce,
    required this.payloadCiphertext,
    required this.isTombstone,
    required this.schemaVersion,
  })  : operationId = operationId.toLowerCase(),
        recordId = recordId.toLowerCase(),
        deviceId = deviceId.toLowerCase() {
    _validate();
  }

  factory SyncOperationV1.fromJson(Map<String, dynamic> json) {
    const fields = <String>{
      'operationId',
      'recordId',
      'deviceId',
      'logicalClock',
      'entityType',
      'payloadNonce',
      'payloadCiphertext',
      'isTombstone',
      'schemaVersion',
    };
    final unknownFields = json.keys.where((key) => !fields.contains(key));
    if (unknownFields.isNotEmpty) {
      throw SyncContractException('unknown fields: ${unknownFields.join(', ')}');
    }
    try {
      return SyncOperationV1(
        operationId: json['operationId'] as String,
        recordId: json['recordId'] as String,
        deviceId: json['deviceId'] as String,
        logicalClock: json['logicalClock'] as int,
        entityType: json['entityType'] as String,
        payloadNonce: json['payloadNonce'] as String,
        payloadCiphertext: json['payloadCiphertext'] as String,
        isTombstone: json['isTombstone'] as bool,
        schemaVersion: json['schemaVersion'] as int,
      );
    } on TypeError {
      throw const SyncContractException('operation has invalid field types');
    }
  }

  final String operationId;
  final String recordId;
  final String deviceId;
  final int logicalClock;
  final String entityType;
  final String payloadNonce;
  final String payloadCiphertext;
  final bool isTombstone;
  final int schemaVersion;

  Map<String, dynamic> toJson() => <String, dynamic>{
        'operationId': operationId,
        'recordId': recordId,
        'deviceId': deviceId,
        'logicalClock': logicalClock,
        'entityType': entityType,
        'payloadNonce': payloadNonce,
        'payloadCiphertext': payloadCiphertext,
        'isTombstone': isTombstone,
        'schemaVersion': schemaVersion,
      };

  void _validate() {
    _validateUuid(operationId, 'operationId');
    _validateUuid(recordId, 'recordId');
    _validateUuid(deviceId, 'deviceId');
    if (logicalClock < 0) {
      throw const SyncContractException('logicalClock must be non-negative');
    }
    if (!supportedEntityTypes.contains(entityType)) {
      throw SyncContractException('unsupported entityType: $entityType');
    }
    _validateBase64(
      payloadNonce,
      'payloadNonce',
      requireNonEmpty: true,
      maxBytes: maxPayloadBytes,
    );
    _validateBase64(
      payloadCiphertext,
      'payloadCiphertext',
      requireNonEmpty: true,
      maxBytes: maxPayloadBytes,
    );
    if (schemaVersion != 1) {
      throw SyncContractException('unsupported schemaVersion: $schemaVersion');
    }
  }

  static void _validateUuid(String value, String fieldName) {
    final uuid = RegExp(
      r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$',
    );
    if (!uuid.hasMatch(value)) {
      throw SyncContractException('$fieldName must be a valid UUID');
    }
  }

  static void _validateBase64(
    String value,
    String fieldName, {
    required bool requireNonEmpty,
    int? maxBytes,
  }) {
    if (requireNonEmpty && value.isEmpty) {
      throw SyncContractException('$fieldName must not be empty');
    }
    try {
      final decoded = base64.decode(value);
      if (base64.encode(decoded) != value) {
        throw const FormatException();
      }
      if (maxBytes != null && decoded.length > maxBytes) {
        throw SyncContractException('$fieldName must be at most 256 KiB');
      }
    } on SyncContractException {
      rethrow;
    } on FormatException {
      throw SyncContractException('$fieldName must be valid base64');
    }
  }
}
