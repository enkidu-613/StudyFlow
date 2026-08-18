import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:studyflow/features/ai/ai_coach_memory.dart';
import 'package:studyflow/features/ai/ai_repository.dart';
import 'package:studyflow/features/ai/ai_workspace_change_service.dart';

/// A device-local conversation with the user's configured AI coach.
/// It never applies changes to tasks or schedule blocks automatically.
final class RecommendationScreen extends StatefulWidget {
  const RecommendationScreen({
    required this.requestReply,
    this.accountId,
    this.memoryStore,
    this.summarizeMemory,
    this.applyDrafts,
    super.key,
  });

  final Future<AiCoachReply> Function({
    required String userMessage,
    required List<AiCoachMessage> history,
    required String conversationSummary,
  }) requestReply;
  final String? accountId;
  final AiCoachMemoryStore? memoryStore;
  final Future<String> Function({
    required String existingSummary,
    required List<AiCoachMessage> messages,
  })? summarizeMemory;
  final Future<List<AiWorkspaceChangeResult>> Function(
    List<AiWorkspaceChangeDraft> drafts,
  )? applyDrafts;

  @override
  State<RecommendationScreen> createState() => _RecommendationScreenState();
}

final class _RecommendationScreenState extends State<RecommendationScreen> {
  static const _maxRememberedMessages = 40;
  static const _duplicateSubmitWindow = Duration(milliseconds: 800);
  static const _welcome = AiCoachMessage.assistant(
    '你好，我是你的 StudyFlow 学习与作息教练。你可以告诉我现在的状态、今天的安排，或直接问“我接下来该做什么？”。',
  );

  final _inputController = TextEditingController();
  final _scrollController = ScrollController();
  final List<AiCoachMessage> _messages = <AiCoachMessage>[_welcome];
  final Map<int, List<AiToolTrace>> _tracesByMessageIndex =
      <int, List<AiToolTrace>>{};
  String _summary = '';
  Object? _error;
  bool _loading = false;
  bool _sendInFlight = false;
  String? _lastSubmittedMessage;
  DateTime? _lastSubmittedAt;
  bool _restoring = true;
  List<AiWorkspaceChangeDraft> _pendingDrafts = <AiWorkspaceChangeDraft>[];
  bool _applyingDrafts = false;
  List<AiWorkspaceChangeResult>? _lastApplyResults;

  @override
  void initState() {
    super.initState();
    _restoreMemory();
  }

  @override
  void dispose() {
    _inputController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _restoreMemory() async {
    final store = widget.memoryStore;
    final accountId = widget.accountId;
    if (store == null || accountId == null) {
      if (mounted) setState(() => _restoring = false);
      return;
    }
    try {
      final memory = await store.load(accountId: accountId);
      if (!mounted) return;
      setState(() {
        _messages
          ..clear()
          ..addAll(
            memory.messages.isEmpty
                ? <AiCoachMessage>[_welcome]
                : memory.messages,
          );
        _tracesByMessageIndex.clear();
        _tracesByMessageIndex.addAll(memory.tracesByMessageIndex);
        _summary = memory.summary;
        _restoring = false;
      });
      _scrollToBottom();
    } on Object catch (error) {
      if (!mounted) return;
      setState(() {
        _error = error;
        _restoring = false;
      });
    }
  }

  Future<void> _persistMemory() async {
    final store = widget.memoryStore;
    final accountId = widget.accountId;
    if (store == null || accountId == null) return;
    final start = _messages.length > _maxRememberedMessages
        ? _messages.length - _maxRememberedMessages
        : 0;
    await store.save(
      accountId: accountId,
      memory: AiCoachMemory(
        summary: _summary,
        messages: _messages.sublist(start),
        tracesByMessageIndex: <int, List<AiToolTrace>>{
          for (final entry in _tracesByMessageIndex.entries)
            if (entry.key >= start) entry.key - start: entry.value,
        },
      ),
    );
  }

  Future<void> _compactMemoryIfNeeded() async {
    if (_messages.length + 2 <= _maxRememberedMessages) return;
    final summarize = widget.summarizeMemory;
    if (summarize == null) return;
    const compactCount = 16;
    final compactedMessages = _messages.sublist(0, compactCount);
    final summary = (await summarize(
      existingSummary: _summary,
      messages: compactedMessages,
    ))
        .trim();
    if (summary.isEmpty) {
      throw const AiSchemaFailure('AI 未返回可用的长期记忆摘要。');
    }
    if (!mounted) return;
    setState(() {
      _summary = summary;
      _messages.removeRange(0, compactCount);
      final remainingTraces = <int, List<AiToolTrace>>{
        for (final entry in _tracesByMessageIndex.entries)
          if (entry.key >= compactCount) entry.key - compactCount: entry.value,
      };
      _tracesByMessageIndex
        ..clear()
        ..addAll(remainingTraces);
    });
    await _persistMemory();
  }

  Future<void> _send([String? suggestedMessage]) async {
    final message = (suggestedMessage ?? _inputController.text).trim();
    if (message.isEmpty || _restoring || _sendInFlight) return;
    final now = DateTime.now();
    if (_lastSubmittedMessage == message &&
        _lastSubmittedAt != null &&
        now.difference(_lastSubmittedAt!) < _duplicateSubmitWindow) {
      return;
    }
    setState(() => _sendInFlight = true);
    _lastSubmittedMessage = message;
    _lastSubmittedAt = now;
    try {
      try {
        await _compactMemoryIfNeeded();
      } on Object catch (error) {
        if (mounted) setState(() => _error = error);
      }
      final history = List<AiCoachMessage>.unmodifiable(
        _messages.length > _maxRememberedMessages
            ? _messages.sublist(_messages.length - _maxRememberedMessages)
            : _messages,
      );
      setState(() {
        _messages.add(AiCoachMessage.user(message));
        _inputController.clear();
        _error = null;
        _loading = true;
      });
      _scrollToBottom();
      try {
        await _persistMemory();
      } on Object catch (error) {
        if (mounted) setState(() => _error = error);
      }
      try {
        final reply = await widget.requestReply(
          userMessage: message,
          history: history,
          conversationSummary: _summary,
        );
        if (!mounted) return;
        setState(() {
          final assistantMessageIndex = _messages.length;
          _messages.add(AiCoachMessage.assistant(reply.content));
          if (reply.traces.isNotEmpty) {
            _tracesByMessageIndex[assistantMessageIndex] = reply.traces;
          }
          // A follow-up such as “草案好了吗？” is an ordinary chat reply and
          // normally has no drafts of its own. Keep the earlier, explicitly
          // generated draft available until the user applies it (or a newer
          // draft deliberately replaces it).
          if (reply.drafts.isNotEmpty) {
            _pendingDrafts = reply.drafts;
          }
          _loading = false;
        });
        try {
          await _persistMemory();
        } on Object catch (error) {
          if (mounted) setState(() => _error = error);
        }
      } on Object catch (error) {
        if (!mounted) return;
        setState(() {
          _error = error;
          _loading = false;
        });
      }
      _scrollToBottom();
    } finally {
      if (mounted) {
        setState(() => _sendInFlight = false);
      } else {
        _sendInFlight = false;
      }
    }
  }

  Future<void> _applyDrafts() async {
    final apply = widget.applyDrafts;
    if (apply == null || _pendingDrafts.isEmpty || _applyingDrafts) return;
    setState(() => _applyingDrafts = true);
    try {
      final results = await apply(_pendingDrafts);
      if (!mounted) return;
      final failures = results.where((result) => !result.succeeded).toList();
      final succeeded = results.length - failures.length;
      final resultMessage = failures.isEmpty
          ? '已成功应用 $succeeded 项变更。'
          : succeeded == 0
              ? '未能应用 ${failures.length} 项变更，请检查后重试。'
              : '已成功应用 $succeeded 项变更；另有 ${failures.length} 项未能应用。';
      setState(() {
        _lastApplyResults = results;
        final messageIndex = _messages.length;
        _messages.add(AiCoachMessage.assistant(resultMessage));
        _tracesByMessageIndex[messageIndex] = <AiToolTrace>[
          AiToolTrace(
            toolName: 'apply_workspace_changes',
            label: '应用已确认的变更',
            summary: resultMessage,
          ),
        ];
        _pendingDrafts = failures.map((result) => result.draft).toList();
        _error = failures.isEmpty ? null : failures.first.error;
      });
      try {
        await _persistMemory();
      } on Object catch (error) {
        if (mounted) setState(() => _error = error);
      }
    } on Object catch (error) {
      if (!mounted) return;
      setState(() {
        final messageIndex = _messages.length;
        _messages.add(const AiCoachMessage.assistant('应用变更时发生错误，未确认成功。'));
        _tracesByMessageIndex[messageIndex] = <AiToolTrace>[
          const AiToolTrace(
            toolName: 'apply_workspace_changes',
            label: '应用已确认的变更',
            summary: '执行过程发生错误，草案仍保留，可稍后重试。',
          ),
        ];
        _error = error;
      });
    } finally {
      if (mounted) setState(() => _applyingDrafts = false);
      _scrollToBottom();
    }
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('AI 学习教练')),
        body: SafeArea(
          child: Column(
            children: <Widget>[
              Expanded(
                child: ListView(
                  controller: _scrollController,
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                  children: <Widget>[
                    for (final entry in _messages.asMap().entries)
                      _ChatBubble(
                        message: entry.value,
                        traces: _tracesByMessageIndex[entry.key] ??
                            const <AiToolTrace>[],
                        showExecutionDetails: entry.key > 0 &&
                            entry.value.role == AiCoachRole.assistant,
                      ),
                    if (_pendingDrafts.isNotEmpty)
                      _WorkspaceChangeCard(
                        drafts: _pendingDrafts,
                        applying: _applyingDrafts,
                        onApply: _applyDrafts,
                      ),
                    if (_lastApplyResults != null && !_applyingDrafts)
                      _ApplyResultCard(results: _lastApplyResults!),
                    if (_loading)
                      const _ChatBubble(
                        message: AiCoachMessage.assistant('正在分析你的学习与日程…'),
                        isLoading: true,
                      ),
                    if (_error != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: Text(
                          '暂时无法获取回复：$_error',
                          style: TextStyle(
                            color: Theme.of(context).colorScheme.error,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: Row(
                  children: <Widget>[
                    for (final prompt in const <String>[
                      '我接下来该做什么？',
                      '帮我安排今天的学习',
                      '我现在很累，怎么调整？',
                    ])
                      Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: ActionChip(
                          label: Text(prompt),
                          onPressed: _loading ||
                                  _restoring ||
                                  _sendInFlight ||
                                  _applyingDrafts
                              ? null
                              : () => _send(prompt),
                        ),
                      ),
                  ],
                ),
              ),
              _Composer(
                controller: _inputController,
                enabled: !_loading &&
                    !_restoring &&
                    !_sendInFlight &&
                    !_applyingDrafts,
                onSend: _send,
              ),
            ],
          ),
        ),
      );
}

final class _ChatBubble extends StatelessWidget {
  const _ChatBubble({
    required this.message,
    this.traces = const <AiToolTrace>[],
    this.showExecutionDetails = false,
    this.isLoading = false,
  });

  final AiCoachMessage message;
  final List<AiToolTrace> traces;
  final bool showExecutionDetails;
  final bool isLoading;

  @override
  Widget build(BuildContext context) {
    final isUser = message.role == AiCoachRole.user;
    final colors = Theme.of(context).colorScheme;
    return Align(
      alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        constraints: const BoxConstraints(maxWidth: 680),
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color:
              isUser ? colors.primaryContainer : colors.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(16),
        ),
        child: isLoading
            ? Row(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  const SizedBox(
                    height: 16,
                    width: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                  const SizedBox(width: 10),
                  Text(message.content),
                ],
              )
            : isUser
                ? Text(message.content)
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      if (showExecutionDetails) ...<Widget>[
                        _ExecutionDetails(traces: traces),
                        const SizedBox(height: 10),
                      ],
                      MarkdownBody(
                        data: message.content,
                        selectable: true,
                        styleSheet:
                            MarkdownStyleSheet.fromTheme(Theme.of(context))
                                .copyWith(
                          p: Theme.of(context).textTheme.bodyLarge,
                        ),
                      ),
                    ],
                  ),
      ),
    );
  }
}

final class _ExecutionDetails extends StatelessWidget {
  const _ExecutionDetails({required this.traces});

  final List<AiToolTrace> traces;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: colors.surfaceContainerLow,
        border: Border.all(color: colors.outlineVariant),
        borderRadius: BorderRadius.circular(12),
      ),
      child: ExpansionTile(
        key: const Key('ai-execution-details'),
        title: Text(traces.isEmpty
            ? '执行详情 · 未调用工具'
            : '执行详情 · 已调用 ${traces.length} 个工具'),
        subtitle:
            Text(traces.isEmpty ? '本条回复未读取实时数据。' : '展示可审计的工具调用，不展示模型内部思考。'),
        shape: const RoundedRectangleBorder(),
        collapsedShape: const RoundedRectangleBorder(),
        children: <Widget>[
          if (traces.isEmpty)
            const ListTile(
              dense: true,
              leading: Icon(Icons.info_outline),
              title: Text('模型未调用任何工具'),
              subtitle: Text('涉及日程、任务、药物或当前时间的问题应先读取实时数据。'),
            ),
          for (final trace in traces)
            ListTile(
              dense: true,
              leading: Icon(Icons.check_circle_outline, color: colors.primary),
              title: Text(trace.label),
              subtitle: Text(
                [
                  if (trace.inputSummary != null) trace.inputSummary!,
                  trace.summary,
                ].join('\n'),
              ),
            ),
        ],
      ),
    );
  }
}

final class _WorkspaceChangeCard extends StatelessWidget {
  const _WorkspaceChangeCard(
      {required this.drafts, required this.applying, required this.onApply});
  final List<AiWorkspaceChangeDraft> drafts;
  final bool applying;
  final Future<void> Function() onApply;
  @override
  Widget build(BuildContext context) => Card(
        margin: const EdgeInsets.only(bottom: 12),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text('待应用变更', style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 6),
                for (final draft in drafts) _DraftTile(draft: draft),
                const SizedBox(height: 8),
                FilledButton.icon(
                  key: const Key('ai-apply-workspace-changes'),
                  onPressed: applying ? null : onApply,
                  icon: applying
                      ? const SizedBox.square(
                          dimension: 16,
                          child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.check),
                  label: Text(applying ? '正在应用…' : '应用这些变更'),
                ),
              ]),
        ),
      );
}

/// One draft rendered with concrete titles, dates and time ranges — never a
/// bare UUID — plus a before/after comparison for update drafts.
final class _DraftTile extends StatelessWidget {
  const _DraftTile({required this.draft});

  final AiWorkspaceChangeDraft draft;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final title = draft.previewTitle ?? _fallbackTitle(draft);
    final detail = draft.previewTimeRange ?? _fallbackTimeRange(draft);
    final previous = draft.previewPrevious;
    final isUpdate =
        draft.action == AiWorkspaceChangeAction.update && previous != null;
    final after = detail == null ? title : '$title（$detail）';
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            '${draft.actionLabel}${draft.entityLabel}：'
            '$title${detail == null ? '' : '（$detail）'}',
            key: const Key('ai-draft-summary'),
          ),
          if (isUpdate) ...<Widget>[
            const SizedBox(height: 2),
            Text(
              '修改前：$previous',
              style: TextStyle(color: colors.outline, fontSize: 13),
            ),
            Text(
              '修改后：$after',
              style: TextStyle(color: colors.primary, fontSize: 13),
            ),
          ],
        ],
      ),
    );
  }

  String _fallbackTitle(AiWorkspaceChangeDraft draft) {
    if (draft.entityType == AiWorkspaceEntityType.task) {
      return draft.values['title'] as String? ?? '任务';
    }
    return switch (draft.values['kind']) {
      'sleep' => '睡眠',
      'rest' => '休息',
      'breakTime' => '短休息',
      _ => '学习',
    };
  }

  String? _fallbackTimeRange(AiWorkspaceChangeDraft draft) {
    final start = draft.values['start'] as String?;
    final end = draft.values['end'] as String?;
    if (start == null && end == null) return null;
    return [
      if (start != null) start.replaceFirst('T', ' '),
      if (end != null) end.replaceFirst('T', ' ')
    ].join(' 至 ');
  }
}

/// Outcome card shown after the user applies drafts: a success summary, or
/// the concrete per-change failure reasons.
final class _ApplyResultCard extends StatelessWidget {
  const _ApplyResultCard({required this.results});

  final List<AiWorkspaceChangeResult> results;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final failures =
        results.where((result) => !result.succeeded).toList(growable: false);
    final succeeded = results.length - failures.length;
    final allSucceeded = failures.isEmpty;
    return Card(
      key: const Key('ai-apply-result-card'),
      margin: const EdgeInsets.only(bottom: 12),
      color: allSucceeded
          ? colors.primaryContainer
          : colors.errorContainer,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              children: <Widget>[
                Icon(
                  allSucceeded ? Icons.check_circle : Icons.error_outline,
                  color: allSucceeded ? colors.primary : colors.error,
                ),
                const SizedBox(width: 8),
                Text(
                  allSucceeded
                      ? '执行成功：已应用 $succeeded 项变更'
                      : succeeded == 0
                          ? '执行失败：${failures.length} 项变更均未应用'
                          : '部分成功：$succeeded 项成功，${failures.length} 项失败',
                  style: Theme.of(context).textTheme.titleSmall,
                ),
              ],
            ),
            for (final failure in failures) ...<Widget>[
              const SizedBox(height: 6),
              Text(
                '• ${failure.draft.entityLabel}「${failure.draft.previewTitle ?? failure.draft.id ?? ''}」'
                '失败原因：${failure.error ?? '未知错误'}',
                style: TextStyle(color: colors.onErrorContainer, fontSize: 13),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

final class _Composer extends StatelessWidget {
  const _Composer({
    required this.controller,
    required this.enabled,
    required this.onSend,
  });

  final TextEditingController controller;
  final bool enabled;
  final Future<void> Function([String? suggestedMessage]) onSend;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: <Widget>[
            Expanded(
              child: TextField(
                key: const Key('ai-coach-input'),
                controller: controller,
                enabled: enabled,
                minLines: 1,
                maxLines: 4,
                textInputAction: TextInputAction.send,
                onSubmitted: (_) => onSend(),
                decoration: const InputDecoration(
                  hintText: '例如：我昨晚没睡好，今天怎么安排？',
                  border: OutlineInputBorder(),
                ),
              ),
            ),
            const SizedBox(width: 8),
            IconButton.filled(
              key: const Key('ai-coach-send'),
              tooltip: '发送',
              onPressed: enabled ? () => onSend() : null,
              icon: const Icon(Icons.arrow_upward),
            ),
          ],
        ),
      );
}
