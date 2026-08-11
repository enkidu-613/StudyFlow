import 'package:flutter/material.dart';

import 'auth_repository.dart';

class PairingScreen extends StatefulWidget {
  const PairingScreen({
    required this.repository,
    required this.deviceId,
    required this.devicePublicKey,
    super.key,
  });

  final AuthRepository repository;
  final String deviceId;
  final String devicePublicKey;

  @override
  State<PairingScreen> createState() => _PairingScreenState();
}

class _PairingScreenState extends State<PairingScreen> {
  final _codeController = TextEditingController();
  String? _message;
  bool _isSubmitting = false;

  @override
  void dispose() {
    _codeController.dispose();
    super.dispose();
  }

  Future<void> _pair() async {
    final code = _codeController.text.trim();
    if (!RegExp(r'^[0-9]{6}$').hasMatch(code)) {
      setState(() => _message = 'Enter the 6-digit pairing code.');
      return;
    }
    setState(() {
      _isSubmitting = true;
      _message = null;
    });
    try {
      await widget.repository.pair(
        code: code,
        deviceId: widget.deviceId,
        devicePublicKey: widget.devicePublicKey,
      );
      if (mounted) {
        setState(() => _message = 'Device enrolled securely.');
      }
    } on Object {
      if (mounted) {
        setState(() =>
            _message = 'Pairing failed. Request a new code and try again.');
      }
    } finally {
      if (mounted) {
        setState(() => _isSubmitting = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('Pair this device')),
        body: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              const Text(
                'Enter the one-time code from an already enrolled StudyFlow device.',
              ),
              const SizedBox(height: 16),
              TextField(
                key: const Key('pairing-code-field'),
                controller: _codeController,
                keyboardType: TextInputType.number,
                maxLength: 6,
                obscureText: true,
                decoration: const InputDecoration(labelText: '6-digit code'),
              ),
              FilledButton(
                onPressed: _isSubmitting ? null : _pair,
                child: Text(_isSubmitting ? 'Pairing…' : 'Pair device'),
              ),
              if (_message != null) ...<Widget>[
                const SizedBox(height: 16),
                Text(_message!),
              ],
            ],
          ),
        ),
      );
}
