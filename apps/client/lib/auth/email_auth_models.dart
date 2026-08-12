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

/// Maps an HTTP status code to a stable error key. UI layers translate the
/// key through the localized strings; this keeps the model layer free of
/// Flutter dependencies.
String authErrorKey(int statusCode) => switch (statusCode) {
      401 => 'authErrorInvalidCredentials',
      409 => 'authErrorEmailTaken',
      422 => 'authErrorInvalidInput',
      429 => 'authErrorTooManyAttempts',
      503 => 'authErrorUnavailable',
      _ => 'authErrorGeneric',
    };

const int passwordMinLength = 8;
const int passwordMaxLength = 16;

final RegExp _emailPattern = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$');
final RegExp _uppercasePattern = RegExp(r'[A-Z]');
final RegExp _lowercasePattern = RegExp(r'[a-z]');
final RegExp _digitPattern = RegExp(r'[0-9]');
final RegExp _specialPattern = RegExp(r'[!@#$%^&*()_+\-=\[\]{};:' r'"' r',.<>/?\\|`~]');

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

String? validateLoginPasswordField(String? value) {
  if (value == null || value.isEmpty) {
    return 'Password is required';
  }
  if (value.length > passwordMaxLength) {
    return 'Password is too long';
  }
  return null;
}

String? validateRegisterPasswordField(String? value, {String? email}) {
  if (value == null || value.isEmpty) {
    return 'Password is required';
  }
  if (value.length < passwordMinLength) {
    return 'Password must be at least $passwordMinLength characters';
  }
  if (value.length > passwordMaxLength) {
    return 'Password must be at most $passwordMaxLength characters';
  }
  if (value.contains(' ')) {
    return 'Password must not contain spaces';
  }
  if (RegExp(r'^\d+$').hasMatch(value)) {
    return 'Password must not be all digits';
  }
  if (email != null) {
    final normalizedEmail = email.trim().toLowerCase();
    final localPart = normalizedEmail.split('@').first;
    if (value.toLowerCase() == normalizedEmail ||
        value.toLowerCase() == localPart) {
      return 'Password must not match the account email';
    }
  }
  final missing = <String>[
    if (!_uppercasePattern.hasMatch(value)) 'an uppercase letter',
    if (!_lowercasePattern.hasMatch(value)) 'a lowercase letter',
    if (!_digitPattern.hasMatch(value)) 'a digit',
    if (!_specialPattern.hasMatch(value)) 'a special character',
  ];
  if (missing.isNotEmpty) {
    return 'Password must contain ${missing.join(', ')}';
  }
  return null;
}
