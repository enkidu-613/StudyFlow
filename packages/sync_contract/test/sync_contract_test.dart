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
    final operation = Map<String, dynamic>.from(
      ((_fixture('sync_push_v1.json')['operations'] as List<dynamic>).first
          as Map<String, dynamic>),
    )..['schemaVersion'] = 2;

    expect(
      () => SyncOperationV1.fromJson(operation),
      throwsA(isA<SyncContractException>()),
    );
  });
}
