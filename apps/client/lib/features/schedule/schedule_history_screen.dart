import 'package:flutter/material.dart';
import 'package:studyflow/app/studyflow_workspace.dart';
import 'package:studyflow/features/schedule/schedule_history.dart';
import 'package:studyflow_domain/domain.dart';

final class ScheduleHistoryScreen extends StatefulWidget {
  const ScheduleHistoryScreen({required this.workspace, super.key});

  final StudyFlowWorkspace workspace;

  @override
  State<ScheduleHistoryScreen> createState() => _ScheduleHistoryScreenState();
}

final class _ScheduleHistoryScreenState extends State<ScheduleHistoryScreen> {
  List<ScheduleHistoryEntry> _entries = const <ScheduleHistoryEntry>[];
  DateTime? _selectedDate;
  Object? _error;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() async {
    try {
      final blocks = await widget.workspace.schedule.list();
      final feedback = await widget.workspace.scheduleFeedback.list();
      final now = DateTime.now();
      final from = now.subtract(const Duration(days: 90));
      if (!mounted) {
        return;
      }
      setState(() {
        _entries = historyEntries(
          blocks: blocks,
          feedback: feedback,
          from: from,
          until: now,
        );
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

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate ?? now,
      firstDate: now.subtract(const Duration(days: 365)),
      lastDate: now,
    );
    if (picked != null && mounted) {
      setState(() => _selectedDate = picked);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(
          title: const Text('日程历史'),
          actions: <Widget>[
            IconButton(
              key: const Key('schedule-history-date-filter'),
              tooltip: '按日期查询',
              icon: const Icon(Icons.calendar_today_outlined),
              onPressed: _pickDate,
            ),
            if (_selectedDate != null)
              IconButton(
                tooltip: '清除日期筛选',
                icon: const Icon(Icons.filter_alt_off_outlined),
                onPressed: () => setState(() => _selectedDate = null),
              ),
          ],
        ),
        body: RefreshIndicator(
          onRefresh: _refresh,
          child: _buildBody(),
        ),
      );

  Widget _buildBody() {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error != null) {
      return ListView(children: <Widget>[
        ListTile(
            leading: const Icon(Icons.error_outline), title: Text('$_error')),
      ]);
    }
    final entries = _selectedDate == null
        ? _entries
        : _entries
            .where((entry) =>
                _sameDay(entry.occurrenceEnd.toLocal(), _selectedDate!))
            .toList();
    if (entries.isEmpty) {
      return ListView(children: <Widget>[
        const SizedBox(height: 96),
        const Icon(Icons.history_outlined, size: 56),
        const SizedBox(height: 16),
        Center(child: Text(_selectedDate == null ? '还没有日程历史' : '这一天没有已结束日程')),
      ]);
    }
    return ListView.separated(
      padding: const EdgeInsets.symmetric(vertical: 8),
      itemCount: entries.length,
      separatorBuilder: (_, __) => const Divider(height: 1),
      itemBuilder: (_, index) => _HistoryTile(entry: entries[index]),
    );
  }

  bool _sameDay(DateTime left, DateTime right) =>
      left.year == right.year &&
      left.month == right.month &&
      left.day == right.day;
}

final class _HistoryTile extends StatelessWidget {
  const _HistoryTile({required this.entry});

  final ScheduleHistoryEntry entry;

  @override
  Widget build(BuildContext context) {
    final feedback = entry.feedback;
    final status = feedback == null
        ? '未确认'
        : feedback.outcome == ScheduleFeedbackOutcome.completed
            ? '已完成'
            : '未完成';
    final color = feedback == null
        ? Theme.of(context).colorScheme.outline
        : feedback.outcome == ScheduleFeedbackOutcome.completed
            ? Colors.green
            : Theme.of(context).colorScheme.error;
    final end = entry.occurrenceEnd.toLocal();
    return ListTile(
      leading: Icon(_icon(entry.block.kind)),
      title: Text(_title(entry.block)),
      subtitle: Text(
          '${end.year}/${end.month}/${end.day}  ${_time(entry.occurrenceStart)} - ${_time(entry.occurrenceEnd)}'
          '${feedback?.reason == null ? '' : '\n原因：${feedback!.reason}'}'),
      isThreeLine: feedback?.reason != null,
      trailing: Chip(label: Text(status), side: BorderSide(color: color)),
    );
  }

  String _title(ScheduleBlock block) => switch (block.kind) {
        ScheduleBlockKind.task => '学习/任务',
        ScheduleBlockKind.rest => '休息',
        ScheduleBlockKind.sleep => '睡眠',
        ScheduleBlockKind.breakTime => '间歇',
      };

  IconData _icon(ScheduleBlockKind kind) => switch (kind) {
        ScheduleBlockKind.task => Icons.checklist_outlined,
        ScheduleBlockKind.rest => Icons.weekend_outlined,
        ScheduleBlockKind.sleep => Icons.bedtime_outlined,
        ScheduleBlockKind.breakTime => Icons.coffee_outlined,
      };

  String _time(DateTime value) {
    final local = value.toLocal();
    return '${local.hour.toString().padLeft(2, '0')}:${local.minute.toString().padLeft(2, '0')}';
  }
}
