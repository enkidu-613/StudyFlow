import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:studyflow/auth/auth_screen.dart';

void main() {
  testWidgets('login mode submits password without exposing other modes',
      (tester) async {
    String? password;
    await tester.pumpWidget(
      MaterialApp(
        home: AuthScreen(
          onLogin: (value) async => password = value,
          onBootstrap: (_, __) async {},
          onPair: (_) async {},
        ),
      ),
    );

    expect(find.byKey(const Key('auth-submit-button')), findsOneWidget);
    expect(find.byKey(const Key('auth-password-field')), findsOneWidget);
    expect(find.byKey(const Key('bootstrap-token-field')), findsNothing);

    await tester.enterText(
      find.byKey(const Key('auth-password-field')),
      'correct horse battery staple',
    );
    await tester.tap(find.byKey(const Key('auth-submit-button')));
    await tester.pump();

    expect(password, 'correct horse battery staple');
  });

  testWidgets('bootstrap mode contains a temporary token field',
      (tester) async {
    String? token;
    String? password;
    await tester.pumpWidget(
      MaterialApp(
        home: AuthScreen(
          onLogin: (_) async {},
          onBootstrap: (receivedToken, receivedPassword) async {
            token = receivedToken;
            password = receivedPassword;
          },
          onPair: (_) async {},
        ),
      ),
    );

    await tester.tap(find.text('Initialize'));
    await tester.pump();
    await tester.enterText(
      find.byKey(const Key('bootstrap-token-field')),
      'temporary-bootstrap-token',
    );
    await tester.enterText(
      find.byKey(const Key('auth-password-field')),
      'correct horse battery staple',
    );
    await tester.tap(find.byKey(const Key('auth-submit-button')));
    await tester.pump();

    expect(token, 'temporary-bootstrap-token');
    expect(password, 'correct horse battery staple');
  });

  testWidgets('recovery mode submits only the recovery key', (tester) async {
    String? recoveryKey;
    await tester.pumpWidget(
      MaterialApp(
        home: AuthScreen(
          onLogin: (_) async {},
          onBootstrap: (_, __) async {},
          onPair: (_) async {},
          recoveryAccountId: 'account-123',
          onRecovery: (value) async => recoveryKey = value,
        ),
      ),
    );

    await tester.tap(find.text('Recover'));
    await tester.pump();
    expect(find.byKey(const Key('recovery-key-field')), findsOneWidget);
    expect(find.byKey(const Key('auth-password-field')), findsNothing);

    await tester.enterText(
      find.byKey(const Key('recovery-key-field')),
      'recovery-secret',
    );
    await tester.tap(find.byKey(const Key('auth-submit-button')));
    await tester.pump();

    expect(recoveryKey, 'recovery-secret');
  });
}
