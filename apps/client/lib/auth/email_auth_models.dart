final class AuthSession {
  const AuthSession({
    required this.userId,
    required this.email,
    required this.accessToken,
    required this.refreshToken,
    required this.expiresIn,
  });

  final String userId;
  final String email;
  final String accessToken;
  final String refreshToken;
  final int expiresIn;

  factory AuthSession.fromJson(Map<String, Object?> json) {
    final userId = _requiredString(json, 'user_id');
    final email = _requiredString(json, 'email');
    final accessToken = _requiredString(json, 'access_token');
    final refreshToken = _requiredString(json, 'refresh_token');
    final expiresIn = json['expires_in'];
    if (expiresIn is! int || expiresIn <= 0) {
      throw const FormatException('expires_in must be a positive integer.');
    }
    return AuthSession(
      userId: userId,
      email: email,
      accessToken: accessToken,
      refreshToken: refreshToken,
      expiresIn: expiresIn,
    );
  }

  Map<String, Object?> toJson() => <String, Object?>{
        'user_id': userId,
        'email': email,
        'access_token': accessToken,
        'refresh_token': refreshToken,
        'expires_in': expiresIn,
      };

  static String _requiredString(Map<String, Object?> json, String key) {
    final value = json[key];
    if (value is! String || value.isEmpty) {
      throw FormatException('$key must be a non-empty string.');
    }
    return value;
  }
}

final class AuthErrorDetail {
  const AuthErrorDetail({required this.statusCode, required this.message});

  final int statusCode;
  final String message;
}

String friendlyAuthError(int statusCode, {String? serverDetail}) {
  if (serverDetail != null && serverDetail.isNotEmpty) {
    return serverDetail;
  }
  return switch (statusCode) {
    401 => '邮箱或密码错误',
    409 => '该邮箱已被注册',
    422 => '邮箱或密码格式不正确',
    503 => '服务暂时不可用，请稍后重试',
    _ => '操作失败，请稍后重试',
  };
}

const int passwordMinLength = 12;
const int passwordMaxLength = 256;

final RegExp _emailPattern = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$');

String? validateEmailField(String? value) {
  final trimmed = value?.trim() ?? '';
  if (trimmed.isEmpty) {
    return 'Email is required';
  }
  if (!_emailPattern.hasMatch(trimmed)) {
    return 'Enter a valid email address';
  }
  return null;
}

String? validatePasswordField(String? value) {
  if (value == null || value.isEmpty) {
    return 'Password is required';
  }
  if (value.length < passwordMinLength) {
    return 'Password must be at least $passwordMinLength characters';
  }
  if (value.length > passwordMaxLength) {
    return 'Password is too long';
  }
  return null;
}
