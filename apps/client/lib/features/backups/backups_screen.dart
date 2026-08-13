import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../l10n/l10n_extension.dart';
import 'backup_models.dart';
import 'backups_repository.dart';

final class BackupsScreen extends StatefulWidget {
  const BackupsScreen({
    required this.repository,
    super.key,
  });

  final BackupsRepository repository;

  @override
  State<BackupsScreen> createState() => _BackupsScreenState();
}

final class _BackupsScreenState extends State<BackupsScreen> {
  List<BackupSummary>? _backups;
  Object? _error;
  bool _loading = true;
  bool _creating = false;
  bool _selectionMode = false;
  final Set<String> _selectedIds = <String>{};
  bool _batchDeleting = false;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() async {
    try {
      final result = await widget.repository.list();
      if (!mounted) {
        return;
      }
      setState(() {
        _backups = result.backups;
        _error = null;
        _loading = false;
        _selectedIds.removeWhere(
          (id) => !result.backups.any((b) => b.backupId == id),
        );
      });
    } on Object catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _error = error;
        _loading = false;
      });
    }
  }

  void _enterSelectionMode([String? initialId]) {
    setState(() {
      _selectionMode = true;
      if (initialId != null) {
        _selectedIds.add(initialId);
      }
    });
  }

  void _exitSelectionMode() {
    setState(() {
      _selectionMode = false;
      _selectedIds.clear();
    });
  }

  void _toggleSelected(String backupId) {
    setState(() {
      if (!_selectedIds.add(backupId)) {
        _selectedIds.remove(backupId);
      }
    });
  }

  void _toggleSelectAll() {
    final list = _backups ?? const <BackupSummary>[];
    setState(() {
      if (_selectedIds.length == list.length) {
        _selectedIds.clear();
      } else {
        _selectedIds
          ..clear()
          ..addAll(list.map((b) => b.backupId));
      }
    });
  }

  Future<void> _confirmBatchDelete() async {
    final l10n = context.l10n;
    final count = _selectedIds.length;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        key: const Key('backup-batch-delete-dialog'),
        title: Text(l10n.backupsBatchDeleteTitle),
        content: Text(l10n.backupsBatchDeleteBody(count)),
        actions: <Widget>[
          TextButton(
            key: const Key('backup-batch-delete-cancel-button'),
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(l10n.commonCancel),
          ),
          FilledButton(
            key: const Key('backup-batch-delete-confirm-button'),
            style: FilledButton.styleFrom(
              foregroundColor: Theme.of(context).colorScheme.error,
            ),
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(l10n.backupsDeleteSelected(count)),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) {
      return;
    }
    final ids = _selectedIds.toList(growable: false);
    setState(() => _batchDeleting = true);
    try {
      final result = await widget.repository.deleteMany(ids);
      if (!mounted) {
        return;
      }
      if (result.notFound.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(l10n.backupsBatchDeleteSuccess(result.deleted))),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              l10n.backupsBatchDeletePartial(
                result.deleted,
                result.notFound.length,
              ),
            ),
          ),
        );
      }
      _exitSelectionMode();
      await _refresh();
    } on BackupApiFailure catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(_friendlyError(error))),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _batchDeleting = false);
      }
    }
  }

  Future<void> _create() async {
    if (_creating) {
      return;
    }
    final l10n = context.l10n;
    setState(() => _creating = true);
    try {
      await widget.repository.create();
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.backupsCreateSuccess)),
      );
      await _refresh();
    } on BackupQuotaFailure {
      if (!mounted) {
        return;
      }
      await _showLimitDialog();
      await _refresh();
    } on BackupApiFailure catch (error) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(_friendlyError(error))),
      );
    } on Object catch (error) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(_friendlyError(error))),
      );
    } finally {
      if (mounted) {
        setState(() => _creating = false);
      }
    }
  }

  Future<void> _showLimitDialog() async {
    final l10n = context.l10n;
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        key: const Key('backup-limit-dialog'),
        title: Text(l10n.backupsLimitTitle),
        content: Text(
          l10n.backupsLimitBody(maxBackupsPerAccount),
        ),
        actions: <Widget>[
          TextButton(
            key: const Key('backup-limit-dismiss-button'),
            onPressed: () => Navigator.of(context).pop(),
            child: Text(l10n.commonCancel),
          ),
          FilledButton(
            key: const Key('backup-limit-go-delete-button'),
            onPressed: () => Navigator.of(context).pop(),
            child: Text(l10n.backupsLimitGoDelete),
          ),
        ],
      ),
    );
  }

  Future<void> _rename(BackupSummary backup) async {
    final l10n = context.l10n;
    final controller = TextEditingController(text: backup.name);
    final formKey = GlobalKey<FormState>();
    final newName = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        key: const Key('backup-rename-dialog'),
        title: Text(l10n.backupsRenameTitle),
        content: Form(
          key: formKey,
          child: TextFormField(
            key: const Key('backup-rename-field'),
            controller: controller,
            maxLength: 64,
            inputFormatters: <TextInputFormatter>[
              LengthLimitingTextInputFormatter(64),
            ],
            decoration: InputDecoration(labelText: l10n.backupsRenameLabel),
            validator: (value) {
              final trimmed = value?.trim() ?? '';
              if (trimmed.isEmpty) {
                return l10n.backupsRenameRequired;
              }
              if (trimmed.length > 64) {
                return l10n.backupsRenameTooLong(64);
              }
              return null;
            },
          ),
        ),
        actions: <Widget>[
          TextButton(
            key: const Key('backup-rename-cancel-button'),
            onPressed: () => Navigator.of(context).pop(),
            child: Text(l10n.commonCancel),
          ),
          FilledButton(
            key: const Key('backup-rename-confirm-button'),
            onPressed: () {
              if (formKey.currentState?.validate() ?? false) {
                Navigator.of(context).pop(controller.text.trim());
              }
            },
            child: Text(l10n.commonSave),
          ),
        ],
      ),
    );
    if (newName == null || newName == backup.name || !mounted) {
      return;
    }
    try {
      await widget.repository.rename(backup.backupId, newName);
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.backupsRenameSuccess)),
      );
      await _refresh();
    } on BackupApiFailure catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(_friendlyError(error))),
        );
      }
    }
  }

  Future<void> _delete(BackupSummary backup) async {
    final l10n = context.l10n;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        key: const Key('backup-delete-dialog'),
        title: Text(l10n.backupsDeleteTitle),
        content: Text(l10n.backupsDeleteBody),
        actions: <Widget>[
          TextButton(
            key: const Key('backup-delete-cancel-button'),
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(l10n.commonCancel),
          ),
          FilledButton(
            key: const Key('backup-delete-confirm-button'),
            style: FilledButton.styleFrom(
              foregroundColor: Theme.of(context).colorScheme.error,
            ),
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(l10n.backupsDelete),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) {
      return;
    }
    try {
      await widget.repository.delete(backup.backupId);
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.backupsDeleteSuccess)),
      );
      await _refresh();
    } on BackupApiFailure catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(_friendlyError(error))),
        );
      }
    }
  }

  String _friendlyError(Object error) {
    final l10n = context.l10n;
    if (error is BackupOfflineFailure || error is BackupNetworkFailure) {
      return l10n.backupsLoadFailedOffline;
    }
    if (error is BackupRateLimitFailure) {
      return l10n.backupsCreateTooFrequent;
    }
    if (error is BackupAuthenticationFailure) {
      return l10n.authSessionExpired;
    }
    return l10n.backupsOperationFailed(
      switch (error) {
        BackupNotFoundFailure() => l10n.backupsDeleteTitle,
        BackupSchemaFailure() => l10n.authErrorInvalidInput,
        _ => l10n.authErrorGeneric,
      },
    );
  }

  String _formatDate(DateTime value) {
    final local = value.toLocal();
    final month = local.month.toString().padLeft(2, '0');
    final day = local.day.toString().padLeft(2, '0');
    final hour = local.hour.toString().padLeft(2, '0');
    final minute = local.minute.toString().padLeft(2, '0');
    return '${local.year}-$month-$day $hour:$minute';
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final backups = _backups;
    final list = backups ?? const <BackupSummary>[];
    return Scaffold(
      appBar: AppBar(
        title: Text(
          _selectionMode
              ? l10n.backupsSelectionTitle(_selectedIds.length)
              : l10n.settingsBackupsEntry,
        ),
        leading: _selectionMode
            ? IconButton(
                key: const Key('backup-selection-close-button'),
                icon: const Icon(Icons.close),
                onPressed: _batchDeleting ? null : _exitSelectionMode,
              )
            : null,
        actions: <Widget>[
          if (!_selectionMode &&
              !_loading &&
              _error == null &&
              list.isNotEmpty)
            TextButton(
              key: const Key('backups-edit-button'),
              onPressed: () => _enterSelectionMode(),
              child: Text(l10n.backupsEdit),
            ),
        ],
      ),
      body: _buildBody(list),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: _selectionMode
              ? _BackupsSelectionBar(
                  selectedCount: _selectedIds.length,
                  allSelected: list.isNotEmpty &&
                      _selectedIds.length == list.length,
                  deleting: _batchDeleting,
                  onSelectAll: _toggleSelectAll,
                  onDelete: _confirmBatchDelete,
                  onCancel: _exitSelectionMode,
                )
              : FilledButton.icon(
                  key: const Key('create-backup-button'),
                  onPressed: _creating || list.length >= maxBackupsPerAccount
                      ? null
                      : _create,
                  icon: _creating
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.cloud_upload_outlined),
                  label: Text(l10n.backupsCreate),
                ),
        ),
      ),
    );
  }

  Widget _buildBody(List<BackupSummary> list) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null) {
      return _BackupsErrorState(
        offline: _error is BackupOfflineFailure ||
            _error is BackupNetworkFailure,
        onRetry: _refresh,
      );
    }
    return IgnorePointer(
      ignoring: _batchDeleting,
      child: RefreshIndicator(
        onRefresh: _refresh,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: <Widget>[
            _BackupCapacityCard(used: list.length, max: maxBackupsPerAccount),
            const SizedBox(height: 12),
            if (list.isEmpty)
              const _BackupsEmptyState()
            else
              for (final backup in list)
                _BackupListItem(
                  backup: backup,
                  selectionMode: _selectionMode,
                  selected: _selectedIds.contains(backup.backupId),
                  onTap: _selectionMode
                      ? () => _toggleSelected(backup.backupId)
                      : null,
                  onLongPress: _selectionMode
                      ? null
                      : () => _enterSelectionMode(backup.backupId),
                  onRename: () => _rename(backup),
                  onDelete: () => _delete(backup),
                  dateFormatter: _formatDate,
                ),
          ],
        ),
      ),
    );
  }
}


final class _BackupCapacityCard extends StatelessWidget {
  const _BackupCapacityCard({required this.used, required this.max});

  final int used;
  final int max;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final full = used >= max;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              children: <Widget>[
                const Icon(Icons.storage_outlined),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    l10n.backupsCapacityTitle,
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                ),
                Text(l10n.backupsCapacityText(max, used)),
              ],
            ),
            const SizedBox(height: 12),
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                key: const Key('backup-capacity-progress'),
                value: max == 0 ? 0 : used / max,
                minHeight: 8,
                color: full
                    ? Theme.of(context).colorScheme.error
                    : Theme.of(context).colorScheme.primary,
                backgroundColor: Theme.of(context)
                    .colorScheme
                    .surfaceContainerHighest,
              ),
            ),
            if (full) ...<Widget>[
              const SizedBox(height: 8),
              Text(
                l10n.backupsCapacityFull,
                style: TextStyle(
                  color: Theme.of(context).colorScheme.error,
                  fontSize: 12,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

final class _BackupListItem extends StatelessWidget {
  const _BackupListItem({
    required this.backup,
    required this.selectionMode,
    required this.selected,
    required this.onTap,
    required this.onLongPress,
    required this.onRename,
    required this.onDelete,
    required this.dateFormatter,
  });

  final BackupSummary backup;
  final bool selectionMode;
  final bool selected;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final VoidCallback onRename;
  final VoidCallback onDelete;
  final String Function(DateTime) dateFormatter;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final date = dateFormatter(backup.createdAt);
    return Card(
      child: ListTile(
        key: Key('backup-item-${backup.backupId}'),
        selected: selectionMode && selected,
        tileColor: selectionMode && selected
            ? Theme.of(context).colorScheme.secondaryContainer.withValues(
                  alpha: 0.3,
                )
            : null,
        leading: selectionMode
            ? Checkbox(
                key: Key('backup-item-checkbox-${backup.backupId}'),
                value: selected,
                onChanged: (_) => onTap?.call(),
              )
            : Icon(
                backup.isReady
                    ? Icons.cloud_done_outlined
                    : Icons.cloud_upload_outlined,
              ),
        title: Text(backup.name),
        subtitle: Text(
          l10n.backupsItemSubtitle(
            date,
            backup.operationCount,
            formatBackupBytes(backup.sizeBytes),
          ),
        ),
        trailing: selectionMode
            ? null
            : PopupMenuButton<String>(
                key: const Key('backup-item-menu'),
                onSelected: (value) {
                  if (value == 'rename') {
                    onRename();
                  } else if (value == 'delete') {
                    onDelete();
                  }
                },
                itemBuilder: (context) => <PopupMenuEntry<String>>[
                  PopupMenuItem<String>(
                    key: const Key('backup-rename-action'),
                    value: 'rename',
                    child: Text(l10n.backupsRename),
                  ),
                  PopupMenuItem<String>(
                    key: const Key('backup-delete-action'),
                    value: 'delete',
                    child: Text(l10n.backupsDelete),
                  ),
                ],
              ),
        onTap: onTap,
        onLongPress: onLongPress,
      ),
    );
  }
}

final class _BackupsSelectionBar extends StatelessWidget {
  const _BackupsSelectionBar({
    required this.selectedCount,
    required this.allSelected,
    required this.deleting,
    required this.onSelectAll,
    required this.onDelete,
    required this.onCancel,
  });

  final int selectedCount;
  final bool allSelected;
  final bool deleting;
  final VoidCallback onSelectAll;
  final VoidCallback onDelete;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return IgnorePointer(
      ignoring: deleting,
      child: AnimatedOpacity(
        opacity: deleting ? 0.5 : 1,
        duration: const Duration(milliseconds: 150),
        child: Row(
          children: <Widget>[
            TextButton(
              key: const Key('backup-select-all-button'),
              onPressed: onSelectAll,
              child: Text(
                allSelected ? l10n.backupsSelectNone : l10n.backupsSelectAll,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: FilledButton.icon(
                key: const Key('backup-batch-delete-button'),
                onPressed: selectedCount == 0 || deleting ? null : onDelete,
                icon: deleting
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.delete_outline),
                label: Text(l10n.backupsDeleteSelected(selectedCount)),
              ),
            ),
            const SizedBox(width: 8),
            TextButton(
              key: const Key('backup-selection-cancel-button'),
              onPressed: deleting ? null : onCancel,
              child: Text(l10n.commonCancel),
            ),
          ],
        ),
      ),
    );
  }
}

final class _BackupsEmptyState extends StatelessWidget {
  const _BackupsEmptyState();

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Padding(
      padding: const EdgeInsets.only(top: 64),
      child: Column(
        key: const Key('backups-empty-state'),
        children: <Widget>[
          const Icon(Icons.cloud_outlined, size: 48),
          const SizedBox(height: 12),
          Text(l10n.backupsEmpty),
          const SizedBox(height: 4),
          Text(
            l10n.backupsEmptyHint,
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ),
    );
  }
}

final class _BackupsErrorState extends StatelessWidget {
  const _BackupsErrorState({required this.offline, required this.onRetry});

  final bool offline;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Center(
      child: Column(
        key: const Key('backups-error-state'),
        mainAxisAlignment: MainAxisAlignment.center,
        children: <Widget>[
          const Icon(Icons.error_outline, size: 48),
          const SizedBox(height: 12),
          Text(offline ? l10n.backupsLoadFailedOffline : l10n.backupsLoadFailed),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            key: const Key('backups-retry-button'),
            onPressed: onRetry,
            icon: const Icon(Icons.refresh),
            label: Text(l10n.backupsRetry),
          ),
        ],
      ),
    );
  }
}
