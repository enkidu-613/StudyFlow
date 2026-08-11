import 'package:flutter/material.dart';
import 'package:studyflow/app/studyflow_workspace.dart';
import 'package:studyflow_platform_contract/platform_contract.dart';

final class SettingsScreen extends StatefulWidget {
  const SettingsScreen({required this.workspace, super.key});

  final StudyFlowWorkspace workspace;

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

final class _SettingsScreenState extends State<SettingsScreen> {
  PermissionHealth? _health;
  CapabilityResult? _usageResult;
  int _pending = 0;
  Object? _error;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() async {
    try {
      final health = await widget.workspace.platform.getPermissionStatus();
      final usage = await widget.workspace.platform.getUsageSummary();
      final pending = await widget.workspace.pendingCount();
      if (!mounted) {
        return;
      }
      setState(() {
        _health = health;
        _usageResult = usage;
        _pending = pending;
        _error = null;
      });
    } on Object catch (error) {
      if (mounted) {
        setState(() => _error = error);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: RefreshIndicator(
        onRefresh: _refresh,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: <Widget>[
            if (_error != null)
              ListTile(
                leading: const Icon(Icons.error_outline),
                title: Text('$_error'),
              ),
            Card(
              child: ListTile(
                leading: Icon(
                  _pending == 0
                      ? Icons.cloud_done_outlined
                      : Icons.cloud_upload_outlined,
                ),
                title: const Text('Pending sync'),
                trailing: Text('$_pending'),
              ),
            ),
            if (_usageResult != null)
              Card(
                child: ListTile(
                  leading: const Icon(Icons.bar_chart_outlined),
                  title: const Text('Usage summary'),
                  subtitle: Text(_usageResult!.message),
                  trailing: Icon(
                    _usageResult!.isSupported
                        ? Icons.check_circle_outline
                        : Icons.info_outline,
                  ),
                ),
              ),
            const SizedBox(height: 8),
            const Text('Permissions',
                style: TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            for (final state in _health?.states ?? const <PermissionState>[])
              Card(
                child: ListTile(
                  leading: Icon(
                    state.allowed
                        ? Icons.check_circle_outline
                        : Icons.radio_button_unchecked,
                  ),
                  title: Text(state.id.name),
                  subtitle: Text(state.detail),
                  trailing: Text(state.available ? 'available' : 'unavailable'),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
