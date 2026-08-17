import 'package:flutter/material.dart';
import 'package:studyflow/app/studyflow_workspace.dart';
import 'package:studyflow/l10n/l10n_extension.dart';
import 'package:studyflow/util/uuid.dart';
import 'package:studyflow_domain/domain.dart';

/// Standalone check-in flow: records sleep, energy, mood, and feedback so the
/// schedule policy can propose small, confirmed sleep-window adjustments.
final class CheckInScreen extends StatefulWidget {
  const CheckInScreen({required this.workspace, super.key});

  final StudyFlowWorkspace workspace;

  @override
  State<CheckInScreen> createState() => _CheckInScreenState();
}

final class _CheckInScreenState extends State<CheckInScreen> {
  List<CheckIn> _checkIns = <CheckIn>[];
  Object? _error;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() async {
    try {
      final checkIns = await widget.workspace.checkIns.list();
      if (!mounted) {
        return;
      }
      setState(() {
        _checkIns = checkIns;
        _error = null;
        _loading = false;
      });
    } on Object catch (error) {
      if (mounted) {
        setState(() {
          _error = error;
          _loading = false;
        });
      }
    }
  }

  Future<void> _openEditor() async {
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
    final l10n = context.l10n;
    return Scaffold(
      appBar: AppBar(title: Text(l10n.homeCheckIn)),
      body: RefreshIndicator(
        onRefresh: _refresh,
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : ListView(
                padding: const EdgeInsets.symmetric(vertical: 8),
                children: <Widget>[
                  if (_error != null)
                    ListTile(
                      leading: const Icon(Icons.error_outline),
                      title: Text('$_error'),
                    ),
                  for (final checkIn in _checkIns)
                    Card(
                      child: ListTile(
                        leading: const Icon(Icons.bedtime_outlined),
                        title: Text(
                          l10n.checkInRowTitle(
                            checkIn.energy,
                            checkIn.sleepMinutes,
                          ),
                        ),
                        subtitle: Text(_format(checkIn.recordedAt)),
                        trailing: _RatingDots(
                          value: checkIn.sleepQuality,
                        ),
                      ),
                    ),
                  if (_checkIns.isEmpty && _error == null)
                    Padding(
                      padding: const EdgeInsets.all(32),
                      child: Center(child: Text(l10n.checkInsEmpty)),
                    ),
                ],
              ),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _openEditor,
        tooltip: l10n.checkInNew,
        child: const Icon(Icons.add),
      ),
    );
  }

  String _format(DateTime value) {
    final local = value.toLocal();
    return '${local.month}/${local.day} '
        '${local.hour.toString().padLeft(2, '0')}:'
        '${local.minute.toString().padLeft(2, '0')}';
  }
}

final class _RatingDots extends StatelessWidget {
  const _RatingDots({required this.value});

  final int value;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        for (var dot = 0; dot < 5; dot++)
          Icon(
            dot < value ? Icons.circle : Icons.circle_outlined,
            size: 12,
            color: dot < value
                ? Theme.of(context).colorScheme.primary
                : Theme.of(context).disabledColor,
          ),
      ],
    );
  }
}

final class CheckInDialog extends StatefulWidget {
  const CheckInDialog({super.key});

  @override
  State<CheckInDialog> createState() => _CheckInDialogState();
}

final class _CheckInDialogState extends State<CheckInDialog> {
  final _feedbackController = TextEditingController();
  double _sleepQuality = 3;
  double _energy = 3;
  double _mood = 3;
  String? _error;
  late TimeOfDay _sleepStart;
  late TimeOfDay _sleepEnd;

  @override
  void initState() {
    super.initState();
    final now = TimeOfDay.now();
    _sleepEnd = now;
    _sleepStart = TimeOfDay(hour: (now.hour + 16) % 24, minute: now.minute);
  }

  @override
  void dispose() {
    _feedbackController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final duration = _sleepDuration();
    return AlertDialog(
      title: Text(l10n.checkInNew),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            ListTile(
              key: const Key('check-in-sleep-start'),
              title: const Text('入睡时间'),
              trailing: Text(_sleepStart.format(context)),
              onTap: () => _pickTime(start: true),
            ),
            ListTile(
              key: const Key('check-in-sleep-end'),
              title: const Text('起床时间'),
              trailing: Text(_sleepEnd.format(context)),
              onTap: () => _pickTime(start: false),
            ),
            Text(
                '自动计算：${duration.inHours} 小时 ${duration.inMinutes.remainder(60)} 分钟'),
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
              key: const Key('check-in-feedback-field'),
              controller: _feedbackController,
              maxLines: 3,
              decoration: InputDecoration(labelText: l10n.checkInFeedback),
            ),
            if (_error != null) Text(_error!),
          ],
        ),
      ),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l10n.commonCancel),
        ),
        FilledButton(
          key: const Key('save-check-in-button'),
          onPressed: _save,
          child: Text(l10n.commonSave),
        ),
      ],
    );
  }

  Future<void> _save() async {
    final now = DateTime.now();
    final start = DateTime(
        now.year, now.month, now.day, _sleepStart.hour, _sleepStart.minute);
    var end = DateTime(
        now.year, now.month, now.day, _sleepEnd.hour, _sleepEnd.minute);
    if (!end.isAfter(start)) end = end.add(const Duration(days: 1));
    final duration = end.difference(start);
    Navigator.of(context).pop(
      CheckIn(
        id: newUuidV4(),
        recordedAt: DateTime.now(),
        sleepMinutes: duration.inMinutes,
        sleepQuality: _sleepQuality.round(),
        energy: _energy.round(),
        mood: _mood.round(),
        feedback: _feedbackController.text.trim(),
        sleepStartedAt: start,
        sleepEndedAt: end,
      ),
    );
  }

  Duration _sleepDuration() {
    final start = _sleepStart.hour * 60 + _sleepStart.minute;
    var end = _sleepEnd.hour * 60 + _sleepEnd.minute;
    if (end <= start) end += 24 * 60;
    return Duration(minutes: end - start);
  }

  Future<void> _pickTime({required bool start}) async {
    final selected = await showTimePicker(
      context: context,
      initialTime: start ? _sleepStart : _sleepEnd,
    );
    if (selected != null && mounted) {
      setState(() {
        if (start) {
          _sleepStart = selected;
        } else {
          _sleepEnd = selected;
        }
      });
    }
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
