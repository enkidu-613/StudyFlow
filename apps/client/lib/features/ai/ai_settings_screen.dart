import 'package:flutter/material.dart';

import 'ai_repository.dart';
import 'ai_settings_model.dart';
import '../../l10n/l10n_extension.dart';

final class AiSettingsScreen extends StatefulWidget {
  const AiSettingsScreen({
    required this.store,
    required this.repository,
    super.key,
  });

  final AiSettingsStore store;
  final AiRepository repository;

  @override
  State<AiSettingsScreen> createState() => _AiSettingsScreenState();
}

final class _AiSettingsScreenState extends State<AiSettingsScreen> {
  final _formKey = GlobalKey<FormState>();
  final _baseUrlController = TextEditingController();
  final _modelController = TextEditingController();
  final _apiKeyController = TextEditingController();
  bool _enabled = false;
  bool _loading = true;
  bool _saving = false;
  String? _testResult;
  bool _testFailed = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _baseUrlController.dispose();
    _modelController.dispose();
    _apiKeyController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final settings = await widget.store.read();
    if (!mounted) {
      return;
    }
    setState(() {
      _baseUrlController.text = settings.baseUrl;
      _modelController.text = settings.model;
      _apiKeyController.text = settings.apiKey;
      _enabled = settings.enabled;
      _loading = false;
    });
  }

  Future<void> _save() async {
    if (!(_formKey.currentState?.validate() ?? false)) {
      return;
    }
    setState(() {
      _saving = true;
      _testResult = null;
    });
    try {
      await widget.store.write(
        AiSettings(
          baseUrl: _baseUrlController.text.trim(),
          model: _modelController.text.trim(),
          apiKey: _apiKeyController.text.trim(),
          enabled: _enabled,
        ),
      );
      if (mounted) {
        setState(() {
          _testResult = context.l10n.aiSaved;
          _testFailed = false;
        });
      }
    } finally {
      if (mounted) {
        setState(() => _saving = false);
      }
    }
  }

  Future<void> _test() async {
    if (!(_formKey.currentState?.validate() ?? false)) {
      return;
    }
    setState(() {
      _testResult = null;
      _saving = true;
    });
    try {
      await widget.repository.testConnection(
        AiSettings(
          baseUrl: _baseUrlController.text.trim(),
          model: _modelController.text.trim(),
          apiKey: _apiKeyController.text.trim(),
          enabled: _enabled,
        ),
      );
      if (mounted) {
        setState(() {
          _testResult = context.l10n.aiConnectionSuccess;
          _testFailed = false;
        });
      }
    } on AiApiFailure catch (error) {
      if (mounted) {
        setState(() {
          _testResult = context.l10n.aiConnectionFailed(error.message);
          _testFailed = true;
        });
      }
    } on Object {
      if (mounted) {
        setState(() {
          _testResult = context.l10n.aiConnectionFailedGeneric;
          _testFailed = true;
        });
      }
    } finally {
      if (mounted) {
        setState(() => _saving = false);
      }
    }
  }

  Future<void> _clear() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(context.l10n.aiClearTitle),
        content: Text(context.l10n.aiClearBody),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(context.l10n.commonCancel),
          ),
          FilledButton(
            key: const Key('ai-clear-confirm-button'),
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(context.l10n.aiClearConfirm),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) {
      return;
    }
    setState(() => _saving = true);
    try {
      await widget.store.clear();
      if (!mounted) {
        return;
      }
      setState(() {
        _baseUrlController.clear();
        _modelController.clear();
        _apiKeyController.clear();
        _enabled = false;
        _testResult = context.l10n.aiCleared;
        _testFailed = false;
      });
    } finally {
      if (mounted) {
        setState(() => _saving = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Scaffold(
      appBar: AppBar(title: Text(l10n.settingsAiEntry)),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Form(
              key: _formKey,
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: <Widget>[
                  SwitchListTile(
                    key: const Key('ai-enabled-switch'),
                    title: Text(l10n.aiEnabledTitle),
                    subtitle: Text(l10n.aiEnabledSubtitle),
                    value: _enabled,
                    onChanged: (value) =>
                        setState(() => _enabled = value),
                  ),
                  TextFormField(
                    key: const Key('ai-base-url-field'),
                    controller: _baseUrlController,
                    enabled: !_saving,
                    keyboardType: TextInputType.url,
                    decoration: InputDecoration(
                      labelText: l10n.aiBaseUrlLabel,
                      hintText: 'https://api.openai.com/v1',
                      prefixIcon: const Icon(Icons.link),
                    ),
                    validator: (value) =>
                        _localizedAiBaseUrlError(validateAiBaseUrl(value)),
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    key: const Key('ai-model-field'),
                    controller: _modelController,
                    enabled: !_saving,
                    decoration: InputDecoration(
                      labelText: l10n.aiModelLabel,
                      hintText: 'gpt-4o-mini',
                      prefixIcon: const Icon(Icons.smart_toy_outlined),
                    ),
                    validator: (value) =>
                        value == null || value.trim().isEmpty
                            ? l10n.aiModelRequired
                            : null,
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    key: const Key('ai-api-key-field'),
                    controller: _apiKeyController,
                    enabled: !_saving,
                    obscureText: true,
                    decoration: InputDecoration(
                      labelText: l10n.aiApiKeyLabel,
                      prefixIcon: const Icon(Icons.key_outlined),
                    ),
                    validator: (value) =>
                        value == null || value.trim().isEmpty
                            ? l10n.aiApiKeyRequired
                            : null,
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: <Widget>[
                      Expanded(
                        child: FilledButton.icon(
                          key: const Key('ai-save-button'),
                          onPressed: _saving ? null : _save,
                          icon: const Icon(Icons.save_outlined),
                          label: Text(l10n.aiSave),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: OutlinedButton.icon(
                          key: const Key('ai-test-button'),
                          onPressed: _saving ? null : _test,
                          icon: const Icon(Icons.bolt_outlined),
                          label: Text(l10n.aiTestConnection),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  TextButton.icon(
                    key: const Key('ai-clear-button'),
                    onPressed: _saving ? null : _clear,
                    icon: const Icon(Icons.delete_outline),
                    label: Text(l10n.aiClearConfig),
                    style: TextButton.styleFrom(
                      foregroundColor: Theme.of(context).colorScheme.error,
                    ),
                  ),
                  if (_testResult != null) ...<Widget>[
                    const SizedBox(height: 12),
                    Text(
                      _testResult!,
                      key: const Key('ai-test-result'),
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: _testFailed
                            ? Theme.of(context).colorScheme.error
                            : Theme.of(context).colorScheme.primary,
                      ),
                    ),
                  ],
                ],
              ),
            ),
    );
  }

  String? _localizedAiBaseUrlError(String? message) {
    final l10n = context.l10n;
    if (message == null) {
      return null;
    }
    return switch (message) {
      'Base URL is required' => l10n.aiBaseUrlRequired,
      'Enter a valid URL' => l10n.aiBaseUrlInvalid,
      'Base URL must use HTTPS' => l10n.aiBaseUrlRequireHttps,
      _ => message,
    };
  }
}
