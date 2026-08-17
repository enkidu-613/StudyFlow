import 'package:flutter/material.dart';
import 'package:studyflow/app/local_account_migration.dart';
import 'package:studyflow/app/studyflow_workspace.dart';
import 'package:studyflow/features/ai/ai_repository.dart';
import 'package:studyflow/features/ai/ai_settings_model.dart';
import 'package:studyflow/features/ai/ai_settings_screen.dart';
import 'package:studyflow/features/backups/backups_repository.dart';
import 'package:studyflow/features/backups/backups_screen.dart';
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
    this.backupsRepositoryFactory,
    super.key,
  });

  final StudyFlowWorkspace workspace;
  final SyncStatusListenable? syncStatus;
  final Future<SyncRunResult?> Function()? onSync;
  final Future<void> Function()? onLogout;
  final Locale? locale;
  final Future<void> Function(String? tag)? onLocaleChanged;
  final BackupsRepository? Function()? backupsRepositoryFactory;

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

final class _SettingsScreenState extends State<SettingsScreen>
    with WidgetsBindingObserver {
  PermissionHealth? _health;
  CapabilityResult? _usageResult;
  int _pending = 0;
  Object? _error;
  List<LocalAccountMigrationCandidate> _migrationCandidates =
      const <LocalAccountMigrationCandidate>[];
  bool _importingLocalData = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _refresh();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Exact-alarm and battery settings are opened outside the app. Refresh
    // after returning instead of reporting the old denied state immediately.
    if (state == AppLifecycleState.resumed) {
      _refresh();
    }
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
              if (!(Theme.of(context).platform == TargetPlatform.android &&
                  state.id == PlatformPermissionId.menuBar))
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
            if (widget.backupsRepositoryFactory != null)
              Card(
                child: ListTile(
                  key: const Key('open-backups'),
                  leading: const Icon(Icons.cloud_outlined),
                  title: Text(l10n.settingsBackupsEntry),
                  subtitle: Text(l10n.settingsBackupsSubtitle),
                  trailing: const Icon(Icons.arrow_forward),
                  onTap: () {
                    final repository = widget.backupsRepositoryFactory!();
                    if (repository == null) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text(l10n.authSessionExpired)),
                      );
                      return;
                    }
                    Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => BackupsScreen(repository: repository),
                      ),
                    );
                  },
                ),
              ),
            const SizedBox(height: 8),
            Card(
              child: ListTile(
                key: const Key('import-local-account-data'),
                leading: const Icon(Icons.move_down_outlined),
                title:
                    Text(_migrationCandidates.isEmpty ? '检查旧本地数据' : '导入旧本地数据'),
                subtitle: Text(_migrationCandidates.isEmpty
                    ? '检查是否有未登录时创建的任务、日程和药物记录。'
                    : '发现 ${_migrationCandidates.length} 个旧账户空间；'
                        '其中最多包含 ${_migrationCandidates.first.recordCount} 条记录。'),
                trailing: _importingLocalData
                    ? const SizedBox.square(
                        dimension: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.arrow_forward),
                onTap: _importingLocalData
                    ? null
                    : (_migrationCandidates.isEmpty
                        ? _checkForLocalData
                        : _importLocalData),
              ),
            ),
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
      await widget.workspace.platform.showUnavailablePermission(
        state.id,
        title: l10n.permissionUnavailableTitle,
        message: l10n.permissionUnavailableMessage(
          l10n.permissionLabel(state.id),
        ),
      );
      return;
    }
    if (state.allowed) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            content: Text(
              '${l10n.permissionLabel(state.id)}：'
              '${l10n.permissionDetailText(state.detail, allowed: true)}',
            ),
          ),
        );
      return;
    }
    final status = await widget.workspace.platform.requestPermission(state.id);
    await _refresh();
    if (!mounted) {
      return;
    }
    switch (status) {
      case 'authorized':
        break;
      case 'opened_settings':
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(l10n.permissionPromptSettingsOpened)),
        );
      case 'declined':
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(l10n.permissionPromptDeclined)),
        );
      case 'denied':
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(l10n.permissionPromptDenied)),
        );
      default:
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(l10n.permissionPromptFailed)),
        );
    }
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

  Future<void> _importLocalData() async {
    final candidates = _migrationCandidates;
    if (candidates.isEmpty || _importingLocalData) return;
    final candidate = candidates.first;
    final approved = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('导入旧本地数据？'),
        content: Text(
          '将导入旧账户中的 ${candidate.recordCount} 条本地记录（含 ${candidate.scheduleCount} 条日程）。'
          '原数据不会删除；当前账户已有同一记录会跳过。导入后会创建新的同步记录。',
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('开始导入'),
          ),
        ],
      ),
    );
    if (approved != true || !mounted) return;
    setState(() => _importingLocalData = true);
    try {
      final result = await LocalAccountMigrationService(
        target: widget.workspace,
      ).importCandidate(candidate);
      await _syncNow();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('已导入 ${result.importedCount} 条记录。')),
      );
      await _refresh();
    } on Object catch (error) {
      if (mounted) setState(() => _error = error);
    } finally {
      if (mounted) setState(() => _importingLocalData = false);
    }
  }

  Future<void> _checkForLocalData() async {
    if (_importingLocalData) return;
    setState(() => _importingLocalData = true);
    try {
      final candidates = await LocalAccountMigrationService(
        target: widget.workspace,
      ).discover();
      if (!mounted) return;
      setState(() => _migrationCandidates = candidates);
      if (candidates.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('未发现可导入的旧本地数据。')),
        );
      }
    } on Object catch (error) {
      if (mounted) setState(() => _error = error);
    } finally {
      if (mounted) setState(() => _importingLocalData = false);
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
    final isOffline = value.kind == SyncStatusKind.offline;
    final isFailed = value.kind == SyncStatusKind.failed;
    final upToDate = value.kind == SyncStatusKind.idle && pending == 0;
    final hasPending = value.kind == SyncStatusKind.idle && pending > 0;
    final subtitle = switch (value.kind) {
      SyncStatusKind.idle when hasPending => l10n.syncPendingCount(pending),
      SyncStatusKind.idle => l10n.syncUpToDate,
      SyncStatusKind.syncing => l10n.syncSyncing,
      SyncStatusKind.offline => l10n.syncOffline,
      SyncStatusKind.failed => l10n.syncFailed(
          value.failureCategory?.name ?? l10n.syncUnknown,
        ),
    };
    return Card(
      child: ListTile(
        leading: Icon(
          isFailed
              ? Icons.cloud_off_outlined
              : (upToDate
                  ? Icons.cloud_done_outlined
                  : Icons.cloud_upload_outlined),
        ),
        title: Text(upToDate ? l10n.syncUpToDate : l10n.syncPending),
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
