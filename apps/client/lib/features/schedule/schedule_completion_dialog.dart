import 'package:flutter/material.dart';
import 'package:studyflow/features/schedule/schedule_completion_service.dart';
import 'package:studyflow_domain/domain.dart';

final class ScheduleCompletionDraft {
  const ScheduleCompletionDraft({required this.outcome, this.reason});

  final ScheduleFeedbackOutcome outcome;
  final String? reason;
}

Future<ScheduleCompletionDraft?> showScheduleCompletionDialog(
  BuildContext context,
  ScheduleCompletionEvent event,
) =>
    showDialog<ScheduleCompletionDraft>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _ScheduleCompletionDialog(event: event),
    );

final class _ScheduleCompletionDialog extends StatefulWidget {
  const _ScheduleCompletionDialog({required this.event});

  final ScheduleCompletionEvent event;

  @override
  State<_ScheduleCompletionDialog> createState() =>
      _ScheduleCompletionDialogState();
}

final class _ScheduleCompletionDialogState
    extends State<_ScheduleCompletionDialog> {
  final TextEditingController _reason = TextEditingController();
  ScheduleFeedbackOutcome _outcome = ScheduleFeedbackOutcome.completed;
  String? _error;

  @override
  void dispose() {
    _reason.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: Text(_question(widget.event.block.kind)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            SegmentedButton<ScheduleFeedbackOutcome>(
              segments: const <ButtonSegment<ScheduleFeedbackOutcome>>[
                ButtonSegment(
                  value: ScheduleFeedbackOutcome.completed,
                  label: Text('已完成'),
                ),
                ButtonSegment(
                  value: ScheduleFeedbackOutcome.notCompleted,
                  label: Text('未完成'),
                ),
              ],
              selected: <ScheduleFeedbackOutcome>{_outcome},
              onSelectionChanged: (value) =>
                  setState(() => _outcome = value.single),
            ),
            if (_outcome == ScheduleFeedbackOutcome.notCompleted) ...<Widget>[
              const SizedBox(height: 16),
              TextField(
                controller: _reason,
                minLines: 2,
                maxLines: 4,
                autofocus: true,
                decoration: InputDecoration(
                  labelText: '未完成的原因',
                  errorText: _error,
                ),
              ),
            ],
          ],
        ),
        actions: <Widget>[
          FilledButton(
            onPressed: _submit,
            child: const Text('提交'),
          ),
        ],
      );

  void _submit() {
    final reason = _reason.text.trim();
    if (_outcome == ScheduleFeedbackOutcome.notCompleted && reason.isEmpty) {
      setState(() => _error = '请填写未完成的原因');
      return;
    }
    Navigator.of(context).pop(ScheduleCompletionDraft(
      outcome: _outcome,
      reason: reason.isEmpty ? null : reason,
    ));
  }

  String _question(ScheduleBlockKind kind) => switch (kind) {
        ScheduleBlockKind.task => '这项学习/任务按计划完成了吗？',
        ScheduleBlockKind.rest => '这段休息按计划结束了吗？',
        ScheduleBlockKind.sleep => '这次睡眠按计划完成了吗？',
        ScheduleBlockKind.breakTime => '这段间歇按计划结束了吗？',
      };
}
