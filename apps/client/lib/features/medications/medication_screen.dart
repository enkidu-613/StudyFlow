import 'package:flutter/material.dart';
import 'package:studyflow/app/studyflow_workspace.dart';
import 'package:studyflow/features/medications/medication_reminder_times.dart';
import 'package:studyflow/util/uuid.dart';
import 'package:studyflow/widgets/confirm_delete_dialog.dart';
import 'package:studyflow_domain/domain.dart';

final class MedicationScreen extends StatefulWidget {
  const MedicationScreen({required this.workspace, super.key});

  final StudyFlowWorkspace workspace;

  @override
  State<MedicationScreen> createState() => _MedicationScreenState();
}

final class _MedicationScreenState extends State<MedicationScreen> {
  List<MedicationPlan> _plans = const <MedicationPlan>[];
  List<MedicationDoseRecord> _records = const <MedicationDoseRecord>[];
  Object? _error;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() async {
    try {
      final plans = await widget.workspace.medications.listPlans();
      final records = await widget.workspace.medications.listDoseRecords();
      if (mounted) {
        setState(() {
          _plans = plans;
          _records = records;
          _error = null;
        });
      }
    } on Object catch (error) {
      if (mounted) setState(() => _error = error);
    }
  }

  Future<void> _openPlanEditor([MedicationPlan? existing]) async {
    final plan = await showModalBottomSheet<MedicationPlan>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _MedicationPlanEditor(plan: existing),
    );
    if (plan == null) return;
    await widget.workspace.medications
        .savePlan(plan, write: await widget.workspace.nextWrite());
    await widget.workspace.medicationAlarms.upsert(plan);
    await _refresh();
  }

  Future<void> _deletePlan(MedicationPlan plan) async {
    try {
      await widget.workspace.medications.deletePlan(
        plan.id,
        write: await widget.workspace.nextWrite(),
      );
      await widget.workspace.medicationAlarms.cancel(plan.id);
      if (!mounted) return;
      setState(
          () => _plans = _plans.where((item) => item.id != plan.id).toList());
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(const SnackBar(content: Text('药物计划已删除，未来提醒已取消。')));
    } on Object catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(SnackBar(content: Text('删除药物计划失败：$error')));
        await _refresh();
      }
    }
  }

  Future<bool> _confirmDeletePlan(MedicationPlan plan) =>
      showDeleteConfirmationDialog(
        context,
        title: '删除药物计划？',
        body: '删除“${plan.name}”后，尚未触发的提醒也会一并取消。',
        confirmKey: 'medication-plan-delete-dialog',
      );

  Future<void> _recordDose(MedicationPlan plan, DateTime plannedAt) async {
    final outcome = await showDialog<MedicationDoseOutcome>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('${plan.name} · ${plan.dose}'),
        content: const Text('请如实记录本次情况；用药问题请查看医嘱并联系医生或药师。'),
        actions: <Widget>[
          TextButton(
              onPressed: () =>
                  Navigator.pop(context, MedicationDoseOutcome.skipped),
              child: const Text('跳过')),
          TextButton(
              onPressed: () =>
                  Navigator.pop(context, MedicationDoseOutcome.delayed),
              child: const Text('延后')),
          FilledButton(
              onPressed: () =>
                  Navigator.pop(context, MedicationDoseOutcome.taken),
              child: const Text('已服')),
        ],
      ),
    );
    if (outcome == null) return;
    final now = DateTime.now();
    await widget.workspace.medications.saveDoseRecord(
      MedicationDoseRecord(
        id: newUuidV4(),
        medicationPlanId: plan.id,
        plannedAt: plannedAt,
        outcome: outcome,
        recordedAt: now,
        delayedUntil: outcome == MedicationDoseOutcome.delayed
            ? now.add(const Duration(minutes: 30))
            : null,
      ),
      write: await widget.workspace.nextWrite(),
    );
    if (outcome == MedicationDoseOutcome.taken) {
      // 已确认服用：重排闹钟，让该时间点不再响铃、震动或弹窗。
      await widget.workspace.medicationAlarms.upsert(plan);
    }
    await _refresh();
  }

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final planned = <({MedicationPlan plan, DateTime at})>[];
    for (final plan in _plans.where((plan) => plan.enabled)) {
      for (final at in plan.occurrencesBetween(
          DateTime(now.year, now.month, now.day).toUtc(),
          DateTime(now.year, now.month, now.day + 1).toUtc())) {
        if (!_records.any((record) =>
            record.medicationPlanId == plan.id &&
            record.plannedAt.isAtSameMomentAs(at))) {
          planned.add((plan: plan, at: at));
        }
      }
    }
    planned.sort((a, b) => a.at.compareTo(b.at));
    return Scaffold(
      appBar: AppBar(title: const Text('药物')),
      floatingActionButton: FloatingActionButton(
        onPressed: _openPlanEditor,
        tooltip: '添加药物计划',
        child: const Icon(Icons.add),
      ),
      body: RefreshIndicator(
        onRefresh: _refresh,
        child: ListView(padding: const EdgeInsets.all(16), children: <Widget>[
          if (_error != null)
            ListTile(
                leading: const Icon(Icons.error_outline),
                title: Text('$_error')),
          Text('今日待服', style: Theme.of(context).textTheme.titleLarge),
          if (planned.isEmpty)
            const Card(child: ListTile(title: Text('今天没有待确认的服药提醒。'))),
          for (final item in planned)
            Card(
                child: ListTile(
              leading: const Icon(Icons.medication_outlined),
              title: Text('${item.plan.name} · ${item.plan.dose}'),
              subtitle: Text(
                  '${item.at.toLocal().hour.toString().padLeft(2, '0')}:${item.at.toLocal().minute.toString().padLeft(2, '0')} · ${item.plan.strength}'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => _recordDose(item.plan, item.at),
            )),
          const SizedBox(height: 16),
          Text('药物计划', style: Theme.of(context).textTheme.titleLarge),
          if (_plans.isEmpty)
            const Card(
                child: ListTile(
                    title: Text('尚未添加药物计划'),
                    subtitle: Text('请根据已确认的医嘱手动填写；不要自行推断剂量或频次。'))),
          for (final plan in _plans)
            _SwipeablePlanCard(
              plan: plan,
              onEdit: () => _openPlanEditor(plan),
              onConfirmDelete: () => _confirmDeletePlan(plan),
              onDelete: () => _deletePlan(plan),
            ),
          const SizedBox(height: 16),
          Text('最近记录', style: Theme.of(context).textTheme.titleLarge),
          for (final record in _records.take(10)) _recordTile(record),
        ]),
      ),
    );
  }
  Widget _recordTile(MedicationDoseRecord record) {
    final plan = _planFor(record.medicationPlanId);
    final name = plan?.name ?? '未知药物';
    final local = record.recordedAt.toLocal();
    final day = DateTime(local.year, local.month, local.day);
    final countInDay = _records
        .where((item) {
          if (item.medicationPlanId != record.medicationPlanId) {
            return false;
          }
          final itemLocal = item.recordedAt.toLocal();
          final itemDay =
              DateTime(itemLocal.year, itemLocal.month, itemLocal.day);
          return itemDay.isAtSameMomentAs(day) &&
              !item.recordedAt.isAfter(record.recordedAt);
        })
        .length;
    return ListTile(
      leading: const Icon(Icons.history_outlined),
      title: Text('${_outcomeLabel(record.outcome)} · $name · 今日第 $countInDay 次'),
      subtitle: Text(record.recordedAt.toLocal().toString()),
    );
  }

  MedicationPlan? _planFor(String id) {
    for (final plan in _plans) {
      if (plan.id == id) {
        return plan;
      }
    }
    return null;
  }
}

String _outcomeLabel(MedicationDoseOutcome outcome) => switch (outcome) {
      MedicationDoseOutcome.taken => '已服',
      MedicationDoseOutcome.skipped => '跳过',
      MedicationDoseOutcome.delayed => '已延后',
    };

/// 药物计划卡片：长按卡片，删除按钮从右侧滑出；
/// 点击按钮弹出删除确认，确认后才删除。
final class _SwipeablePlanCard extends StatefulWidget {
  const _SwipeablePlanCard({
    required this.plan,
    required this.onEdit,
    required this.onConfirmDelete,
    required this.onDelete,
  });

  final MedicationPlan plan;
  final VoidCallback onEdit;
  final Future<bool> Function() onConfirmDelete;
  final Future<void> Function() onDelete;

  @override
  State<_SwipeablePlanCard> createState() => _SwipeablePlanCardState();
}

final class _SwipeablePlanCardState extends State<_SwipeablePlanCard> {
  static const double _revealWidth = 80;

  bool _revealed = false;

  Future<void> _handleDeleteTap() async {
    if (!(await widget.onConfirmDelete())) return;
    if (mounted) setState(() => _revealed = false);
    await widget.onDelete();
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Stack(
        children: <Widget>[
          Positioned.fill(
            child: Padding(
              padding: const EdgeInsets.only(right: 4),
              child: Align(
                alignment: Alignment.centerRight,
                child: Material(
                  color: colors.error,
                  borderRadius: BorderRadius.circular(12),
                  clipBehavior: Clip.antiAlias,
                  child: InkWell(
                    key: const Key('medication-plan-delete-button'),
                    onTap: _handleDeleteTap,
                    child: SizedBox(
                      width: _revealWidth - 8,
                      height: 44,
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: <Widget>[
                          Icon(Icons.delete_outline, color: colors.onError),
                          Text('删除',
                              style: TextStyle(
                                  color: colors.onError, fontSize: 12)),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
          TweenAnimationBuilder<double>(
            tween: Tween<double>(
              begin: 0,
              end: _revealed ? _revealWidth : 0,
            ),
            duration: const Duration(milliseconds: 200),
            curve: Curves.easeOutCubic,
            builder: (context, extent, child) => Transform.translate(
              offset: Offset(-extent, 0),
              child: child,
            ),
            child: Card(
              child: ListTile(
                key: const Key('medication-plan-card'),
                onLongPress: () =>
                    setState(() => _revealed = !_revealed),
                leading: Icon(widget.plan.enabled
                    ? Icons.medication
                    : Icons.medication_outlined),
                title: Text(widget.plan.name),
                subtitle: Text(
                    '${widget.plan.strength} · 每次 ${widget.plan.dose} · ${widget.plan.reminderTimes.map((time) => '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}').join('、')}'),
                trailing: const Icon(Icons.edit_outlined),
                onTap: () {
                  if (_revealed) {
                    setState(() => _revealed = false);
                    return;
                  }
                  widget.onEdit();
                },
              ),
            ),
          ),
        ],
      ),
    );
  }
}

final class _MedicationPlanEditor extends StatefulWidget {
  const _MedicationPlanEditor({this.plan});

  final MedicationPlan? plan;

  @override
  State<_MedicationPlanEditor> createState() => _MedicationPlanEditorState();
}

final class _MedicationPlanEditorState extends State<_MedicationPlanEditor> {
  final _formKey = GlobalKey<FormState>();
  late final _name = TextEditingController(text: widget.plan?.name ?? '');
  late final _strength =
      TextEditingController(text: widget.plan?.strength ?? '');
  late final _dose = TextEditingController(text: widget.plan?.dose ?? '');
  late final List<TextEditingController> _timeControllers = [
    for (final time in widget.plan?.reminderTimes ??
        const <MedicationTime>[MedicationTime(hour: 9, minute: 0)])
      TextEditingController(text: _formatMedicationTime(time)),
  ];
  late final _reminderCount = TextEditingController(
    text: '${widget.plan?.reminderTimes.length ?? 1}',
  );
  late final _intervalDays = TextEditingController(
    text: '${widget.plan?.intervalDays ?? 1}',
  );
  @override
  void dispose() {
    _name.dispose();
    _strength.dispose();
    _dose.dispose();
    for (final controller in _timeControllers) {
      controller.dispose();
    }
    _reminderCount.dispose();
    _intervalDays.dispose();
    super.dispose();
  }

  void _resizeTimeControllers(String value) {
    final count = int.tryParse(value);
    if (count == null || count < 1 || count > 24) return;
    final current = <MedicationTime>[];
    for (final controller in _timeControllers) {
      final parsed = _parseMedicationTime(controller.text);
      if (parsed != null) current.add(parsed);
    }
    final resized = resizeMedicationReminderTimes(count, current);
    while (_timeControllers.length > count) {
      _timeControllers.removeLast().dispose();
    }
    while (_timeControllers.length < count) {
      final index = _timeControllers.length;
      _timeControllers.add(
        TextEditingController(text: _formatMedicationTime(resized[index])),
      );
    }
    for (var index = 0; index < _timeControllers.length; index++) {
      if (_parseMedicationTime(_timeControllers[index].text) == null) {
        _timeControllers[index].text = _formatMedicationTime(resized[index]);
      }
    }
    setState(() {});
  }

  void _save() {
    if (!_formKey.currentState!.validate()) return;
    final reminderTimes = <MedicationTime>[];
    for (var index = 0; index < _timeControllers.length; index++) {
      final time = _parseMedicationTime(_timeControllers[index].text);
      if (time == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('第 ${index + 1} 个提醒时间格式应为 HH:MM。')),
        );
        return;
      }
      reminderTimes.add(time);
    }
    final intervalDays = int.tryParse(_intervalDays.text);
    if (intervalDays == null || intervalDays < 1) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('周期天数必须是大于 0 的整数。')));
      return;
    }
    final now = DateTime.now();
    final existing = widget.plan;
    Navigator.pop(
        context,
        MedicationPlan(
            id: existing?.id ?? newUuidV4(),
            name: _name.text,
            strength: _strength.text,
            dose: _dose.text,
            frequency: intervalDays == 1
                ? MedicationFrequency.daily
                : MedicationFrequency.everyNDays,
            intervalDays: intervalDays,
            reminderTimes: reminderTimes,
            startDate: existing?.startDate ?? now,
            enabled: existing?.enabled ?? true,
            createdAt: existing?.createdAt ?? now,
            updatedAt: now,
            note: existing?.note));
  }

  @override
  Widget build(BuildContext context) => SafeArea(
      child: Padding(
          padding: EdgeInsets.only(
              left: 24,
              right: 24,
              top: 24,
              bottom: MediaQuery.viewInsetsOf(context).bottom + 24),
          child: SingleChildScrollView(
              child: Form(
                  key: _formKey,
                  child:
                      Column(mainAxisSize: MainAxisSize.min, children: <Widget>[
                    Text(widget.plan == null ? '添加药物计划' : '编辑药物计划',
                        style: Theme.of(context).textTheme.titleLarge),
                    const SizedBox(height: 12),
                    const Text('请按已确认医嘱填写；本应用不会提供剂量、补服或相互作用建议。'),
                    TextFormField(
                        controller: _name,
                        decoration: const InputDecoration(labelText: '药品名称'),
                        validator: _required),
                    TextFormField(
                        controller: _strength,
                        decoration:
                            const InputDecoration(labelText: '规格（例如 10 mg/片）'),
                        validator: _required),
                    TextFormField(
                        controller: _dose,
                        decoration:
                            const InputDecoration(labelText: '每次用量（例如 1 片）'),
                        validator: _required),
                    TextFormField(
                      key: const Key('medication-reminder-count-field'),
                      controller: _reminderCount,
                      decoration: const InputDecoration(
                        labelText: '每日服用次数',
                        helperText: '例如填 3，就会生成 3 个每日提醒时间。',
                      ),
                      keyboardType: TextInputType.number,
                      onChanged: _resizeTimeControllers,
                      validator: _positiveCount,
                    ),
                    for (var index = 0;
                        index < _timeControllers.length;
                        index++)
                      TextFormField(
                        key:
                            ValueKey<String>('medication-reminder-time-$index'),
                        controller: _timeControllers[index],
                        decoration: InputDecoration(
                          labelText: '提醒时间 ${index + 1}（HH:MM）',
                        ),
                        keyboardType: TextInputType.datetime,
                        validator: _required,
                      ),
                    TextFormField(
                      key: const Key('medication-interval-field'),
                      controller: _intervalDays,
                      decoration: const InputDecoration(
                        labelText: '每隔几天服用（每日填 1，隔天填 2）',
                      ),
                      keyboardType: TextInputType.number,
                      validator: _required,
                    ),
                    const SizedBox(height: 16),
                    FilledButton(
                        onPressed: _save,
                        child: Text(widget.plan == null ? '确认并创建提醒' : '保存修改')),
                  ])))));
}

String? _required(String? value) =>
    value == null || value.trim().isEmpty ? '此项必填' : null;

String? _positiveCount(String? value) {
  final count = int.tryParse(value?.trim() ?? '');
  return count == null || count < 1 || count > 24 ? '请输入 1–24 之间的整数' : null;
}

MedicationTime? _parseMedicationTime(String value) {
  final match = RegExp(r'^(\d{1,2}):(\d{1,2})$').firstMatch(value.trim());
  if (match == null) return null;
  final hour = int.tryParse(match.group(1)!);
  final minute = int.tryParse(match.group(2)!);
  if (hour == null || minute == null || hour > 23 || minute > 59) return null;
  return MedicationTime(hour: hour, minute: minute);
}

String _formatMedicationTime(MedicationTime time) =>
    '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}';
