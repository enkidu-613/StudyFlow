import 'package:flutter/material.dart';

enum AuthMode { login, bootstrap, pair, recovery }

final class AuthScreen extends StatefulWidget {
  const AuthScreen({
    required this.onLogin,
    required this.onBootstrap,
    required this.onPair,
    this.recoveryAccountId,
    this.onRecovery,
    this.onUseLocal,
    this.initialMessage,
    super.key,
  });

  final Future<void> Function(String password) onLogin;
  final Future<void> Function(String token, String password) onBootstrap;
  final Future<void> Function(String code) onPair;
  final String? recoveryAccountId;
  final Future<void> Function(String recoveryKey)? onRecovery;
  final Future<void> Function()? onUseLocal;
  final String? initialMessage;

  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

final class _AuthScreenState extends State<AuthScreen> {
  AuthMode _mode = AuthMode.login;
  final _passwordController = TextEditingController();
  final _bootstrapTokenController = TextEditingController();
  final _pairingCodeController = TextEditingController();
  final _recoveryKeyController = TextEditingController();
  String? _message;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _message = widget.initialMessage;
  }

  @override
  void dispose() {
    _passwordController.dispose();
    _bootstrapTokenController.dispose();
    _pairingCodeController.dispose();
    _recoveryKeyController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_busy) {
      return;
    }
    final password = _passwordController.text;
    if ((_mode == AuthMode.login || _mode == AuthMode.bootstrap) &&
        password.isEmpty) {
      setState(() => _message = 'Password is required.');
      return;
    }
    if (_mode == AuthMode.bootstrap && _bootstrapTokenController.text.isEmpty) {
      setState(() => _message = 'Bootstrap token is required.');
      return;
    }
    if (_mode == AuthMode.pair &&
        !RegExp(r'^\d{6}$').hasMatch(_pairingCodeController.text)) {
      setState(() => _message = 'Enter the 6-digit pairing code.');
      return;
    }
    if (_mode == AuthMode.recovery &&
        _recoveryKeyController.text.trim().isEmpty) {
      setState(() => _message = 'Enter the recovery key.');
      return;
    }

    setState(() {
      _busy = true;
      _message = null;
    });
    try {
      switch (_mode) {
        case AuthMode.login:
          await widget.onLogin(password);
        case AuthMode.bootstrap:
          await widget.onBootstrap(_bootstrapTokenController.text, password);
        case AuthMode.pair:
          await widget.onPair(_pairingCodeController.text);
        case AuthMode.recovery:
          await widget.onRecovery!(_recoveryKeyController.text.trim());
      }
    } on Object catch (error) {
      if (mounted) {
        setState(() => _message = 'Authentication failed: $error');
      }
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  Future<void> _useLocal() async {
    if (widget.onUseLocal == null || _busy) {
      return;
    }
    setState(() => _busy = true);
    try {
      await widget.onUseLocal!();
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
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
                segments: <ButtonSegment<AuthMode>>[
                  const ButtonSegment<AuthMode>(
                    value: AuthMode.login,
                    label: Text('Sign in'),
                    icon: Icon(Icons.login),
                  ),
                  const ButtonSegment<AuthMode>(
                    value: AuthMode.bootstrap,
                    label: Text('Initialize'),
                    icon: Icon(Icons.person_add),
                  ),
                  const ButtonSegment<AuthMode>(
                    value: AuthMode.pair,
                    label: Text('Pair'),
                    icon: Icon(Icons.devices),
                  ),
                  if (widget.onRecovery != null)
                    const ButtonSegment<AuthMode>(
                      value: AuthMode.recovery,
                      label: Text('Recover'),
                      icon: Icon(Icons.key),
                    ),
                ],
                selected: <AuthMode>{_mode},
                onSelectionChanged: (selection) => setState(() {
                  _mode = selection.single;
                  _message = null;
                }),
              ),
              const SizedBox(height: 20),
              if (_mode == AuthMode.bootstrap)
                TextField(
                  key: const Key('bootstrap-token-field'),
                  controller: _bootstrapTokenController,
                  obscureText: true,
                  decoration: const InputDecoration(
                    labelText: 'One-time bootstrap token',
                  ),
                ),
              if (_mode == AuthMode.bootstrap) const SizedBox(height: 12),
              if (_mode == AuthMode.login || _mode == AuthMode.bootstrap)
                TextField(
                  key: const Key('auth-password-field'),
                  controller: _passwordController,
                  obscureText: true,
                  decoration: const InputDecoration(labelText: 'Password'),
                ),
              if (_mode == AuthMode.pair)
                TextField(
                  key: const Key('pairing-code-field'),
                  controller: _pairingCodeController,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: '6-digit pairing code',
                  ),
                ),
              if (_mode == AuthMode.recovery) ...<Widget>[
                if (widget.recoveryAccountId != null)
                  Text(
                    'Account: ${widget.recoveryAccountId}',
                    key: const Key('recovery-account-id'),
                  ),
                const SizedBox(height: 12),
                TextField(
                  key: const Key('recovery-key-field'),
                  controller: _recoveryKeyController,
                  obscureText: true,
                  decoration: const InputDecoration(
                    labelText: 'Recovery key',
                  ),
                ),
              ],
              const SizedBox(height: 16),
              FilledButton(
                key: const Key('auth-submit-button'),
                onPressed: _busy ? null : _submit,
                child: Text(_busy ? 'Working…' : _submitLabel),
              ),
              if (widget.onUseLocal != null) ...<Widget>[
                const SizedBox(height: 8),
                OutlinedButton(
                  key: const Key('local-mode-button'),
                  onPressed: _busy ? null : _useLocal,
                  child: const Text('Use local offline mode'),
                ),
              ],
              if (_message != null) ...<Widget>[
                const SizedBox(height: 16),
                Text(_message!, textAlign: TextAlign.center),
              ],
            ],
          ),
        ),
      ),
    );
  }

  String get _submitLabel => switch (_mode) {
        AuthMode.login => 'Sign in',
        AuthMode.bootstrap => 'Initialize account',
        AuthMode.pair => 'Pair device',
        AuthMode.recovery => 'Restore account key',
      };
}
