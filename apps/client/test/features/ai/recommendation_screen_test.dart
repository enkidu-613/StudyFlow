import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:studyflow/features/ai/ai_coach_memory.dart';
import 'package:studyflow/features/ai/ai_repository.dart';
import 'package:studyflow/features/ai/ai_workspace_change_service.dart';
import 'package:studyflow/features/ai/recommendation_screen.dart';
import '../../helpers/l10n_test_app.dart';

void main() {
  testWidgets('sends a Chinese message and displays a coach reply',
      (tester) async {
    await pumpWithL10n(
      tester,
      RecommendationScreen(
        requestReply: ({
          required userMessage,
          required history,
          required conversationSummary,
        }) async {
          expect(userMessage, '今天很累，怎么学习？');
          expect(history.single.role, AiCoachRole.assistant);
          return const AiCoachReply('先休息 20 分钟，再只完成一个 25 分钟的小任务。');
        },
      ),
    );

    await tester.enterText(
      find.byKey(const Key('ai-coach-input')),
      '今天很累，怎么学习？',
    );
    await tester.tap(find.byKey(const Key('ai-coach-send')));
    await tester.pumpAndSettle();

    expect(find.text('今天很累，怎么学习？'), findsOneWidget);
    expect(
      find.text('先休息 20 分钟，再只完成一个 25 分钟的小任务。'),
      findsOneWidget,
    );
  });

  testWidgets('shows a Chinese error without removing the user message',
      (tester) async {
    await pumpWithL10n(
      tester,
      RecommendationScreen(
        requestReply: ({
          required userMessage,
          required history,
          required conversationSummary,
        }) async =>
            throw const AiNetworkFailure('AI 服务不可用。'),
      ),
    );

    await tester.enterText(
      find.byKey(const Key('ai-coach-input')),
      '帮我安排今天。',
    );
    await tester.tap(find.byKey(const Key('ai-coach-send')));
    await tester.pumpAndSettle();

    expect(find.text('帮我安排今天。'), findsOneWidget);
    expect(find.textContaining('暂时无法获取回复'), findsOneWidget);
  });

  testWidgets('accepts only one submit while a reply is in progress',
      (tester) async {
    final reply = Completer<AiCoachReply>();
    var calls = 0;
    await pumpWithL10n(
      tester,
      RecommendationScreen(
        requestReply: ({
          required userMessage,
          required history,
          required conversationSummary,
        }) {
          calls += 1;
          return reply.future;
        },
      ),
    );

    await tester.enterText(
      find.byKey(const Key('ai-coach-input')),
      '为我调整今天的日程',
    );
    await tester.testTextInput.receiveAction(TextInputAction.send);
    await tester.testTextInput.receiveAction(TextInputAction.send);
    await tester.pump();

    expect(calls, 1);
    expect(find.text('为我调整今天的日程'), findsOneWidget);
    expect(
      tester
          .widget<IconButton>(find.byKey(const Key('ai-coach-send')))
          .onPressed,
      isNull,
    );

    reply.complete(const AiCoachReply('我会先读取日程，再提出调整草案。'));
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<IconButton>(find.byKey(const Key('ai-coach-send')))
          .onPressed,
      isNotNull,
    );
  });

  testWidgets('keeps a pending draft available after a later chat reply',
      (tester) async {
    var replyCount = 0;
    var applyCalls = 0;
    final draft = AiWorkspaceChangeDraft(
      entityType: AiWorkspaceEntityType.scheduleBlock,
      action: AiWorkspaceChangeAction.update,
      id: 'internal-schedule-id',
      values: const <String, Object?>{
        'start': '2026-08-17T17:00:00',
        'end': '2026-08-17T18:00:00',
        'kind': 'sleep',
      },
    );
    await pumpWithL10n(
      tester,
      RecommendationScreen(
        requestReply: ({
          required userMessage,
          required history,
          required conversationSummary,
        }) async {
          replyCount += 1;
          return replyCount == 1
              ? AiCoachReply('草案已准备好。', drafts: <AiWorkspaceChangeDraft>[draft])
              : const AiCoachReply('草案仍在下方，等待你确认。');
        },
        applyDrafts: (drafts) async {
          applyCalls += 1;
          return drafts
              .map((draft) => AiWorkspaceChangeResult(draft: draft))
              .toList();
        },
      ),
    );

    await tester.enterText(find.byKey(const Key('ai-coach-input')), '生成草案');
    await tester.tap(find.byKey(const Key('ai-coach-send')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('ai-apply-workspace-changes')), findsOneWidget);
    expect(find.textContaining('睡眠'), findsOneWidget);
    expect(find.text('internal-schedule-id'), findsNothing);

    await tester.enterText(find.byKey(const Key('ai-coach-input')), '草案好了吗？');
    await tester.tap(find.byKey(const Key('ai-coach-send')));
    await tester.pumpAndSettle();

    expect(find.text('草案仍在下方，等待你确认。'), findsOneWidget);
    expect(find.byKey(const Key('ai-apply-workspace-changes')), findsOneWidget);

    await tester.tap(find.byKey(const Key('ai-apply-workspace-changes')));
    await tester.pumpAndSettle();

    expect(applyCalls, 1);
    expect(find.text('已成功应用 1 项变更。'), findsOneWidget);
    expect(find.byKey(const Key('ai-apply-workspace-changes')), findsNothing);
  });

  testWidgets('reports a failed draft application and keeps it retryable',
      (tester) async {
    final draft = AiWorkspaceChangeDraft(
      entityType: AiWorkspaceEntityType.task,
      action: AiWorkspaceChangeAction.update,
      id: 'task-id',
      values: const <String, Object?>{'title': '复习 Python'},
    );
    await pumpWithL10n(
      tester,
      RecommendationScreen(
        requestReply: ({
          required userMessage,
          required history,
          required conversationSummary,
        }) async =>
            AiCoachReply('请确认草案。', drafts: <AiWorkspaceChangeDraft>[draft]),
        applyDrafts: (drafts) async => <AiWorkspaceChangeResult>[
          AiWorkspaceChangeResult(
              draft: drafts.single, error: StateError('not found')),
        ],
      ),
    );

    await tester.enterText(find.byKey(const Key('ai-coach-input')), '生成草案');
    await tester.tap(find.byKey(const Key('ai-coach-send')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('ai-apply-workspace-changes')));
    await tester.pumpAndSettle();

    expect(find.text('未能应用 1 项变更，请检查后重试。'), findsOneWidget);
    expect(find.byKey(const Key('ai-apply-workspace-changes')), findsOneWidget);
  });

  testWidgets('shows collapsible, sanitized tool execution details',
      (tester) async {
    await pumpWithL10n(
      tester,
      RecommendationScreen(
        requestReply: ({
          required userMessage,
          required history,
          required conversationSummary,
        }) async =>
            const AiCoachReply(
          '我已根据今天的日程给出建议。',
          traces: <AiToolTrace>[
            AiToolTrace(
              toolName: 'get_schedule_blocks',
              label: '查询日程',
              summary: '已查询 1 条日程。',
            ),
          ],
        ),
      ),
    );

    await tester.enterText(
      find.byKey(const Key('ai-coach-input')),
      '今天有什么安排？',
    );
    await tester.tap(find.byKey(const Key('ai-coach-send')));
    await tester.pumpAndSettle();

    expect(find.text('执行详情 · 已调用 1 个工具'), findsOneWidget);
    expect(
      tester.getTopLeft(find.text('执行详情 · 已调用 1 个工具')).dy,
      lessThan(tester.getTopLeft(find.text('我已根据今天的日程给出建议。')).dy),
    );
    expect(find.text('已查询 1 条日程。'), findsNothing);

    await tester.tap(find.text('执行详情 · 已调用 1 个工具'));
    await tester.pumpAndSettle();

    expect(find.text('查询日程'), findsOneWidget);
    expect(find.text('已查询 1 条日程。'), findsOneWidget);
    expect(find.textContaining('内部思考'), findsOneWidget);
  });

  testWidgets('discloses when a coach reply did not call any tool',
      (tester) async {
    await pumpWithL10n(
      tester,
      RecommendationScreen(
        requestReply: ({
          required userMessage,
          required history,
          required conversationSummary,
        }) async =>
            const AiCoachReply('先喝一点水，再决定下一步。'),
      ),
    );

    await tester.enterText(
      find.byKey(const Key('ai-coach-input')),
      '给我一句泛化建议。',
    );
    await tester.tap(find.byKey(const Key('ai-coach-send')));
    await tester.pumpAndSettle();

    expect(find.text('执行详情 · 未调用工具'), findsOneWidget);
    await tester.tap(find.text('执行详情 · 未调用工具'));
    await tester.pumpAndSettle();
    expect(find.text('模型未调用任何工具'), findsOneWidget);
  });

  testWidgets('restores a saved conversation for the same account',
      (tester) async {
    final memory = _MemoryStore();
    await memory.save(
      accountId: 'account-1',
      memory: const AiCoachMemory(
        summary: '长期目标：十月前完成项目。',
        messages: <AiCoachMessage>[
          AiCoachMessage.user('我昨天完成了什么？'),
          AiCoachMessage.assistant('你完成了一次 25 分钟专注。'),
        ],
      ),
    );

    await pumpWithL10n(
      tester,
      RecommendationScreen(
        accountId: 'account-1',
        memoryStore: memory,
        requestReply: ({
          required userMessage,
          required history,
          required conversationSummary,
        }) async =>
            const AiCoachReply('继续保持。'),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('我昨天完成了什么？'), findsOneWidget);
    expect(find.text('你完成了一次 25 分钟专注。'), findsOneWidget);
  });

  testWidgets('compacts old messages into a rolling local summary',
      (tester) async {
    final memory = _MemoryStore();
    final oldMessages = List<AiCoachMessage>.generate(
      40,
      (index) => index.isEven
          ? AiCoachMessage.user('旧消息 $index')
          : AiCoachMessage.assistant('旧回复 $index'),
    );
    await memory.save(
      accountId: 'account-1',
      memory: AiCoachMemory(summary: '', messages: oldMessages),
    );
    List<AiCoachMessage>? compacted;

    await pumpWithL10n(
      tester,
      RecommendationScreen(
        accountId: 'account-1',
        memoryStore: memory,
        summarizeMemory: ({required existingSummary, required messages}) async {
          expect(existingSummary, isEmpty);
          compacted = messages;
          return '长期目标：十月前完成项目。';
        },
        requestReply: ({
          required userMessage,
          required history,
          required conversationSummary,
        }) async {
          expect(conversationSummary, '长期目标：十月前完成项目。');
          expect(history, hasLength(24));
          return const AiCoachReply('先完成今天最重要的一步。');
        },
      ),
    );
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('ai-coach-input')),
      '我现在该做什么？',
    );
    await tester.tap(find.byKey(const Key('ai-coach-send')));
    await tester.pumpAndSettle();

    expect(compacted, hasLength(16));
    final saved = await memory.load(accountId: 'account-1');
    expect(saved.summary, '长期目标：十月前完成项目。');
    expect(saved.messages, hasLength(26));
    expect(find.text('先完成今天最重要的一步。'), findsOneWidget);
  });
}

final class _MemoryStore implements AiCoachMemoryStore {
  final Map<String, AiCoachMemory> _memory = <String, AiCoachMemory>{};

  @override
  Future<void> clear({required String accountId}) async {
    _memory.remove(accountId);
  }

  @override
  Future<AiCoachMemory> load({required String accountId}) async =>
      _memory[accountId] ?? const AiCoachMemory.empty();

  @override
  Future<void> save({
    required String accountId,
    required AiCoachMemory memory,
  }) async {
    _memory[accountId] = memory;
  }
}
