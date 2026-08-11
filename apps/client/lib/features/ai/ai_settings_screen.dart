import 'package:flutter/material.dart';

import 'ai_repository.dart';
import 'ai_settings_model.dart';

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
        setState(() => _testResult = '已保存');
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
        setState(() => _testResult = '连接成功');
      }
    } on AiApiFailure catch (error) {
      if (mounted) {
        setState(() => _testResult = '连接失败：${error.message}');
      }
    } on Object {
      if (mounted) {
        setState(() => _testResult = '连接失败，请稍后重试');
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
        title: const Text('清除 AI 配置'),
        content: const Text('将删除本机的 Base URL、模型和 API Key，确定吗？'),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('取消'),
          ),
          FilledButton(
            key: const Key('ai-clear-confirm-button'),
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('清除'),
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
        _testResult = '已清除';
      });
    } finally {
      if (mounted) {
        setState(() => _saving = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('AI 设置')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Form(
              key: _formKey,
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: <Widget>[
                  SwitchListTile(
                    key: const Key('ai-enabled-switch'),
                    title: const Text('启用 AI 建议'),
                    subtitle: const Text('API Key 只保存在本机安全存储，不会上传。'),
                    value: _enabled,
                    onChanged: (value) =>
                        setState(() => _enabled = value),
                  ),
                  TextFormField(
                    key: const Key('ai-base-url-field'),
                    controller: _baseUrlController,
                    enabled: !_saving,
                    keyboardType: TextInputType.url,
                    decoration: const InputDecoration(
                      labelText: 'Base URL',
                      hintText: 'https://api.openai.com/v1',
                      prefixIcon: Icon(Icons.link),
                    ),
                    validator: validateAiBaseUrl,
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    key: const Key('ai-model-field'),
                    controller: _modelController,
                    enabled: !_saving,
                    decoration: const InputDecoration(
                      labelText: 'Model',
                      hintText: 'gpt-4o-mini',
                      prefixIcon: Icon(Icons.smart_toy_outlined),
                    ),
                    validator: (value) => value == null || value.trim().isEmpty
                        ? 'Model 名称不能为空'
                        : null,
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    key: const Key('ai-api-key-field'),
                    controller: _apiKeyController,
                    enabled: !_saving,
                    obscureText: true,
                    decoration: const InputDecoration(
                      labelText: 'API Key',
                      prefixIcon: Icon(Icons.key_outlined),
                    ),
                    validator: (value) => value == null || value.trim().isEmpty
                        ? 'API Key 不能为空'
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
                          label: const Text('保存'),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: OutlinedButton.icon(
                          key: const Key('ai-test-button'),
                          onPressed: _saving ? null : _test,
                          icon: const Icon(Icons.bolt_outlined),
                          label: const Text('测试连接'),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  TextButton.icon(
                    key: const Key('ai-clear-button'),
                    onPressed: _saving ? null : _clear,
                    icon: const Icon(Icons.delete_outline),
                    label: const Text('清除配置'),
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
                        color: _testResult!.startsWith('连接失败')
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
}
