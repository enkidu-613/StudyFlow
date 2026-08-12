import 'package:flutter/material.dart';

import 'auth_repository.dart';
import 'email_auth_models.dart';

enum AuthMode { login, register }

final class AuthScreen extends StatefulWidget {
  const AuthScreen({
    required this.onLogin,
    required this.onRegister,
    this.initialMessage,
    super.key,
  });

  final Future<void> Function(String email, String password) onLogin;
  final Future<void> Function(String email, String password) onRegister;
  final String? initialMessage;

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
    if (error is AuthApiException) {
      return error.friendlyMessage;
    }
    if (error is AuthScopeException) {
      return '登录已过期，请重新登录';
    }
    return '网络连接失败，请检查网络后重试';
  }

  @override
  Widget build(BuildContext context) {
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
                'StudyFlow',
                style: Theme.of(context).textTheme.headlineMedium,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 24),
              SegmentedButton<AuthMode>(
                segments: const <ButtonSegment<AuthMode>>[
                  ButtonSegment<AuthMode>(
                    value: AuthMode.login,
                    label: Text('Sign in'),
                    icon: Icon(Icons.login),
                  ),
                  ButtonSegment<AuthMode>(
                    value: AuthMode.register,
                    label: Text('Create account'),
                    icon: Icon(Icons.person_add),
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
                      decoration: const InputDecoration(
                        labelText: 'Email',
                        prefixIcon: Icon(Icons.mail_outline),
                      ),
                      validator: validateEmailField,
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      key: const Key('auth-password-field'),
                      controller: _passwordController,
                      enabled: !_busy,
                      obscureText: true,
                      autofillHints: const <String>[AutofillHints.password],
                      decoration: const InputDecoration(
                        labelText: 'Password',
                        prefixIcon: Icon(Icons.lock_outline),
                      ),
                      validator: _mode == AuthMode.register
                          ? validateRegisterPasswordField
                          : validateLoginPasswordField,
                    ),
                    if (_mode == AuthMode.register) ...<Widget>[
                      const SizedBox(height: 12),
                      TextFormField(
                        key: const Key('auth-confirm-password-field'),
                        controller: _confirmPasswordController,
                        enabled: !_busy,
                        obscureText: true,
                        decoration: const InputDecoration(
                          labelText: 'Confirm password',
                          prefixIcon: Icon(Icons.lock_outline),
                        ),
                        validator: (value) {
                          if (value == null || value.isEmpty) {
                            return 'Confirm your password';
                          }
                          if (value != _passwordController.text) {
                            return 'Passwords do not match';
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
                          : Text(_submitLabel),
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
            ],
          ),
        ),
      ),
    );
  }

  String get _submitLabel =>
      _mode == AuthMode.login ? 'Sign in' : 'Create account';
}
