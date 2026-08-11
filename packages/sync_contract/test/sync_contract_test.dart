import 'dart:convert';
import 'dart:io';

import 'package:studyflow_sync_contract/sync_contract.dart';
import 'package:test/test.dart';

Map<String, dynamic> _fixture(String name) {
  final candidates = <File>[
    File('tests/contract/$name'),
    File('../../tests/contract/$name'),
  ];
  final fixture = candidates.firstWhere((file) => file.existsSync());
  return jsonDecode(fixture.readAsStringSync()) as Map<String, dynamic>;
}

Map<String, dynamic> _pushOperation() => Map<String, dynamic>.from(
      ((_fixture('sync_push_v1.json')['operations'] as List<dynamic>).first
          as Map<String, dynamic>),
    );

void main() {
  test('round-trips the push fixture without decrypting payload', () {
    final fixture = _fixture('sync_push_v1.json');
    final operation = SyncOperationV1.fromJson(
      (fixture['operations'] as List<dynamic>).first as Map<String, dynamic>,
    );

    expect(operation.schemaVersion, 1);
    expect(operation.entityType, 'task');
    expect(operation.payloadCiphertext, isNotEmpty);
    expect(operation.toJson(),
        (fixture['operations'] as List<dynamic>).first);
  });

  test('round-trips every pull fixture operation', () {
    final fixture = _fixture('sync_pull_v1.json');
    final operations = fixture['operations'] as List<dynamic>;

    for (final rawOperation in operations) {
      final operation = SyncOperationV1.fromJson(
        rawOperation as Map<String, dynamic>,
      );
      expect(operation.toJson(), rawOperation);
    }
  });

  test('rejects unsupported schema versions', () {
    final operation = _pushOperation()..['schemaVersion'] = 2;

    expect(
      () => SyncOperationV1.fromJson(operation),
      throwsA(isA<SyncContractException>()),
    );
  });

  test('normalizes uppercase UUID input to lowercase wire values', () {
    final operation = _pushOperation()
      ..['operationId'] = 'abcdefab-cdef-4abc-8def-abcdefabcdef'.toUpperCase()
      ..['recordId'] = 'fedcbafe-dcba-4fed-8abc-fedcbafedcba'.toUpperCase()
      ..['deviceId'] = 'abcdefab-cdef-4abc-8def-abcdefabcdea'.toUpperCase();

    final normalized = SyncOperationV1.fromJson(operation).toJson();

    expect(normalized['operationId'], 'abcdefab-cdef-4abc-8def-abcdefabcdef');
    expect(normalized['recordId'], 'fedcbafe-dcba-4fed-8abc-fedcbafedcba');
    expect(normalized['deviceId'], 'abcdefab-cdef-4abc-8def-abcdefabcdea');
  });

  test('rejects unknown fields', () {
    final operation = _pushOperation()..['plaintext'] = 'task title';

    expect(
      () => SyncOperationV1.fromJson(operation),
      throwsA(isA<SyncContractException>()),
    );
  });

  test('rejects invalid UUID fields', () {
    for (final field in ['operationId', 'recordId', 'deviceId']) {
      final operation = _pushOperation()..[field] = 'not-a-uuid';

      expect(
        () => SyncOperationV1.fromJson(operation),
        throwsA(isA<SyncContractException>()),
        reason: field,
      );
    }
  });

  test('rejects negative logical clocks', () {
    final operation = _pushOperation()..['logicalClock'] = -1;

    expect(
      () => SyncOperationV1.fromJson(operation),
      throwsA(isA<SyncContractException>()),
    );
  });

  test('rejects unsupported entity types', () {
    final operation = _pushOperation()..['entityType'] = 'note';

    expect(
      () => SyncOperationV1.fromJson(operation),
      throwsA(isA<SyncContractException>()),
    );
  });

  test('rejects malformed base64 payloads', () {
    for (final field in ['payloadNonce', 'payloadCiphertext']) {
      final operation = _pushOperation()..[field] = 'not-base64!!!';

      expect(
        () => SyncOperationV1.fromJson(operation),
        throwsA(isA<SyncContractException>()),
        reason: field,
      );
    }
  });

  test('rejects oversized decoded payloads', () {
    final oversizedPayload = base64Encode(List<int>.filled(maxPayloadBytes + 1, 0));

    for (final field in ['payloadNonce', 'payloadCiphertext']) {
      final operation = _pushOperation()..[field] = oversizedPayload;

      expect(
        () => SyncOperationV1.fromJson(operation),
        throwsA(isA<SyncContractException>()),
        reason: field,
      );
    }
  });

  test('rejects field type violations', () {
    final invalidValues = <String, dynamic>{
      'operationId': 1,
      'logicalClock': '7',
      'entityType': 1,
      'payloadNonce': 1,
      'payloadCiphertext': 1,
      'isTombstone': 'false',
      'schemaVersion': '1',
    };

    for (final entry in invalidValues.entries) {
      final operation = _pushOperation()..[entry.key] = entry.value;

      expect(
        () => SyncOperationV1.fromJson(operation),
        throwsA(isA<SyncContractException>()),
        reason: entry.key,
      );
    }
  });
}
