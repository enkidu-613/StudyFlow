import 'package:flutter/material.dart';

import '../l10n/l10n_extension.dart';
import 'auth_repository.dart';
import 'email_auth_models.dart';

enum AuthMode { login, register }

enum AuthInitialMessage {
  sessionExpired,
  restoreFailed,
  restoreFailedAndSignIn,
}

final class AuthScreen extends StatefulWidget {
  const AuthScreen({
    required this.onLogin,
    required this.onRegister,
    this.initialMessage,
    this.initialMessageKind,
    super.key,
  });

  final Future<void> Function(String email, String password) onLogin;
  final Future<void> Function(String email, String password) onRegister;
  final String? initialMessage;
  final AuthInitialMessage? initialMessageKind;

  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

final class _AuthScreenState extends State<AuthScreen> {
  AuthMode _mode = AuthMode.login;
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();
  String? _message;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _message = widget.initialMessage;
  }

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

  void _switchMode(AuthMode mode) {
    setState(() {
      _mode = mode;
      _message = null;
      _emailController.clear();
      _passwordController.clear();
      _confirmPasswordController.clear();
    });
  }

  Future<void> _submit() async {
    if (_busy) {
      return;
    }
    setState(() => _message = null);
    if (!(_formKey.currentState?.validate() ?? false)) {
      return;
    }
    final email = _emailController.text.trim();
    final password = _passwordController.text;
    setState(() {
      _busy = true;
      _message = null;
    });
    try {
      switch (_mode) {
        case AuthMode.login:
          await widget.onLogin(email, password);
        case AuthMode.register:
          await widget.onRegister(email, password);
      }
    } on Object catch (error) {
      if (mounted) {
        setState(() => _message = _friendlySubmissionError(error));
      }
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  String _friendlySubmissionError(Object error) {
    final l10n = context.l10n;
    if (error is AuthApiException) {
      final detail = error.serverDetail;
      if (detail != null && detail.isNotEmpty) {
        return detail;
      }
      return _localizedAuthError(error.statusCode);
    }
    if (error is AuthScopeException) {
      return l10n.authSessionExpired;
    }
    return l10n.authNetworkFailed;
  }

  String _localizedAuthError(int statusCode) {
    final l10n = context.l10n;
    return switch (authErrorKey(statusCode)) {
      'authErrorInvalidCredentials' => l10n.authErrorInvalidCredentials,
      'authErrorEmailTaken' => l10n.authErrorEmailTaken,
      'authErrorInvalidInput' => l10n.authErrorInvalidInput,
      'authErrorTooManyAttempts' => l10n.authErrorTooManyAttempts,
      'authErrorUnavailable' => l10n.authErrorUnavailable,
      _ => l10n.authErrorGeneric,
    };
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Scaffold(
      key: const Key('auth-screen'),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 460),
          child: ListView(
            padding: const EdgeInsets.all(24),
            shrinkWrap: true,
            children: <Widget>[
              Text(
                l10n.appTitle,
                style: Theme.of(context).textTheme.headlineMedium,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 24),
              SegmentedButton<AuthMode>(
                segments: <ButtonSegment<AuthMode>>[
                  ButtonSegment<AuthMode>(
                    value: AuthMode.login,
                    label: Text(l10n.authSignIn),
                    icon: const Icon(Icons.login),
                  ),
                  ButtonSegment<AuthMode>(
                    value: AuthMode.register,
                    label: Text(l10n.authCreateAccount),
                    icon: const Icon(Icons.person_add),
                  ),
                ],
                selected: <AuthMode>{_mode},
                onSelectionChanged: (selection) =>
                    _switchMode(selection.single),
              ),
              const SizedBox(height: 20),
              Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: <Widget>[
                    TextFormField(
                      key: const Key('auth-email-field'),
                      controller: _emailController,
                      enabled: !_busy,
                      keyboardType: TextInputType.emailAddress,
                      autofillHints: const <String>[AutofillHints.email],
                      decoration: InputDecoration(
                        labelText: l10n.authEmailLabel,
                        prefixIcon: const Icon(Icons.mail_outline),
                      ),
                      validator: (value) {
                        final message = validateEmailField(value);
                        return message == null
                            ? null
                            : switch (message) {
                                'Email is required' => l10n.authEmailRequired,
                                _ => l10n.authEmailInvalid,
                              };
                      },
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      key: const Key('auth-password-field'),
                      controller: _passwordController,
                      enabled: !_busy,
                      obscureText: true,
                      autofillHints: const <String>[AutofillHints.password],
                      decoration: InputDecoration(
                        labelText: l10n.authPasswordLabel,
                        prefixIcon: const Icon(Icons.lock_outline),
                      ),
                      validator: _mode == AuthMode.register
                          ? (value) => _localizedRegisterError(
                                validateRegisterPasswordField(
                                  value,
                                  email: _emailController.text,
                                ),
                              )
                          : (value) => _localizedLoginError(
                                validateLoginPasswordField(value),
                              ),
                    ),
                    if (_mode == AuthMode.register) ...<Widget>[
                      const SizedBox(height: 12),
                      TextFormField(
                        key: const Key('auth-confirm-password-field'),
                        controller: _confirmPasswordController,
                        enabled: !_busy,
                        obscureText: true,
                        decoration: InputDecoration(
                          labelText: l10n.authConfirmPasswordLabel,
                          prefixIcon: const Icon(Icons.lock_outline),
                        ),
                        validator: (value) {
                          if (value == null || value.isEmpty) {
                            return l10n.authConfirmRequired;
                          }
                          if (value != _passwordController.text) {
                            return l10n.authPasswordMismatch;
                          }
                          return null;
                        },
                      ),
                    ],
                    const SizedBox(height: 16),
                    FilledButton(
                      key: const Key('auth-submit-button'),
                      onPressed: _busy ? null : _submit,
                      child: _busy
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : Text(
                              _mode == AuthMode.login
                                  ? l10n.authSignIn
                                  : l10n.authCreateAccount,
                            ),
                    ),
                  ],
                ),
              ),
              if (_message != null) ...<Widget>[
                const SizedBox(height: 16),
                Text(
                  _message!,
                  key: const Key('auth-error-message'),
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.error,
                  ),
                ),
              ],
              if (_message == null && widget.initialMessageKind != null) ...<Widget>[
                const SizedBox(height: 16),
                Text(
                  _localizedInitialMessage(widget.initialMessageKind!),
                  key: const Key('auth-error-message'),
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.error,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  String _localizedInitialMessage(AuthInitialMessage kind) {
    final l10n = context.l10n;
    return switch (kind) {
      AuthInitialMessage.sessionExpired => l10n.authSessionExpired,
      AuthInitialMessage.restoreFailed => l10n.authNetworkFailed,
      AuthInitialMessage.restoreFailedAndSignIn => l10n.authNetworkFailed,
    };
  }

  String? _localizedLoginError(String? message) {
    final l10n = context.l10n;
    if (message == null) {
      return null;
    }
    return switch (message) {
      'Password is required' => l10n.authPasswordRequired,
      'Password is too long' => l10n.authPasswordMaxLength(
          passwordMaxLength,
        ),
      _ => message,
    };
  }

  String? _localizedRegisterError(String? message) {
    final l10n = context.l10n;
    if (message == null) {
      return null;
    }
    if (message.startsWith('Password must contain ')) {
      return l10n.authPasswordMissing(
        message.substring('Password must contain '.length),
      );
    }
    return switch (message) {
      'Password is required' => l10n.authPasswordRequired,
      'Password must be at least 8 characters' =>
        l10n.authPasswordTooShort(passwordMinLength),
      'Password must be at most 16 characters' =>
        l10n.authPasswordMaxLength(passwordMaxLength),
      'Password must not contain spaces' => l10n.authPasswordNoSpaces,
      'Password must not be all digits' => l10n.authPasswordAllDigits,
      'Password must not match the account email' =>
        l10n.authPasswordMatchesEmail,
      _ => message,
    };
  }
}
