import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:studyflow/auth/auth_screen.dart';
import 'package:studyflow/auth/auth_repository.dart';

void main() {
  testWidgets('initial state shows sign in and create account only',
      (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: AuthScreen(
          onLogin: (_, __) async {},
          onRegister: (_, __) async {},
        ),
      ),
    );

    expect(find.byKey(const Key('auth-screen')), findsOneWidget);
    expect(find.text('Sign in'), findsWidgets);
    expect(find.text('Create account'), findsWidgets);
    expect(find.text('Initialize'), findsNothing);
    expect(find.text('Pair'), findsNothing);
    expect(find.text('Recovery key'), findsNothing);
    expect(find.byKey(const Key('bootstrap-token-field')), findsNothing);
    expect(find.byKey(const Key('pairing-code-field')), findsNothing);
    expect(find.byKey(const Key('recovery-key-field')), findsNothing);
  });

  testWidgets('login mode shows email and password fields', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: AuthScreen(
          onLogin: (_, __) async {},
          onRegister: (_, __) async {},
        ),
      ),
    );

    expect(find.byKey(const Key('auth-email-field')), findsOneWidget);
    expect(find.byKey(const Key('auth-password-field')), findsOneWidget);
    expect(find.byKey(const Key('auth-confirm-password-field')), findsNothing);
  });

  testWidgets('register mode shows email, password and confirmation',
      (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: AuthScreen(
          onLogin: (_, __) async {},
          onRegister: (_, __) async {},
        ),
      ),
    );

    await tester.tap(find.text('Create account'));
    await tester.pump();

    expect(find.byKey(const Key('auth-email-field')), findsOneWidget);
    expect(find.byKey(const Key('auth-password-field')), findsOneWidget);
    expect(find.byKey(const Key('auth-confirm-password-field')), findsOneWidget);
  });

  testWidgets('login submits email and password', (tester) async {
    String? submittedEmail;
    String? submittedPassword;
    await tester.pumpWidget(
      MaterialApp(
        home: AuthScreen(
          onLogin: (email, password) async {
            submittedEmail = email;
            submittedPassword = password;
          },
          onRegister: (_, __) async {},
        ),
      ),
    );

    await tester.enterText(
      find.byKey(const Key('auth-email-field')),
      'user@example.com',
    );
    await tester.enterText(
      find.byKey(const Key('auth-password-field')),
      'correcthorse',
    );
    await tester.tap(find.byKey(const Key('auth-submit-button')));
    await tester.pump();

    expect(submittedEmail, 'user@example.com');
    expect(submittedPassword, 'correcthorse');
  });

  testWidgets('register submits email and password', (tester) async {
    String? submittedEmail;
    String? submittedPassword;
    await tester.pumpWidget(
      MaterialApp(
        home: AuthScreen(
          onLogin: (_, __) async {},
          onRegister: (email, password) async {
            submittedEmail = email;
            submittedPassword = password;
          },
        ),
      ),
    );

    await tester.tap(find.text('Create account'));
    await tester.pump();
    await tester.enterText(
      find.byKey(const Key('auth-email-field')),
      'new@example.com',
    );
    await tester.enterText(
      find.byKey(const Key('auth-password-field')),
      'Correct-Horse-1',
    );
    await tester.enterText(
      find.byKey(const Key('auth-confirm-password-field')),
      'Correct-Horse-1',
    );
    await tester.tap(find.byKey(const Key('auth-submit-button')));
    await tester.pump();

    expect(submittedEmail, 'new@example.com');
    expect(submittedPassword, 'Correct-Horse-1');
  });

  testWidgets('password mismatch blocks submission and shows inline error',
      (tester) async {
    var submitted = false;
    await tester.pumpWidget(
      MaterialApp(
        home: AuthScreen(
          onLogin: (_, __) async {},
          onRegister: (_, __) async {
            submitted = true;
          },
        ),
      ),
    );

    await tester.tap(find.text('Create account'));
    await tester.pump();
    await tester.enterText(
      find.byKey(const Key('auth-email-field')),
      'new@example.com',
    );
    await tester.enterText(
      find.byKey(const Key('auth-password-field')),
      'Correct-Horse-1',
    );
    await tester.enterText(
      find.byKey(const Key('auth-confirm-password-field')),
      'Different-Pass-2',
    );
    await tester.tap(find.byKey(const Key('auth-submit-button')));
    await tester.pump();

    expect(submitted, isFalse);
    expect(find.text('Passwords do not match'), findsOneWidget);
  });

  testWidgets('short password shows inline validation error in register mode',
      (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: AuthScreen(
          onLogin: (_, __) async {},
          onRegister: (_, __) async {},
        ),
      ),
    );

    await tester.tap(find.text('Create account'));
    await tester.pump();
    await tester.enterText(
      find.byKey(const Key('auth-email-field')),
      'user@example.com',
    );
    await tester.enterText(
      find.byKey(const Key('auth-password-field')),
      'short',
    );
    await tester.tap(find.byKey(const Key('auth-submit-button')));
    await tester.pump();

    expect(
      find.text('Password must be at least 8 characters'),
      findsOneWidget,
    );
  });

  testWidgets('login mode accepts legacy passwords without composition rules',
      (tester) async {
    String? submittedPassword;
    await tester.pumpWidget(
      MaterialApp(
        home: AuthScreen(
          onLogin: (_, password) async {
            submittedPassword = password;
          },
          onRegister: (_, __) async {},
        ),
      ),
    );

    await tester.enterText(
      find.byKey(const Key('auth-email-field')),
      'user@example.com',
    );
    await tester.enterText(
      find.byKey(const Key('auth-password-field')),
      'correcthorse',
    );
    await tester.tap(find.byKey(const Key('auth-submit-button')));
    await tester.pump();

    expect(submittedPassword, 'correcthorse');
  });

  testWidgets('api failure shows friendly Chinese error', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: AuthScreen(
          onLogin: (_, __) async {
            throw const AuthApiException(401, null, 'Unauthorized.');
          },
          onRegister: (_, __) async {},
        ),
      ),
    );

    await tester.enterText(
      find.byKey(const Key('auth-email-field')),
      'user@example.com',
    );
    await tester.enterText(
      find.byKey(const Key('auth-password-field')),
      'correcthorse',
    );
    await tester.tap(find.byKey(const Key('auth-submit-button')));
    await tester.pump();
    await tester.pump();

    expect(find.text('邮箱或密码错误'), findsOneWidget);
  });

  testWidgets('server detail message takes precedence', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: AuthScreen(
          onLogin: (_, __) async {
            throw const AuthApiException(409, '该邮箱已被注册', 'Conflict.');
          },
          onRegister: (_, __) async {},
        ),
      ),
    );

    await tester.enterText(
      find.byKey(const Key('auth-email-field')),
      'user@example.com',
    );
    await tester.enterText(
      find.byKey(const Key('auth-password-field')),
      'correcthorse',
    );
    await tester.tap(find.byKey(const Key('auth-submit-button')));
    await tester.pump();
    await tester.pump();

    expect(find.text('该邮箱已被注册'), findsOneWidget);
  });

  testWidgets('initial message is displayed when provided', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: AuthScreen(
          onLogin: (_, __) async {},
          onRegister: (_, __) async {},
          initialMessage: '登录已过期，请重新登录',
        ),
      ),
    );

    expect(find.text('登录已过期，请重新登录'), findsOneWidget);
  });
}
