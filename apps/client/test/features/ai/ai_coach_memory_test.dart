import 'package:flutter_test/flutter_test.dart';
import 'package:studyflow/features/ai/ai_coach_memory.dart';
import 'package:studyflow/features/ai/ai_repository.dart';

void main() {
  test('loads legacy message-list memory with an empty summary', () {
    final memory = AiCoachMemory.fromJson(<Object?>[
      <String, String>{'role': 'user', 'content': '十月前完成项目。'},
      <String, String>{'role': 'assistant', 'content': '我会按此目标安排。'},
    ]);

    expect(memory.summary, isEmpty);
    expect(memory.messages, hasLength(2));
    expect(memory.messages.first.content, '十月前完成项目。');
  });

  test('round-trips a rolling summary and recent messages', () {
    const original = AiCoachMemory(
      summary: '长期目标：十月前完成项目。偏好：循序调整作息。',
      messages: <AiCoachMessage>[
        AiCoachMessage.user('我今晚想先学习一小时。'),
        AiCoachMessage.assistant('可以，结束后预留放松时间。'),
      ],
    );

    final restored = AiCoachMemory.fromJson(original.toJson());

    expect(restored.summary, original.summary);
    expect(restored.messages.map((message) => message.content), <String>[
      '我今晚想先学习一小时。',
      '可以，结束后预留放松时间。',
    ]);
  });

  test('round-trips sanitized execution details with their assistant reply',
      () {
    const original = AiCoachMemory(
      summary: '',
      messages: <AiCoachMessage>[
        AiCoachMessage.user('今天有什么安排？'),
        AiCoachMessage.assistant('你有一段学习日程。'),
      ],
      tracesByMessageIndex: <int, List<AiToolTrace>>{
        1: <AiToolTrace>[
          AiToolTrace(
            toolName: 'get_schedule_blocks',
            label: '查询日程',
            summary: '已查询 1 条日程。',
            inputSummary: '按指定时间范围查询。',
          ),
        ],
      },
    );

    final restored = AiCoachMemory.fromJson(original.toJson());

    expect(restored.tracesByMessageIndex[1], hasLength(1));
    expect(restored.tracesByMessageIndex[1]!.single.toolName,
        'get_schedule_blocks');
    expect(restored.tracesByMessageIndex[1]!.single.summary, '已查询 1 条日程。');
  });
}
