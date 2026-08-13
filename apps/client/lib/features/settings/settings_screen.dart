import 'package:flutter/material.dart';
import 'package:studyflow/app/studyflow_workspace.dart';
import 'package:studyflow/features/ai/ai_repository.dart';
import 'package:studyflow/features/ai/ai_settings_model.dart';
import 'package:studyflow/features/ai/ai_settings_screen.dart';
import 'package:studyflow/l10n/l10n_extension.dart';
import 'package:studyflow/sync/sync_status.dart';
import 'package:studyflow_platform_contract/platform_contract.dart';

final class SettingsScreen extends StatefulWidget {
  const SettingsScreen({
    required this.workspace,
    this.syncStatus,
    this.onSync,
    this.onLogout,
    this.locale,
    this.onLocaleChanged,
    super.key,
  });

  final StudyFlowWorkspace workspace;
  final SyncStatusListenable? syncStatus;
  final Future<SyncRunResult?> Function()? onSync;
  final Future<void> Function()? onLogout;
  final Locale? locale;
  final Future<void> Function(String? tag)? onLocaleChanged;

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
    final l10n = context.l10n;
    return Scaffold(
      appBar: AppBar(title: Text(l10n.navSettings)),
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
            if (_usageResult != null)
              Card(
                child: ListTile(
                  leading: const Icon(Icons.bar_chart_outlined),
                  title: Text(l10n.settingsUsageSummary),
                  subtitle: Text(_usageResult!.message),
                  trailing: Icon(
                    _usageResult!.isSupported
                        ? Icons.check_circle_outline
                        : Icons.info_outline,
                  ),
                ),
              ),
            const SizedBox(height: 8),
            Text(
              l10n.settingsPermissions,
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            for (final state in _health?.states ?? const <PermissionState>[])
              Card(
                child: ListTile(
                  leading: Icon(
                    state.allowed
                        ? Icons.check_circle_outline
                        : Icons.radio_button_unchecked,
                  ),
                  title: Text(l10n.permissionLabel(state.id)),
                  subtitle: Text(
                    l10n.permissionDetailText(
                      state.detail,
                      allowed: state.allowed,
                    ),
                  ),
                  trailing: Text(
                    l10n.permissionStatusText(
                      available: state.available,
                      allowed: state.allowed,
                    ),
                  ),
                  onTap: () => _handlePermissionTap(state),
                ),
              ),
            const SizedBox(height: 16),
            if (widget.onLocaleChanged != null)
              Card(
                child: ListTile(
                  key: const Key('language-setting'),
                  leading: const Icon(Icons.language_outlined),
                  title: Text(l10n.settingsLanguage),
                  trailing: DropdownButton<String>(
                    value: _selectedLanguageTag(widget.locale),
                    underline: const SizedBox.shrink(),
                    items: <DropdownMenuItem<String>>[
                      DropdownMenuItem<String>(
                        value: 'system',
                        child: Text(l10n.settingsLanguageSystem),
                      ),
                      const DropdownMenuItem<String>(
                        value: 'zh',
                        child: Text('简体中文'),
                      ),
                      const DropdownMenuItem<String>(
                        value: 'en',
                        child: Text('English'),
                      ),
                    ],
                    onChanged: (tag) {
                      if (tag != null) {
                        widget.onLocaleChanged!(
                          tag == 'system' ? null : tag,
                        );
                      }
                    },
                  ),
                ),
              ),
            const SizedBox(height: 8),
            Card(
              child: ListTile(
                key: const Key('open-ai-settings'),
                leading: const Icon(Icons.auto_awesome_outlined),
                title: Text(l10n.settingsAiEntry),
                subtitle: Text(l10n.settingsAiSubtitle),
                trailing: const Icon(Icons.arrow_forward),
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => AiSettingsScreen(
                      store: SecureAiSettingsStore(),
                      repository: HttpAiRepository(),
                    ),
                  ),
                ),
              ),
            ),
            if (widget.onLogout != null) ...<Widget>[
              const SizedBox(height: 16),
              OutlinedButton.icon(
                key: const Key('sign-out-button'),
                onPressed: _busyLogout ? null : _signOut,
                icon: const Icon(Icons.logout),
                label: Text(l10n.settingsSignOut),
              ),
            ],
          ],
        ),
      ),
    );
  }

  bool _busyLogout = false;

  Future<void> _handlePermissionTap(PermissionState state) async {
    final l10n = context.l10n;
    if (!state.available) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            l10n.permissionDetailText(state.detail, allowed: false),
          ),
        ),
      );
      return;
    }
    if (state.allowed) {
      return;
    }
    final isNotification = state.id == PlatformPermissionId.notifications ||
        state.id == PlatformPermissionId.userNotifications;
    if (isNotification) {
      final granted = await widget.workspace.platform
          .requestPermission(state.id);
      await _refresh();
      if (!granted && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(l10n.permissionDetailRequired),
          ),
        );
      }
      return;
    }
    // App-internal permissions (menu bar, focus) have no system prompt.
    await widget.workspace.platform.openPermissionSettings();
  }

  String _selectedLanguageTag(Locale? locale) => switch (locale?.languageCode) {
        'zh' => 'zh',
        'en' => 'en',
        _ => 'system',
      };

  Future<void> _signOut() async {
    final onLogout = widget.onLogout;
    if (onLogout == null || _busyLogout) {
      return;
    }
    setState(() => _busyLogout = true);
    try {
      await onLogout();
    } finally {
      if (mounted) {
        setState(() => _busyLogout = false);
      }
    }
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
        context,
        const SyncStatus.idle(pendingCount: 0),
        pendingOverride: pendingFallback,
      );
    }
    return ValueListenableBuilder<SyncStatus>(
      valueListenable: listenable,
      builder: (context, value, child) => _buildCard(context, value),
    );
  }

  Widget _buildCard(
    BuildContext context,
    SyncStatus value, {
    int? pendingOverride,
  }) {
    final l10n = context.l10n;
    final pending = pendingOverride ?? value.pendingCount;
    final isIdle = value.kind == SyncStatusKind.idle;
    final isOffline = value.kind == SyncStatusKind.offline;
    final subtitle = switch (value.kind) {
      SyncStatusKind.idle => l10n.syncIdle,
      SyncStatusKind.syncing => l10n.syncSyncing,
      SyncStatusKind.offline => l10n.syncOffline,
      SyncStatusKind.failed => l10n.syncFailed(
          value.failureCategory?.name ?? l10n.syncUnknown,
        ),
    };
    return Card(
      child: ListTile(
        leading: Icon(
          isIdle ? Icons.cloud_done_outlined : Icons.cloud_upload_outlined,
        ),
        title: Text(l10n.syncPendingTitle),
        subtitle: Text(subtitle),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Text('$pending'),
            if (onSync != null)
              IconButton(
                key: const Key('sync-now-button'),
                tooltip: isOffline ? l10n.syncRetryOnline : l10n.syncNow,
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
