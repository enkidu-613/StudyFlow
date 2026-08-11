import 'package:flutter/material.dart';
import 'package:studyflow/app/studyflow_workspace.dart';
import 'package:studyflow/auth/recovery_key_screen.dart';
import 'package:studyflow/sync/sync_status.dart';
import 'package:studyflow_platform_contract/platform_contract.dart';

final class SettingsScreen extends StatefulWidget {
  const SettingsScreen({
    required this.workspace,
    this.recoveryController,
    this.syncStatus,
    this.onSync,
    super.key,
  });

  final StudyFlowWorkspace workspace;
  final RecoveryKeyController? recoveryController;
  final SyncStatusListenable? syncStatus;
  final Future<SyncRunResult?> Function()? onSync;

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

  Future<void> _syncNow() async {
    final onSync = widget.onSync;
    if (onSync == null) {
      return;
    }
    await onSync();
    await _refresh();
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
            _SyncStatusCard(
              pendingFallback: _pending,
              status: widget.syncStatus,
              onSync: widget.onSync == null ? null : _syncNow,
            ),
            if (widget.recoveryController != null)
              Card(
                child: ListTile(
                  leading: const Icon(Icons.key_outlined),
                  title: const Text('Account recovery key'),
                  subtitle: const Text(
                    'Export it once and store it offline in a private place.',
                  ),
                  trailing: IconButton(
                    key: const Key('open-recovery-screen'),
                    tooltip: 'Open recovery key',
                    icon: const Icon(Icons.arrow_forward),
                    onPressed: () => Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => RecoveryKeyScreen(
                          controller: widget.recoveryController!,
                        ),
                      ),
                    ),
                  ),
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

final class _SyncStatusCard extends StatelessWidget {
  const _SyncStatusCard({
    required this.pendingFallback,
    required this.status,
    required this.onSync,
  });

  final int pendingFallback;
  final SyncStatusListenable? status;
  final Future<void> Function()? onSync;

  @override
  Widget build(BuildContext context) {
    final listenable = status;
    if (listenable == null) {
      return _buildCard(
        const SyncStatus.idle(pendingCount: 0),
        pendingOverride: pendingFallback,
      );
    }
    return ValueListenableBuilder<SyncStatus>(
      valueListenable: listenable,
      builder: (context, value, child) => _buildCard(value),
    );
  }

  Widget _buildCard(SyncStatus value, {int? pendingOverride}) {
    final pending = pendingOverride ?? value.pendingCount;
    final isIdle = value.kind == SyncStatusKind.idle;
    final isOffline = value.kind == SyncStatusKind.offline;
    final subtitle = switch (value.kind) {
      SyncStatusKind.idle => 'Synchronized or waiting for changes',
      SyncStatusKind.syncing => 'Synchronizing encrypted records…',
      SyncStatusKind.offline => 'Offline; local changes are safe',
      SyncStatusKind.failed =>
        'Sync failed: ${value.failureCategory?.name ?? 'unknown'}',
    };
    return Card(
      child: ListTile(
        leading: Icon(
          isIdle ? Icons.cloud_done_outlined : Icons.cloud_upload_outlined,
        ),
        title: const Text('Pending sync'),
        subtitle: Text(subtitle),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Text('$pending'),
            if (onSync != null)
              IconButton(
                key: const Key('sync-now-button'),
                tooltip: isOffline ? 'Retry when online' : 'Sync now',
                onPressed: onSync,
                icon: Icon(
                  isOffline ? Icons.refresh : Icons.sync,
                ),
              ),
          ],
        ),
      ),
    );
  }
}
