import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:studyflow/auth/auth_repository.dart';
import 'package:studyflow_sync_contract/sync_contract.dart';

abstract interface class SyncApi {
  Future<SyncPushResult> push({
    required AuthContext authContext,
    required List<SyncOperationV2> operations,
  });

  Future<SyncPullResult> pull({
    required AuthContext authContext,
    required int after,
    int limit = 50,
  });
}

final class HttpSyncApi implements SyncApi {
  HttpSyncApi({required Uri baseUri, http.Client? client})
      : _baseUri = _validateBaseUri(baseUri),
        _client = client ?? http.Client();

  final Uri _baseUri;
  final http.Client _client;

  @override
  Future<SyncPushResult> push({
    required AuthContext authContext,
    required List<SyncOperationV2> operations,
  }) async {
    final json = _object(
      await _send(
        authContext,
        _baseUri.resolve('/v1/sync/push'),
        body: jsonEncode(<String, Object?>{
          'operations': operations
              .map<Object?>((operation) => operation.toJson())
              .toList(growable: false),
        }),
      ),
      'push response',
    );
    _requireKeys(
      json,
      const <String>{'accepted', 'duplicates', 'rejected'},
      'push response',
    );
    return SyncPushResult(
      accepted: _stringList(json['accepted'], 'accepted'),
      duplicates: _stringList(json['duplicates'], 'duplicates'),
      rejected: _stringList(json['rejected'], 'rejected'),
    );
  }

  @override
  Future<SyncPullResult> pull({
    required AuthContext authContext,
    required int after,
    int limit = 50,
  }) async {
    if (after < 0 || limit < 1 || limit > 200) {
      throw ArgumentError('Pull cursor and limit are outside the contract.');
    }
    final uri = _baseUri.resolve('/v1/sync/pull').replace(
      queryParameters: <String, String>{
        'after': '$after',
        'limit': '$limit',
      },
    );
    final json = _object(await _send(authContext, uri), 'pull response');
    _requireKeys(
      json,
      const <String>{'next_cursor', 'operations'},
      'pull response',
    );
    final nextCursor = json['next_cursor'];
    final operations = json['operations'];
    if (nextCursor is! int || nextCursor < after || operations is! List) {
      throw const SyncSchemaFailure(
          'Pull response violated the sync contract.');
    }
    try {
      return SyncPullResult(
        nextCursor: nextCursor,
        operations: operations
            .map(
              (operation) => SyncOperationV2.fromJson(
                _object(operation, 'pulled operation').cast<String, dynamic>(),
              ),
            )
            .toList(growable: false),
      );
    } on SyncApiFailure {
      rethrow;
    } on Object catch (error) {
      throw SyncSchemaFailure(
        'Pulled operation violated the sync contract: $error',
        cause: error,
      );
    }
  }

  Future<Object?> _send(
    AuthContext authContext,
    Uri uri, {
    String? body,
  }) async {
    try {
      final response = body == null
          ? await _client.get(uri, headers: _headers(authContext))
          : await _client.post(uri, headers: _headers(authContext), body: body);
      if (response.statusCode == 401 || response.statusCode == 403) {
        throw const SyncAuthenticationFailure(
          'Synchronization credentials were rejected.',
        );
      }
      if (response.statusCode == 409) {
        throw const SyncConflictFailure(
          'Synchronization operation conflicts with server state.',
        );
      }
      if (response.statusCode == 422) {
        throw SyncSchemaFailure(_schemaFailureMessage(response));
      }
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw SyncNetworkFailure(
          'Synchronization server returned HTTP ${response.statusCode}.',
        );
      }
      try {
        return jsonDecode(response.body);
      } on FormatException catch (error) {
        throw SyncSchemaFailure(
          'Synchronization response was not valid JSON.',
          cause: error,
        );
      }
    } on SyncApiFailure {
      rethrow;
    } on SocketException catch (error) {
      throw SyncOfflineFailure('Network is offline.', cause: error);
    } on http.ClientException catch (error) {
      throw SyncNetworkFailure('Synchronization request failed.', cause: error);
    } on TimeoutException catch (error) {
      throw SyncNetworkFailure('Synchronization request timed out.',
          cause: error);
    }
  }

  Map<String, String> _headers(AuthContext authContext) => <String, String>{
        'Accept': 'application/json',
        'Content-Type': 'application/json',
        'Authorization': 'Bearer ${authContext.accessToken}',
      };

  void close() => _client.close();
}

String _schemaFailureMessage(http.Response response) {
  const fallback = 'Synchronization request violated the server contract.';
  try {
    final decoded = jsonDecode(response.body);
    if (decoded is! Map) {
      return '$fallback (HTTP ${response.statusCode}).';
    }
    final formatted = _formatServerDetail(decoded['detail']);
    if (formatted.isEmpty) {
      return '$fallback (HTTP ${response.statusCode}).';
    }
    return 'HTTP ${response.statusCode}: $formatted';
  } on Object {
    return '$fallback (HTTP ${response.statusCode}).';
  }
}

String _formatServerDetail(Object? detail) {
  if (detail is String) {
    return detail.trim();
  }
  if (detail is! List) {
    return '';
  }
  final messages = <String>[];
  for (final item in detail) {
    if (item is! Map) {
      continue;
    }
    final message = item['msg'];
    if (message is! String || message.trim().isEmpty) {
      continue;
    }
    final location = item['loc'];
    final field = location is List && location.isNotEmpty
        ? location.last.toString()
        : '';
    messages.add(field.isEmpty ? message.trim() : '$field: ${message.trim()}');
    if (messages.length == 3) {
      break;
    }
  }
  return messages.join('; ');
}

final class SyncPushResult {
  SyncPushResult({
    required Iterable<String> accepted,
    required Iterable<String> duplicates,
    required Iterable<String> rejected,
  })  : accepted = List<String>.unmodifiable(accepted),
        duplicates = List<String>.unmodifiable(duplicates),
        rejected = List<String>.unmodifiable(rejected) {
    for (final operationId in <String>[
      ...this.accepted,
      ...this.duplicates,
      ...this.rejected,
    ]) {
      if (!_canonicalUuidPattern.hasMatch(operationId)) {
        throw const SyncProtocolFailure(
          'Synchronization acknowledgement contains a non-canonical '
          'operation ID.',
        );
      }
    }
  }

  final List<String> accepted;
  final List<String> duplicates;
  final List<String> rejected;
}

final class SyncPullResult {
  SyncPullResult({
    required this.nextCursor,
    required Iterable<SyncOperationV2> operations,
  }) : operations = List<SyncOperationV2>.unmodifiable(operations) {
    if (nextCursor < 0) {
      throw ArgumentError.value(
          nextCursor, 'nextCursor', 'must be nonnegative');
    }
  }

  final int nextCursor;
  final List<SyncOperationV2> operations;
}

sealed class SyncApiFailure implements Exception {
  const SyncApiFailure(this.message, {this.cause});

  final String message;
  final Object? cause;
}

final class SyncOfflineFailure extends SyncApiFailure {
  const SyncOfflineFailure(super.message, {super.cause});
}

final class SyncNetworkFailure extends SyncApiFailure {
  const SyncNetworkFailure(super.message, {super.cause});
}

final class SyncAuthenticationFailure extends SyncApiFailure {
  const SyncAuthenticationFailure(super.message, {super.cause});
}

final class SyncSchemaFailure extends SyncApiFailure {
  const SyncSchemaFailure(super.message, {super.cause});
}

class SyncProtocolFailure extends SyncApiFailure {
  const SyncProtocolFailure(super.message, {super.cause});
}

final class SyncConflictFailure extends SyncProtocolFailure {
  const SyncConflictFailure(super.message, {super.cause});
}

final RegExp _canonicalUuidPattern = RegExp(
  r'^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$',
);

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
    throw SyncSchemaFailure('$label must be an object.');
  }
  final result = <String, Object?>{};
  for (final entry in value.entries) {
    if (entry.key is! String) {
      throw SyncSchemaFailure('$label contains a non-string key.');
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
    throw SyncSchemaFailure('$label contains unexpected fields.');
  }
}

List<String> _stringList(Object? value, String label) {
  if (value is! List || value.any((item) => item is! String)) {
    throw SyncSchemaFailure('$label must be a string list.');
  }
  return value.cast<String>();
}
