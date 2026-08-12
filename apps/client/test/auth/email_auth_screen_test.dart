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

  group('validateRegisterPasswordField', () {
    test('accepts a password with all required categories', () {
      expect(validateRegisterPasswordField('Correct-Horse-1'), isNull);
    });

    test('accepts a password at exactly 8 characters with all categories', () {
      expect(validateRegisterPasswordField('Ab1!cdef'), isNull);
    });

    test('accepts a password at exactly 16 characters with all categories', () {
      expect(validateRegisterPasswordField('Ab1!cdefghijklmn'), isNull);
    });

    test('rejects empty value', () {
      expect(validateRegisterPasswordField(null), 'Password is required');
      expect(validateRegisterPasswordField(''), 'Password is required');
    });

    test('rejects a short password', () {
      expect(
        validateRegisterPasswordField('short'),
        'Password must be at least 8 characters',
      );
    });

    test('rejects a password longer than 16 characters', () {
      expect(
        validateRegisterPasswordField('Correct-Horse-Battery-1'),
        'Password must be at most 16 characters',
      );
    });

    test('rejects a password missing an uppercase letter', () {
      expect(
        validateRegisterPasswordField('correct-horse-1'),
        'Password must contain an uppercase letter',
      );
    });

    test('rejects a password missing a lowercase letter', () {
      expect(
        validateRegisterPasswordField('CORRECT-HORSE-1'),
        'Password must contain a lowercase letter',
      );
    });

    test('rejects a password missing a digit', () {
      expect(
        validateRegisterPasswordField('Correct-Horse-B'),
        'Password must contain a digit',
      );
    });

    test('rejects a password missing a special character', () {
      expect(
        validateRegisterPasswordField('CorrectHorse1'),
        'Password must contain a special character',
      );
    });

    test('allows unicode alongside required categories', () {
      expect(validateRegisterPasswordField('Café-Macaroon-1'), isNull);
    });

    test('rejects a password containing spaces', () {
      expect(
        validateRegisterPasswordField('Correct Horse 1!'),
        'Password must not contain spaces',
      );
    });

    test('rejects an all-digit password', () {
      expect(
        validateRegisterPasswordField('12345678'),
        'Password must not be all digits',
      );
    });

    test('rejects a password matching the email', () {
      expect(
        validateRegisterPasswordField(
          'User@Example.Com',
          email: 'user@example.com',
        ),
        'Password must not match the account email',
      );
    });

    test('rejects a password matching the email local part', () {
      expect(
        validateRegisterPasswordField(
          'username-1!',
          email: 'username-1!@example.com',
        ),
        'Password must not match the account email',
      );
    });

    test('accepts a password different from the email', () {
      expect(
        validateRegisterPasswordField(
          'Correct-Horse-1',
          email: 'user@example.com',
        ),
        isNull,
      );
    });
  });

  group('validateLoginPasswordField', () {
    test('accepts a legacy password without composition rules', () {
      expect(validateLoginPasswordField('correcthorse'), isNull);
    });

    test('rejects empty value', () {
      expect(validateLoginPasswordField(null), 'Password is required');
      expect(validateLoginPasswordField(''), 'Password is required');
    });
  });
}
