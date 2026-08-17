import 'package:flutter/material.dart';
import 'package:studyflow/app/studyflow_workspace.dart';
import 'package:studyflow/util/uuid.dart';
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
    await _refresh();
  }

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
            Card(
                child: ListTile(
              leading: Icon(
                  plan.enabled ? Icons.medication : Icons.medication_outlined),
              title: Text(plan.name),
              subtitle: Text(
                  '${plan.strength} · 每次 ${plan.dose} · ${plan.reminderTimes.map((time) => '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}').join('、')}'),
              trailing: const Icon(Icons.edit_outlined),
              onTap: () => _openPlanEditor(plan),
            )),
          const SizedBox(height: 16),
          Text('最近记录', style: Theme.of(context).textTheme.titleLarge),
          for (final record in _records.take(10))
            ListTile(
              leading: const Icon(Icons.history_outlined),
              title: Text(_outcomeLabel(record.outcome)),
              subtitle: Text(record.recordedAt.toLocal().toString()),
            ),
        ]),
      ),
    );
  }
}

String _outcomeLabel(MedicationDoseOutcome outcome) => switch (outcome) {
      MedicationDoseOutcome.taken => '已服',
      MedicationDoseOutcome.skipped => '跳过',
      MedicationDoseOutcome.delayed => '已延后',
    };

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
  late final _time = TextEditingController(
    text: widget.plan == null
        ? '09:00'
        : '${widget.plan!.reminderTimes.first.hour.toString().padLeft(2, '0')}:${widget.plan!.reminderTimes.first.minute.toString().padLeft(2, '0')}',
  );
  late final _intervalDays = TextEditingController(
    text: '${widget.plan?.intervalDays ?? 1}',
  );
  @override
  void dispose() {
    _name.dispose();
    _strength.dispose();
    _dose.dispose();
    _time.dispose();
    _intervalDays.dispose();
    super.dispose();
  }

  void _save() {
    if (!_formKey.currentState!.validate()) return;
    final parts = _time.text.split(':');
    final hour = int.tryParse(parts.first);
    final minute = parts.length == 2 ? int.tryParse(parts.last) : null;
    final intervalDays = int.tryParse(_intervalDays.text);
    if (hour == null || minute == null || hour > 23 || minute > 59) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('提醒时间格式应为 HH:MM。')));
      return;
    }
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
            reminderTimes: <MedicationTime>[
              MedicationTime(hour: hour, minute: minute)
            ],
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
          child: Form(
              key: _formKey,
              child: Column(mainAxisSize: MainAxisSize.min, children: <Widget>[
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
                    controller: _time,
                    decoration:
                        const InputDecoration(labelText: '每日提醒时间（HH:MM）'),
                    keyboardType: TextInputType.datetime,
                    validator: _required),
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
              ]))));
}

String? _required(String? value) =>
    value == null || value.trim().isEmpty ? '此项必填' : null;
