import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:studyflow/auth/auth_repository.dart';
import 'package:studyflow/features/backups/backup_models.dart';

abstract interface class BackupsRepository {
  Future<BackupSummary> create({String? name});

  Future<BackupListResult> list();

  Future<BackupSummary> rename(String backupId, String name);

  Future<void> delete(String backupId);
}

final class HttpBackupsRepository implements BackupsRepository {
  HttpBackupsRepository({
    required Uri baseUri,
    required AuthContext authContext,
    http.Client? client,
  })  : _baseUri = _validateBaseUri(baseUri),
        _authContext = authContext,
        _client = client ?? http.Client();

  static const _timeout = Duration(seconds: 30);

  final Uri _baseUri;
  final AuthContext _authContext;
  final http.Client _client;

  @override
  Future<BackupSummary> create({String? name}) async {
    final body = <String, Object?>{
      if (name != null && name.isNotEmpty) 'name': name,
    };
    final json = _object(
      await _send(
        'POST',
        '/v1/backups',
        body: jsonEncode(body),
        acceptedStatusCodes: const <int>{201},
      ),
      'create backup response',
    );
    try {
      return BackupSummary.fromApiJson(json.cast<String, Object?>());
    } on FormatException catch (error) {
      throw BackupSchemaFailure(
        'Create backup response was invalid.',
        cause: error,
      );
    }
  }

  @override
  Future<BackupListResult> list() async {
    final json = _object(
      await _send('GET', '/v1/backups'),
      'list backups response',
    );
    _requireKeys(json, const <String>{'backups'}, 'list backups response');
    final backups = json['backups'];
    if (backups is! List) {
      throw const BackupSchemaFailure('Backups must be a list.');
    }
    try {
      return BackupListResult(
        backups: backups.map((item) {
          final map = _object(item, 'backup item');
          return BackupSummary.fromApiJson(map.cast<String, Object?>());
        }),
      );
    } on BackupApiFailure {
      rethrow;
    } on Object catch (error) {
      throw BackupSchemaFailure(
        'Backup item violated the contract.',
        cause: error,
      );
    }
  }

  @override
  Future<BackupSummary> rename(String backupId, String name) async {
    final json = _object(
      await _send(
        'PATCH',
        '/v1/backups/$backupId',
        body: jsonEncode(<String, Object?>{'name': name}),
      ),
      'rename backup response',
    );
    try {
      return BackupSummary.fromApiJson(json.cast<String, Object?>());
    } on FormatException catch (error) {
      throw BackupSchemaFailure(
        'Rename backup response was invalid.',
        cause: error,
      );
    }
  }

  @override
  Future<void> delete(String backupId) async {
    await _send(
      'DELETE',
      '/v1/backups/$backupId',
      acceptedStatusCodes: const <int>{204},
    );
  }

  Future<Object?> _send(
    String method,
    String path, {
    String? body,
    Set<int> acceptedStatusCodes = const <int>{200},
  }) async {
    try {
      final uri = _baseUri.resolve(path);
      final request = http.Request(method, uri)
        ..headers.addAll(_headers())
        ..body = body ?? '';
      final streamed = await _client.send(request).timeout(_timeout);
      final response = await http.Response.fromStream(streamed);
      if (response.statusCode == 401 || response.statusCode == 403) {
        throw const BackupAuthenticationFailure(
          'Backup credentials were rejected.',
        );
      }
      if (response.statusCode == 409) {
        throw const BackupQuotaFailure(
          'Backup limit reached.',
        );
      }
      if (response.statusCode == 404) {
        throw const BackupNotFoundFailure('Backup was not found.');
      }
      if (response.statusCode == 422) {
        throw const BackupSchemaFailure(
          'Backup request violated the server contract.',
        );
      }
      if (!acceptedStatusCodes.contains(response.statusCode)) {
        throw BackupServerFailure(
          'Backup server returned HTTP ${response.statusCode}.',
        );
      }
      if (response.body.isEmpty) {
        return null;
      }
      try {
        return jsonDecode(response.body);
      } on FormatException catch (error) {
        throw BackupSchemaFailure(
          'Backup response was not valid JSON.',
          cause: error,
        );
      }
    } on BackupApiFailure {
      rethrow;
    } on SocketException catch (error) {
      throw BackupOfflineFailure('Network is offline.', cause: error);
    } on http.ClientException catch (error) {
      throw BackupNetworkFailure('Backup request failed.', cause: error);
    } on TimeoutException catch (error) {
      throw BackupNetworkFailure('Backup request timed out.', cause: error);
    }
  }

  Map<String, String> _headers() => <String, String>{
        'Accept': 'application/json',
        'Content-Type': 'application/json',
        'Authorization': 'Bearer ${_authContext.accessToken}',
      };

  void close() => _client.close();
}

sealed class BackupApiFailure implements Exception {
  const BackupApiFailure(this.message, {this.cause});

  final String message;
  final Object? cause;

  @override
  String toString() {
    final causeText = cause == null ? '' : ' (cause: $cause)';
    return '$message$causeText';
  }
}

final class BackupQuotaFailure extends BackupApiFailure {
  const BackupQuotaFailure(super.message, {super.cause});
}

final class BackupServerFailure extends BackupApiFailure {
  const BackupServerFailure(super.message, {super.cause});
}

final class BackupNotFoundFailure extends BackupApiFailure {
  const BackupNotFoundFailure(super.message, {super.cause});
}

final class BackupAuthenticationFailure extends BackupApiFailure {
  const BackupAuthenticationFailure(super.message, {super.cause});
}

final class BackupNetworkFailure extends BackupApiFailure {
  const BackupNetworkFailure(super.message, {super.cause});
}

final class BackupOfflineFailure extends BackupApiFailure {
  const BackupOfflineFailure(super.message, {super.cause});
}

final class BackupSchemaFailure extends BackupApiFailure {
  const BackupSchemaFailure(super.message, {super.cause});
}

Uri _validateBaseUri(Uri uri) {
  final loopback =
      uri.host == 'localhost' || uri.host == '127.0.0.1' || uri.host == '::1';
  if (uri.host.isEmpty ||
      (uri.scheme != 'https' && !(uri.scheme == 'http' && loopback)) ||
      uri.userInfo.isNotEmpty ||
      uri.hasQuery ||
      uri.hasFragment) {
    throw ArgumentError.value(uri, 'baseUri', 'must be a secure HTTP origin');
  }
  return uri;
}

Map<String, Object?> _object(Object? value, String label) {
  if (value is! Map) {
    throw BackupSchemaFailure('$label must be an object.');
  }
  final result = <String, Object?>{};
  for (final entry in value.entries) {
    if (entry.key is! String) {
      throw BackupSchemaFailure('$label contains a non-string key.');
    }
    result[entry.key as String] = entry.value;
  }
  return result;
}

void _requireKeys(
  Map<String, Object?> json,
  Set<String> expected,
  String label,
) {
  if (json.keys.toSet().difference(expected).isNotEmpty ||
      expected.difference(json.keys.toSet()).isNotEmpty) {
    throw BackupSchemaFailure('$label contains unexpected fields.');
  }
}
