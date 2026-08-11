import 'package:flutter/material.dart';

import '../security/key_manager.dart';

abstract interface class RecoveryKeyController {
  Future<String> exportRecoveryKey();

  Future<void> restoreRecoveryKey(String recoveryKey);
}

final class KeyManagerRecoveryKeyController implements RecoveryKeyController {
  KeyManagerRecoveryKeyController(this._keyManager);

  final KeyManager _keyManager;

  @override
  Future<String> exportRecoveryKey() => _keyManager.exportRecoveryKey();

  @override
  Future<void> restoreRecoveryKey(String recoveryKey) =>
      _keyManager.restoreRecoveryKey(recoveryKey);
}

class RecoveryKeyScreen extends StatefulWidget {
  const RecoveryKeyScreen({required this.controller, super.key});

  final RecoveryKeyController controller;

  @override
  State<RecoveryKeyScreen> createState() => _RecoveryKeyScreenState();
}

class _RecoveryKeyScreenState extends State<RecoveryKeyScreen> {
  final _restoreController = TextEditingController();
  bool _confirmed = false;
  bool _busy = false;
  String? _visibleRecoveryKey;
  String? _message;

  @override
  void dispose() {
    _visibleRecoveryKey = null;
    _restoreController.clear();
    _restoreController.dispose();
    super.dispose();
  }

  Future<void> _showRecoveryKey() async {
    if (!_confirmed || _visibleRecoveryKey != null) {
      return;
    }
    setState(() => _busy = true);
    try {
      final exported = await widget.controller.exportRecoveryKey();
      if (mounted) {
        setState(() {
          _visibleRecoveryKey = exported;
          _message = null;
        });
      }
    } on Object {
      if (mounted) {
        setState(() => _message = 'Recovery key export failed on this device.');
      }
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  Future<void> _restore() async {
    final value = _restoreController.text.trim();
    if (value.isEmpty) {
      setState(() => _message = 'Enter the recovery key.');
      return;
    }
    setState(() => _busy = true);
    try {
      await widget.controller.restoreRecoveryKey(value);
      _restoreController.clear();
      if (mounted) {
        setState(
            () => _message = 'Account encryption key restored on this device.');
      }
    } on Object {
      if (mounted) {
        setState(() {
          _message =
              'Recovery failed. Without the correct recovery key, encrypted '
              'account data cannot be recovered.';
        });
      }
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('Recovery key')),
        body: ListView(
          padding: const EdgeInsets.all(24),
          children: <Widget>[
            const Text(
              'If this recovery key is lost, encrypted account data cannot be recovered.',
            ),
            CheckboxListTile(
              value: _confirmed,
              onChanged: _visibleRecoveryKey == null
                  ? (value) => setState(() => _confirmed = value ?? false)
                  : null,
              title:
                  const Text('I will store it somewhere private and offline.'),
              contentPadding: EdgeInsets.zero,
            ),
            FilledButton(
              onPressed: !_confirmed || _busy || _visibleRecoveryKey != null
                  ? null
                  : _showRecoveryKey,
              child: const Text('Show recovery key once'),
            ),
            if (_visibleRecoveryKey != null) ...<Widget>[
              const SizedBox(height: 16),
              SelectableText(_visibleRecoveryKey!),
              const Text('This key is shown only for this recovery step.'),
            ],
            const Divider(height: 40),
            TextField(
              controller: _restoreController,
              obscureText: true,
              decoration:
                  const InputDecoration(labelText: 'Existing recovery key'),
            ),
            OutlinedButton(
              onPressed: _busy ? null : _restore,
              child: const Text('Restore encryption key'),
            ),
            if (_message != null) Text(_message!),
          ],
        ),
      );
}
