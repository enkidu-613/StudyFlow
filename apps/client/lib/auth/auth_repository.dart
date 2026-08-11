import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;

final class AuthContext {
  AuthContext({
    required String accountId,
    required String deviceId,
    required this.accessToken,
    required this.refreshToken,
    required this.encryptedAccountDataKeyEnvelope,
  })  : accountId = _normalizedUuid(accountId, 'accountId'),
        deviceId = _normalizedUuid(deviceId, 'deviceId') {
    _requireSecret(accessToken, 'accessToken');
    _requireSecret(refreshToken, 'refreshToken');
    _requireCanonicalBase64(
      encryptedAccountDataKeyEnvelope,
      'encryptedAccountDataKeyEnvelope',
    );
  }

  final String accountId;
  final String deviceId;
  final String accessToken;
  final String refreshToken;
  final String encryptedAccountDataKeyEnvelope;

  factory AuthContext.fromJson(Object? value) {
    final json = _jsonObject(value, 'active auth context');
    const expectedKeys = <String>{
      'account_id',
      'device_id',
      'access_token',
      'refresh_token',
      'encrypted_account_data_key_envelope',
    };
    if (json.keys.toSet().difference(expectedKeys).isNotEmpty ||
        expectedKeys.difference(json.keys.toSet()).isNotEmpty) {
      throw const FormatException('Active auth context has unexpected fields.');
    }
    return AuthContext._fromMap(json);
  }

  factory AuthContext.fromApiJson(Object? value) =>
      AuthContext._fromMap(_jsonObject(value, 'authentication response'));

  factory AuthContext._fromMap(Map<String, Object?> json) => AuthContext(
        accountId: _requiredString(json, 'account_id'),
        deviceId: _requiredString(json, 'device_id'),
        accessToken: _requiredString(json, 'access_token'),
        refreshToken: _requiredString(json, 'refresh_token'),
        encryptedAccountDataKeyEnvelope:
            _requiredString(json, 'encrypted_account_data_key_envelope'),
      );

  Map<String, Object?> toJson() => <String, Object?>{
        'account_id': accountId,
        'device_id': deviceId,
        'access_token': accessToken,
        'refresh_token': refreshToken,
        'encrypted_account_data_key_envelope': encryptedAccountDataKeyEnvelope,
      };

  @override
  bool operator ==(Object other) =>
      other is AuthContext &&
      other.accountId == accountId &&
      other.deviceId == deviceId &&
      other.accessToken == accessToken &&
      other.refreshToken == refreshToken &&
      other.encryptedAccountDataKeyEnvelope == encryptedAccountDataKeyEnvelope;

  @override
  int get hashCode => Object.hash(
        accountId,
        deviceId,
        accessToken,
        refreshToken,
        encryptedAccountDataKeyEnvelope,
      );
}

final class PairingCodeResult {
  PairingCodeResult({required this.code, required this.expiresAt}) {
    if (!_pairingCodePattern.hasMatch(code)) {
      throw ArgumentError.value(code, 'code', 'must contain six digits');
    }
  }

  final String code;
  final DateTime expiresAt;
}

abstract interface class AuthContextStore {
  Future<AuthContext?> read();

  Future<void> write(AuthContext context);

  Future<void> delete();
}

final class FlutterSecureAuthContextStore implements AuthContextStore {
  FlutterSecureAuthContextStore({FlutterSecureStorage? storage})
      : _storage = storage ??
            const FlutterSecureStorage(
              aOptions: AndroidOptions(
                resetOnError: false,
                storageNamespace: 'studyflow.auth.v1',
              ),
              mOptions: MacOsOptions(
                accessibility: KeychainAccessibility.unlocked_this_device,
                synchronizable: false,
                usesDataProtectionKeychain: true,
              ),
            );

  static const _activeContextKey = 'studyflow.auth.active-context.v1';
  final FlutterSecureStorage _storage;

  @override
  Future<AuthContext?> read() async {
    final serialized = await _storage.read(key: _activeContextKey);
    if (serialized == null) {
      return null;
    }
    try {
      return AuthContext.fromJson(jsonDecode(serialized));
    } on FormatException catch (error) {
      throw AuthStorageException(
        'Stored authentication state is invalid. Sign in again after clearing it.',
        cause: error,
      );
    }
  }

  @override
  Future<void> write(AuthContext context) => _storage.write(
        key: _activeContextKey,
        value: jsonEncode(context.toJson()),
      );

  @override
  Future<void> delete() => _storage.delete(key: _activeContextKey);
}

abstract interface class AuthApi {
  Future<AuthContext> login({
    required String password,
    required String deviceId,
  });

  Future<AuthContext> refresh({required String refreshToken});

  Future<PairingCodeResult> createPairingCode({
    required String accessToken,
    required String targetDeviceId,
    required String targetDevicePublicKey,
    required String encryptedAccountDataKeyEnvelope,
  });

  Future<AuthContext> pair({
    required String code,
    required String deviceId,
    required String devicePublicKey,
  });

  Future<void> revokeDevice({
    required String accessToken,
    required String deviceId,
  });
}

final class HttpAuthApi implements AuthApi {
  HttpAuthApi({required Uri baseUri, http.Client? client})
      : _baseUri = _validatedBaseUri(baseUri),
        _client = client ?? http.Client();

  final Uri _baseUri;
  final http.Client _client;

  @override
  Future<AuthContext> login({
    required String password,
    required String deviceId,
  }) async =>
      AuthContext.fromApiJson(
        await _post(
          '/v1/auth/login',
          <String, Object?>{
            'password': password,
            'device_id': _normalizedUuid(deviceId, 'deviceId'),
          },
        ),
      );

  @override
  Future<AuthContext> refresh({required String refreshToken}) async =>
      AuthContext.fromApiJson(
        await _post(
          '/v1/auth/refresh',
          <String, Object?>{'refresh_token': refreshToken},
        ),
      );

  @override
  Future<PairingCodeResult> createPairingCode({
    required String accessToken,
    required String targetDeviceId,
    required String targetDevicePublicKey,
    required String encryptedAccountDataKeyEnvelope,
  }) async {
    final body = _jsonObject(
      await _post(
        '/v1/devices/pairing-codes',
        <String, Object?>{
          'target_device_id': _normalizedUuid(targetDeviceId, 'targetDeviceId'),
          'target_device_public_key': targetDevicePublicKey,
          'encrypted_account_data_key_envelope':
              encryptedAccountDataKeyEnvelope,
        },
        accessToken: accessToken,
        acceptedStatusCodes: const <int>{201},
      ),
      'pairing code response',
    );
    return PairingCodeResult(
      code: _requiredString(body, 'code'),
      expiresAt: DateTime.parse(_requiredString(body, 'expires_at')).toUtc(),
    );
  }

  @override
  Future<AuthContext> pair({
    required String code,
    required String deviceId,
    required String devicePublicKey,
  }) async =>
      AuthContext.fromApiJson(
        await _post(
          '/v1/devices/pair',
          <String, Object?>{
            'code': code,
            'device_id': _normalizedUuid(deviceId, 'deviceId'),
            'device_public_key': devicePublicKey,
          },
        ),
      );

  @override
  Future<void> revokeDevice({
    required String accessToken,
    required String deviceId,
  }) async {
    await _post(
      '/v1/devices/revoke',
      <String, Object?>{'device_id': _normalizedUuid(deviceId, 'deviceId')},
      accessToken: accessToken,
      acceptedStatusCodes: const <int>{204},
    );
  }

  void close() => _client.close();

  Future<Object?> _post(
    String path,
    Map<String, Object?> body, {
    String? accessToken,
    Set<int> acceptedStatusCodes = const <int>{200},
  }) async {
    final response = await _client.post(
      _baseUri.resolve(path),
      headers: <String, String>{
        'Content-Type': 'application/json',
        if (accessToken != null) 'Authorization': 'Bearer $accessToken',
      },
      body: jsonEncode(body),
    );
    if (!acceptedStatusCodes.contains(response.statusCode)) {
      throw AuthApiException(
        response.statusCode,
        'Authentication request failed.',
      );
    }
    if (response.body.isEmpty) {
      return null;
    }
    try {
      return jsonDecode(response.body);
    } on FormatException catch (error) {
      throw AuthApiException(
        response.statusCode,
        'Authentication response was invalid.',
        cause: error,
      );
    }
  }
}

final class AuthRepository {
  AuthRepository({required AuthApi api, required AuthContextStore store})
      : _api = api,
        _store = store;

  final AuthApi _api;
  final AuthContextStore _store;
  AuthContext? _activeContext;

  AuthContext? get activeContext => _activeContext;

  Future<AuthContext?> restoreActiveContext() async {
    _activeContext = await _store.read();
    return _activeContext;
  }

  Future<AuthContext> login({
    required String password,
    required String deviceId,
  }) async {
    final normalizedDeviceId = _normalizedUuid(deviceId, 'deviceId');
    final authenticated = await _api.login(
      password: password,
      deviceId: normalizedDeviceId,
    );
    if (authenticated.deviceId != normalizedDeviceId) {
      throw const AuthScopeException(
        'Login response was bound to a different device.',
      );
    }
    return _persist(authenticated);
  }

  Future<AuthContext> pair({
    required String code,
    required String deviceId,
    required String devicePublicKey,
  }) async {
    if (!_pairingCodePattern.hasMatch(code)) {
      throw ArgumentError.value(code, 'code', 'must contain six digits');
    }
    final normalizedDeviceId = _normalizedUuid(deviceId, 'deviceId');
    final authenticated = await _api.pair(
      code: code,
      deviceId: normalizedDeviceId,
      devicePublicKey: devicePublicKey,
    );
    if (authenticated.deviceId != normalizedDeviceId) {
      throw const AuthScopeException(
        'Pairing response was bound to a different device.',
      );
    }
    return _persist(authenticated);
  }

  Future<AuthContext> refresh() async {
    final current = _requireActiveContext();
    late final AuthContext refreshed;
    try {
      refreshed = await _api.refresh(refreshToken: current.refreshToken);
    } on AuthApiException catch (error) {
      if (error.statusCode == 401) {
        await _clearActiveContext();
      }
      rethrow;
    }
    if (refreshed.accountId != current.accountId ||
        refreshed.deviceId != current.deviceId) {
      await logout();
      throw const AuthScopeException(
        'Refreshed credentials changed the active account or device.',
      );
    }
    return _persist(refreshed);
  }

  Future<PairingCodeResult> createPairingCode({
    required String targetDeviceId,
    required String targetDevicePublicKey,
    required String encryptedAccountDataKeyEnvelope,
  }) {
    final current = _requireActiveContext();
    return _api.createPairingCode(
      accessToken: current.accessToken,
      targetDeviceId: targetDeviceId,
      targetDevicePublicKey: targetDevicePublicKey,
      encryptedAccountDataKeyEnvelope: encryptedAccountDataKeyEnvelope,
    );
  }

  Future<void> revokeDevice(String deviceId) async {
    final current = _requireActiveContext();
    final normalizedDeviceId = _normalizedUuid(deviceId, 'deviceId');
    try {
      await _api.revokeDevice(
        accessToken: current.accessToken,
        deviceId: normalizedDeviceId,
      );
    } on AuthApiException catch (error) {
      if (error.statusCode == 401) {
        await _clearActiveContext();
      }
      rethrow;
    }
    if (normalizedDeviceId == current.deviceId) {
      await logout();
    }
  }

  Future<void> logout() => _clearActiveContext();

  Future<void> _clearActiveContext() async {
    _activeContext = null;
    await _store.delete();
  }

  Future<AuthContext> _persist(AuthContext context) async {
    await _store.write(context);
    _activeContext = context;
    return context;
  }

  AuthContext _requireActiveContext() {
    final current = _activeContext;
    if (current == null) {
      throw const AuthScopeException('No account is currently active.');
    }
    return current;
  }
}

class AuthScopeException implements Exception {
  const AuthScopeException(this.message);

  final String message;
}

class AuthStorageException implements Exception {
  const AuthStorageException(this.message, {this.cause});

  final String message;
  final Object? cause;
}

class AuthApiException implements Exception {
  const AuthApiException(this.statusCode, this.message, {this.cause});

  final int statusCode;
  final String message;
  final Object? cause;
}

Uri _validatedBaseUri(Uri uri) {
  final isLoopback =
      uri.host == 'localhost' || uri.host == '127.0.0.1' || uri.host == '::1';
  final hasSecureTransport =
      uri.scheme == 'https' || (uri.scheme == 'http' && isLoopback);
  if (!hasSecureTransport ||
      uri.host.isEmpty ||
      uri.hasQuery ||
      uri.hasFragment ||
      uri.userInfo.isNotEmpty) {
    throw ArgumentError.value(uri, 'baseUri', 'must be an HTTP(S) origin');
  }
  return uri;
}

Map<String, Object?> _jsonObject(Object? value, String label) {
  if (value is! Map) {
    throw FormatException('$label must be a JSON object.');
  }
  final result = <String, Object?>{};
  for (final entry in value.entries) {
    if (entry.key is! String) {
      throw FormatException('$label contains a non-string key.');
    }
    result[entry.key as String] = entry.value;
  }
  return result;
}

String _requiredString(Map<String, Object?> json, String key) {
  final value = json[key];
  if (value is! String) {
    throw FormatException('$key must be a string.');
  }
  return value;
}

String _normalizedUuid(String value, String name) {
  final normalized = value.toLowerCase();
  if (!_uuidPattern.hasMatch(normalized)) {
    throw ArgumentError.value(value, name, 'must be a UUID');
  }
  return normalized;
}

void _requireSecret(String value, String name) {
  if (value.isEmpty || value.length > 4096 || value.contains('\x00')) {
    throw ArgumentError.value(
        value.isEmpty ? value : '<redacted>', name, 'is invalid');
  }
}

void _requireCanonicalBase64(String value, String name) {
  try {
    final decoded = base64Decode(value);
    if (decoded.isEmpty || base64Encode(decoded) != value) {
      throw const FormatException('non-canonical base64');
    }
  } on FormatException {
    throw ArgumentError.value('<redacted>', name, 'must be canonical base64');
  }
}

final RegExp _uuidPattern = RegExp(
  r'^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$',
);
final RegExp _pairingCodePattern = RegExp(r'^[0-9]{6}$');
