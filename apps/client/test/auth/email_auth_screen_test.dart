import 'package:flutter_test/flutter_test.dart';
import 'package:studyflow/auth/email_auth_models.dart';

void main() {
  group('AuthSession', () {
    test('parses a full authentication response', () {
      final session = AuthSession.fromJson(<String, Object?>{
        'user_id': '11111111-1111-4111-8111-111111111111',
        'email': 'user@example.com',
        'access_token': 'access-token-value',
        'refresh_token': 'refresh-token-value',
        'expires_in': 900,
      });

      expect(session.userId, '11111111-1111-4111-8111-111111111111');
      expect(session.email, 'user@example.com');
      expect(session.accessToken, 'access-token-value');
      expect(session.refreshToken, 'refresh-token-value');
      expect(session.expiresIn, 900);
    });

    test('round-trips through JSON', () {
      const session = AuthSession(
        userId: '11111111-1111-4111-8111-111111111111',
        email: 'user@example.com',
        accessToken: 'a',
        refreshToken: 'r',
        expiresIn: 900,
      );

      final restored = AuthSession.fromJson(session.toJson());

      expect(restored.userId, session.userId);
      expect(restored.email, session.email);
      expect(restored.accessToken, session.accessToken);
      expect(restored.refreshToken, session.refreshToken);
      expect(restored.expiresIn, session.expiresIn);
    });

    test('rejects a missing required field', () {
      expect(
        () => AuthSession.fromJson(<String, Object?>{
          'user_id': '11111111-1111-4111-8111-111111111111',
          'email': 'user@example.com',
          'access_token': 'a',
          'refresh_token': 'r',
        }),
        throwsFormatException,
      );
    });

    test('rejects non-positive expires_in', () {
      expect(
        () => AuthSession.fromJson(<String, Object?>{
          'user_id': '11111111-1111-4111-8111-111111111111',
          'email': 'user@example.com',
          'access_token': 'a',
          'refresh_token': 'r',
          'expires_in': 0,
        }),
        throwsFormatException,
      );
    });
  });

  group('friendlyAuthError', () {
    test('maps common status codes to readable Chinese messages', () {
      expect(friendlyAuthError(401), '邮箱或密码错误');
      expect(friendlyAuthError(409), '该邮箱已被注册');
      expect(friendlyAuthError(422), '邮箱或密码格式不正确');
    });

    test('server detail takes precedence over the mapping', () {
      expect(friendlyAuthError(409, serverDetail: 'custom detail'), 'custom detail');
    });

    test('unknown status falls back to a generic message', () {
      expect(friendlyAuthError(500), '操作失败，请稍后重试');
    });
  });

  group('validateEmailField', () {
    test('accepts a normal email address', () {
      expect(validateEmailField('user@example.com'), isNull);
    });

    test('accepts leading and trailing whitespace after trimming', () {
      expect(validateEmailField('  user@example.com  '), isNull);
    });

    test('rejects empty value', () {
      expect(validateEmailField(null), 'Email is required');
      expect(validateEmailField(''), 'Email is required');
    });

    test('rejects a malformed address', () {
      expect(validateEmailField('not-an-email'), 'Enter a valid email address');
    });
  });

  group('validatePasswordField', () {
    test('accepts a password at least 12 characters long', () {
      expect(validatePasswordField('correct horse battery'), isNull);
    });

    test('rejects empty value', () {
      expect(validatePasswordField(null), 'Password is required');
      expect(validatePasswordField(''), 'Password is required');
    });

    test('rejects a short password', () {
      expect(
        validatePasswordField('short'),
        'Password must be at least 12 characters',
      );
    });
  });
}
