import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:studyflow/auth/auth_repository.dart';
import 'package:studyflow/features/backups/backup_models.dart';
import 'package:studyflow/features/backups/backups_repository.dart';

AuthContext context() => AuthContext(
      userId: '11111111-1111-4111-8111-111111111111',
      email: 'user@example.com',
      accessToken: 'access-token',
      refreshToken: 'refresh-token',
      expiresIn: 900,
    );

HttpBackupsRepository repositoryWith(
  MockClient client,
) =>
    HttpBackupsRepository(
      baseUri: Uri.parse('https://api.example.com'),
      authContext: context(),
      client: client,
    );

BackupSummary summaryJson(Map<String, Object?> overrides) =>
    BackupSummary.fromApiJson(<String, Object?>{
      'backup_id': '22222222-2222-4222-8222-222222222222',
      'name': '考前备份',
      'created_at': '2026-08-13T04:00:00Z',
      'size_bytes': 2048,
      'operation_count': 3,
      'status': 'ready',
      ...overrides,
    });

void main() {
  test('create posts name and parses 201 summary', () async {
    late http.Request captured;
    final client = MockClient((request) async {
      captured = request;
      return http.Response(
        jsonEncode(
          summaryJson(<String, Object?>{}).toJsonForTest(),
        ),
        201,
        headers: <String, String>{'content-type': 'application/json; charset=utf-8'},
      );
    });
    final repository = repositoryWith(client);

    final backup = await repository.create(name: '考前备份');

    expect(captured.method, 'POST');
    expect(captured.url.path, '/v1/backups');
    expect(captured.headers['Authorization'], 'Bearer access-token');
    expect(jsonDecode(captured.body), <String, Object?>{'name': '考前备份'});
    expect(backup.name, '考前备份');
    expect(backup.backupId, '22222222-2222-4222-8222-222222222222');
  });

  test('create without name sends empty object', () async {
    late http.Request captured;
    final client = MockClient((request) async {
      captured = request;
      return http.Response(
        jsonEncode(
          summaryJson(<String, Object?>{}).toJsonForTest(),
        ),
        201,
        headers: <String, String>{'content-type': 'application/json; charset=utf-8'},
      );
    });
    final repository = repositoryWith(client);

    await repository.create();

    expect(jsonDecode(captured.body), <String, Object?>{});
  });

  test('create 409 maps to BackupQuotaFailure', () async {
    final client = MockClient(
      (request) async => http.Response('quota', 409),
    );
    final repository = repositoryWith(client);

    expect(
      () => repository.create(),
      throwsA(isA<BackupQuotaFailure>()),
    );
  });

  test('list parses backups array', () async {
    final client = MockClient(
      (request) async => http.Response(
        jsonEncode(<String, Object?>{
          'backups': <Object?>[
            summaryJson(<String, Object?>{}).toJsonForTest(),
          ],
        }),
        200,
        headers: <String, String>{'content-type': 'application/json; charset=utf-8'},
      ),
    );
    final repository = repositoryWith(client);

    final result = await repository.list();

    expect(result.backups, hasLength(1));
    expect(result.backups.single.name, '考前备份');
  });

  test('list 401 maps to BackupAuthenticationFailure', () async {
    final client = MockClient((request) async => http.Response('no', 401));
    final repository = repositoryWith(client);

    expect(
      () => repository.list(),
      throwsA(isA<BackupAuthenticationFailure>()),
    );
  });

  test('rename sends PATCH with name and parses summary', () async {
    late http.Request captured;
    final client = MockClient((request) async {
      captured = request;
      return http.Response(
        jsonEncode(
          summaryJson(<String, Object?>{'name': '新名字'}).toJsonForTest(),
        ),
        200,
        headers: <String, String>{'content-type': 'application/json; charset=utf-8'},
      );
    });
    final repository = repositoryWith(client);

    final backup = await repository.rename(
      '22222222-2222-4222-8222-222222222222',
      '新名字',
    );

    expect(captured.method, 'PATCH');
    expect(captured.url.path, '/v1/backups/22222222-2222-4222-8222-222222222222');
    expect(jsonDecode(captured.body), <String, Object?>{'name': '新名字'});
    expect(backup.name, '新名字');
  });

  test('rename 404 maps to BackupNotFoundFailure', () async {
    final client = MockClient((request) async => http.Response('no', 404));
    final repository = repositoryWith(client);

    expect(
      () => repository.rename('22222222-2222-4222-8222-222222222222', 'x'),
      throwsA(isA<BackupNotFoundFailure>()),
    );
  });

  test('delete sends DELETE and accepts 204', () async {
    late http.Request captured;
    final client = MockClient((request) async {
      captured = request;
      return http.Response('', 204);
    });
    final repository = repositoryWith(client);

    await repository.delete('22222222-2222-4222-8222-222222222222');

    expect(captured.method, 'DELETE');
    expect(captured.url.path, '/v1/backups/22222222-2222-4222-8222-222222222222');
  });

  test('delete 429 maps to BackupRateLimitFailure', () async {
    final client = MockClient((request) async => http.Response('slow', 429));
    final repository = repositoryWith(client);

    expect(
      () => repository.delete('22222222-2222-4222-8222-222222222222'),
      throwsA(isA<BackupRateLimitFailure>()),
    );
  });

  test('rejects non-HTTPS base URIs', () {
    expect(
      () => HttpBackupsRepository(
        baseUri: Uri.parse('http://api.example.com'),
        authContext: context(),
      ),
      throwsArgumentError,
    );
  });

  test('deleteMany posts ids and parses deleted/not_found', () async {
    late http.Request captured;
    final client = MockClient((request) async {
      captured = request;
      return http.Response(
        jsonEncode(<String, Object?>{
          'deleted': 1,
          'not_found': <String>['33333333-3333-4333-8333-333333333333'],
        }),
        200,
        headers: <String, String>{'content-type': 'application/json; charset=utf-8'},
      );
    });
    final repository = repositoryWith(client);

    final result = await repository.deleteMany(<String>[
      '22222222-2222-4222-8222-222222222222',
      '33333333-3333-4333-8333-333333333333',
    ]);

    expect(captured.method, 'POST');
    expect(captured.url.path, '/v1/backups/batch-delete');
    expect(jsonDecode(captured.body), <String, Object?>{
      'backup_ids': <String>[
        '22222222-2222-4222-8222-222222222222',
        '33333333-3333-4333-8333-333333333333',
      ],
    });
    expect(result.deleted, 1);
    expect(result.notFound, <String>['33333333-3333-4333-8333-333333333333']);
  });

  test('deleteMany rejects unexpected response fields', () async {
    final client = MockClient(
      (request) async => http.Response(
        jsonEncode(<String, Object?>{'deleted': 1}),
        200,
        headers: <String, String>{'content-type': 'application/json; charset=utf-8'},
      ),
    );
    final repository = repositoryWith(client);

    expect(
      () => repository.deleteMany(<String>['22222222-2222-4222-8222-222222222222']),
      throwsA(isA<BackupSchemaFailure>()),
    );
  });

  test('deleteMany 401 maps to BackupAuthenticationFailure', () async {
    final client = MockClient((request) async => http.Response('no', 401));
    final repository = repositoryWith(client);

    expect(
      () => repository.deleteMany(<String>['22222222-2222-4222-8222-222222222222']),
      throwsA(isA<BackupAuthenticationFailure>()),
    );
  });
}

extension on BackupSummary {
  Map<String, Object?> toJsonForTest() => <String, Object?>{
        'backup_id': backupId,
        'name': name,
        'created_at': createdAt.toIso8601String(),
        'size_bytes': sizeBytes,
        'operation_count': operationCount,
        'status': status,
      };
}
