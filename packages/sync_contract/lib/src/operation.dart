import 'dart:convert';

import 'sync_error.dart';

const int maxPayloadBytes = 256 * 1024;
const Set<String> supportedEntityTypes = <String>{
  'task',
  'schedule_block',
  'focus_session',
  'check_in',
  'schedule_feedback',
  'medication_plan',
  'medication_dose_record',
};

class SyncOperationV2 {
  SyncOperationV2({
    required String operationId,
    required String recordId,
    required this.logicalClock,
    required this.entityType,
    required this.payload,
    required this.isTombstone,
    required this.schemaVersion,
  })  : operationId = operationId.toLowerCase(),
        recordId = recordId.toLowerCase() {
    _validate();
  }

  factory SyncOperationV2.fromJson(Map<String, dynamic> json) {
    const fields = <String>{
      'operationId',
      'recordId',
      'logicalClock',
      'entityType',
      'payload',
      'isTombstone',
      'schemaVersion',
    };
    final unknownFields = json.keys.where((key) => !fields.contains(key));
    if (unknownFields.isNotEmpty) {
      throw SyncContractException(
          'unknown fields: ${unknownFields.join(', ')}');
    }
    try {
      final payload = json['payload'];
      if (payload is! Map<String, dynamic>) {
        throw const SyncContractException('payload must be a JSON object');
      }
      return SyncOperationV2(
        operationId: json['operationId'] as String,
        recordId: json['recordId'] as String,
        logicalClock: json['logicalClock'] as int,
        entityType: json['entityType'] as String,
        payload: payload,
        isTombstone: json['isTombstone'] as bool,
        schemaVersion: json['schemaVersion'] as int,
      );
    } on TypeError {
      throw const SyncContractException('operation has invalid field types');
    }
  }

  final String operationId;
  final String recordId;
  final int logicalClock;
  final String entityType;
  final Map<String, dynamic> payload;
  final bool isTombstone;
  final int schemaVersion;

  Map<String, dynamic> toJson() => <String, dynamic>{
        'operationId': operationId,
        'recordId': recordId,
        'logicalClock': logicalClock,
        'entityType': entityType,
        'payload': payload,
        'isTombstone': isTombstone,
        'schemaVersion': schemaVersion,
      };

  void _validate() {
    _validateUuid(operationId, 'operationId');
    _validateUuid(recordId, 'recordId');
    if (logicalClock < 0) {
      throw const SyncContractException('logicalClock must be non-negative');
    }
    if (!supportedEntityTypes.contains(entityType)) {
      throw SyncContractException('unsupported entityType: $entityType');
    }
    if (payload.isEmpty && !isTombstone) {
      throw const SyncContractException(
        'payload must not be empty for non-tombstone operations',
      );
    }
    final payloadBytes = utf8.encode(jsonEncode(payload)).length;
    if (payloadBytes > maxPayloadBytes) {
      throw SyncContractException('payload must be at most 256 KiB');
    }
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
}
