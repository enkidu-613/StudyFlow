import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:studyflow/app/studyflow_workspace.dart';
import 'package:studyflow/features/checkins/check_in_screen.dart';
import 'package:studyflow/l10n/l10n_extension.dart';
import 'package:studyflow/util/uuid.dart';
import 'package:studyflow_domain/domain.dart';
import 'package:studyflow_platform_contract/platform_contract.dart';

final class HomeScreen extends StatefulWidget {
  const HomeScreen({required this.workspace, super.key});

  final StudyFlowWorkspace workspace;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

final class _HomeData {
  const _HomeData({
    required this.taskCount,
    required this.focusCount,
    required this.pendingSync,
    required this.health,
    required this.latestCheckIn,
  });

  final int taskCount;
  final int focusCount;
  final int pendingSync;
  final PermissionHealth health;
  final CheckIn? latestCheckIn;
}

final class _HomeScreenState extends State<HomeScreen> {
  _HomeData? _data;
  Object? _error;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() async {
    try {
      final tasks = await widget.workspace.tasks.list();
      final sessions = await widget.workspace.focus.list();
      final checkIns = await widget.workspace.checkIns.list();
      final pendingSync = await widget.workspace.pendingCount();
      final health = await widget.workspace.platform.getPermissionStatus();
      if (!mounted) {
        return;
      }
      setState(() {
        _data = _HomeData(
          taskCount: tasks.length,
          focusCount: sessions.length,
          pendingSync: pendingSync,
          health: health,
          latestCheckIn: checkIns.isEmpty ? null : checkIns.first,
        );
        _error = null;
      });
    } on Object catch (error) {
      if (mounted) {
        setState(() => _error = error);
      }
    }
  }

  Future<void> _openCheckIn() async {
    final saved = await showDialog<CheckIn>(
      context: context,
      builder: (context) => const CheckInDialog(),
    );
    if (saved == null) {
      return;
    }
    await widget.workspace.checkIns.save(
      saved,
      write: await widget.workspace.nextWrite(),
    );
    await _refresh();
  }

  @override
  Widget build(BuildContext context) {
    final data = _data;
    final l10n = context.l10n;
    return Scaffold(
      appBar: AppBar(title: Text(l10n.navToday)),
      body: RefreshIndicator(
        onRefresh: _refresh,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: <Widget>[
            if (_error != null)
              Card(
                child: ListTile(
                  leading: const Icon(Icons.error_outline),
                  title: Text('$_error'),
                ),
              ),
            if (data != null) ...<Widget>[
              _SummaryGrid(
                taskCount: data.taskCount,
                focusCount: data.focusCount,
                pendingSync: data.pendingSync,
              ),
              const SizedBox(height: 16),
              Card(
                child: ListTile(
                  leading: Icon(
                    _notificationsAllowed(data.health)
                        ? Icons.notifications_active_outlined
                        : Icons.notifications_off_outlined,
                  ),
                  title: Text(l10n.homeNotifications),
                  subtitle: Text(
                    _notificationsAllowed(data.health)
                        ? l10n.homeNotifGranted
                        : l10n.homeNotifRequired,
                  ),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => context.go('/settings'),
                ),
              ),
              const SizedBox(height: 8),
              Card(
                child: ListTile(
                  leading: const Icon(Icons.fact_check_outlined),
                  title: Text(l10n.homeCheckIn),
                  trailing: const Icon(Icons.add),
                  onTap: _openCheckIn,
                ),
              ),
              if (data.latestCheckIn != null) ...<Widget>[
                const SizedBox(height: 8),
                Card(
                  child: ListTile(
                    leading: const Icon(Icons.bedtime_outlined),
                    title: Text(l10n.homeLastCheckIn),
                    subtitle: Text(
                      l10n.minutesShort(data.latestCheckIn!.sleepMinutes),
                    ),
                  ),
                ),
              ],
            ],
            const SizedBox(height: 8),
            Card(
              child: ListTile(
                key: const Key('today-ai-plan-button'),
                leading: const Icon(Icons.auto_awesome_outlined),
                title: Text(l10n.aiRecommendTitle),
                subtitle: Text(l10n.aiEnabledSubtitle),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => context.push('/ai/recommendations'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  bool _notificationsAllowed(PermissionHealth health) =>
      health.stateFor(PlatformPermissionId.notifications)?.allowed ?? false;
}

final class _SummaryGrid extends StatelessWidget {
  const _SummaryGrid({
    required this.taskCount,
    required this.focusCount,
    required this.pendingSync,
  });

  final int taskCount;
  final int focusCount;
  final int pendingSync;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: <Widget>[
        Expanded(child: _SummaryTile(icon: Icons.checklist, value: taskCount)),
        const SizedBox(width: 8),
        Expanded(child: _SummaryTile(icon: Icons.timer, value: focusCount)),
        const SizedBox(width: 8),
        Expanded(
          child: _SummaryTile(
            icon: pendingSync == 0
                ? Icons.cloud_done_outlined
                : Icons.cloud_upload_outlined,
            value: pendingSync,
          ),
        ),
      ],
    );
  }
}

final class _SummaryTile extends StatelessWidget {
  const _SummaryTile({required this.icon, required this.value});

  final IconData icon;
  final int value;

  @override
  Widget build(BuildContext context) => Card(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 18),
          child: Column(
            children: <Widget>[
              Icon(icon),
              const SizedBox(height: 8),
              Text('$value', style: Theme.of(context).textTheme.titleLarge),
            ],
          ),
        ),
      );
}

final class _CheckInDialog extends StatefulWidget {
  const _CheckInDialog();

  @override
  State<_CheckInDialog> createState() => _CheckInDialogState();
}

final class _CheckInDialogState extends State<_CheckInDialog> {
  final _sleepController = TextEditingController(text: '420');
  final _feedbackController = TextEditingController();
  double _sleepQuality = 3;
  double _energy = 3;
  double _mood = 3;

  @override
  void dispose() {
    _sleepController.dispose();
    _feedbackController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return AlertDialog(
      title: Text(l10n.checkInNew),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            TextField(
              controller: _sleepController,
              keyboardType: TextInputType.number,
              decoration: InputDecoration(
                labelText: l10n.checkInSleepMinutes,
                suffixText: l10n.minutesSuffix,
              ),
            ),
            _RatingSlider(
              label: l10n.checkInSleepQuality,
              value: _sleepQuality,
              onChanged: (value) => setState(() => _sleepQuality = value),
            ),
            _RatingSlider(
              label: l10n.checkInEnergy,
              value: _energy,
              onChanged: (value) => setState(() => _energy = value),
            ),
            _RatingSlider(
              label: l10n.checkInMood,
              value: _mood,
              onChanged: (value) => setState(() => _mood = value),
            ),
            TextField(
              controller: _feedbackController,
              maxLines: 3,
              decoration: InputDecoration(labelText: l10n.checkInFeedback),
            ),
          ],
        ),
      ),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l10n.commonCancel),
        ),
        FilledButton(
          onPressed: _save,
          child: Text(l10n.commonSave),
        ),
      ],
    );
  }

  Future<void> _save() async {
    final sleepMinutes = int.tryParse(_sleepController.text.trim());
    if (sleepMinutes == null || sleepMinutes < 0) {
      return;
    }
    Navigator.of(context).pop(
      CheckIn(
        id: newUuidV4(),
        recordedAt: DateTime.now(),
        sleepMinutes: sleepMinutes,
        sleepQuality: _sleepQuality.round(),
        energy: _energy.round(),
        mood: _mood.round(),
        feedback: _feedbackController.text.trim(),
      ),
    );
  }
}

final class _RatingSlider extends StatelessWidget {
  const _RatingSlider({
    required this.label,
    required this.value,
    required this.onChanged,
  });

  final String label;
  final double value;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) => Row(
        children: <Widget>[
          SizedBox(width: 110, child: Text(label)),
          Expanded(
            child: Slider(
              value: value,
              min: 1,
              max: 5,
              divisions: 4,
              label: value.round().toString(),
              onChanged: onChanged,
            ),
          ),
          SizedBox(width: 28, child: Text('${value.round()}')),
        ],
      );
}
