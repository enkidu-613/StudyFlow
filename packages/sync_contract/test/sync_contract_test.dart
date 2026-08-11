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
      ((_fixture('sync_push_v2.json')['operations'] as List<dynamic>).first
          as Map<String, dynamic>),
    );

void main() {
  test('round-trips the push fixture with a plaintext payload', () {
    final fixture = _fixture('sync_push_v2.json');
    final operation = SyncOperationV2.fromJson(
      (fixture['operations'] as List<dynamic>).first as Map<String, dynamic>,
    );

    expect(operation.schemaVersion, 1);
    expect(operation.entityType, 'task');
    expect(operation.payload, <String, dynamic>{
      'title': 'Read chapter 1',
      'status': 'pending',
    });
    expect(operation.toJson(),
        (fixture['operations'] as List<dynamic>).first);
  });

  test('round-trips every pull fixture operation', () {
    final fixture = _fixture('sync_pull_v2.json');
    final operations = fixture['operations'] as List<dynamic>;

    for (final rawOperation in operations) {
      final operation = SyncOperationV2.fromJson(
        rawOperation as Map<String, dynamic>,
      );
      expect(operation.toJson(), rawOperation);
    }
  });

  test('rejects unsupported schema versions', () {
    final operation = _pushOperation()..['schemaVersion'] = 2;

    expect(
      () => SyncOperationV2.fromJson(operation),
      throwsA(isA<SyncContractException>()),
    );
  });

  test('normalizes uppercase UUID input to lowercase wire values', () {
    final operation = _pushOperation()
      ..['operationId'] = 'abcdefab-cdef-4abc-8def-abcdefabcdef'.toUpperCase()
      ..['recordId'] = 'fedcbafe-dcba-4fed-8abc-fedcbafedcba'.toUpperCase();

    final normalized = SyncOperationV2.fromJson(operation).toJson();

    expect(normalized['operationId'], 'abcdefab-cdef-4abc-8def-abcdefabcdef');
    expect(normalized['recordId'], 'fedcbafe-dcba-4fed-8abc-fedcbafedcba');
  });

  test('rejects unknown fields', () {
    final operation = _pushOperation()..['plaintext'] = 'task title';

    expect(
      () => SyncOperationV2.fromJson(operation),
      throwsA(isA<SyncContractException>()),
    );
  });

  test('rejects invalid UUID fields', () {
    for (final field in ['operationId', 'recordId']) {
      final operation = _pushOperation()..[field] = 'not-a-uuid';

      expect(
        () => SyncOperationV2.fromJson(operation),
        throwsA(isA<SyncContractException>()),
        reason: field,
      );
    }
  });

  test('rejects negative logical clocks', () {
    final operation = _pushOperation()..['logicalClock'] = -1;

    expect(
      () => SyncOperationV2.fromJson(operation),
      throwsA(isA<SyncContractException>()),
    );
  });

  test('rejects unsupported entity types', () {
    final operation = _pushOperation()..['entityType'] = 'note';

    expect(
      () => SyncOperationV2.fromJson(operation),
      throwsA(isA<SyncContractException>()),
    );
  });

  test('rejects a non-object payload', () {
    for (final payload in <Object?>['not-json', 1, <Object?>[]]) {
      final operation = _pushOperation()..['payload'] = payload;

      expect(
        () => SyncOperationV2.fromJson(operation),
        throwsA(isA<SyncContractException>()),
        reason: '$payload',
      );
    }
  });

  test('rejects an empty payload for non-tombstone operations', () {
    final operation = _pushOperation()..['payload'] = <String, dynamic>{};

    expect(
      () => SyncOperationV2.fromJson(operation),
      throwsA(isA<SyncContractException>()),
    );
  });

  test('allows an empty payload for tombstone operations', () {
    final operation = _pushOperation()
      ..['payload'] = <String, dynamic>{}
      ..['isTombstone'] = true;

    expect(SyncOperationV2.fromJson(operation).isTombstone, isTrue);
  });

  test('rejects oversized JSON payloads', () {
    final operation = _pushOperation()
      ..['payload'] = <String, dynamic>{
        'title': 'x' * maxPayloadBytes,
      };

    expect(
      () => SyncOperationV2.fromJson(operation),
      throwsA(isA<SyncContractException>()),
    );
  });

  test('rejects field type violations', () {
    final invalidValues = <String, dynamic>{
      'operationId': 1,
      'logicalClock': '7',
      'entityType': 1,
      'payload': 'json',
      'isTombstone': 'false',
      'schemaVersion': '1',
    };

    for (final entry in invalidValues.entries) {
      final operation = _pushOperation()..[entry.key] = entry.value;

      expect(
        () => SyncOperationV2.fromJson(operation),
        throwsA(isA<SyncContractException>()),
        reason: entry.key,
      );
    }
  });
}
