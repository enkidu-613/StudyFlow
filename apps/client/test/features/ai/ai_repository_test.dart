import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:studyflow/features/ai/ai_repository.dart';
import 'package:studyflow/features/ai/ai_settings_model.dart';

void main() {
  test(
      'returns schedule, medication and current-time tool results before final reply',
      () async {
    final requests = <Map<String, Object?>>[];
    final client = MockClient((request) async {
      requests.add(
        (jsonDecode(request.body) as Map).cast<String, Object?>(),
      );
      if (requests.length == 1) {
        return http.Response(
          jsonEncode(<String, Object?>{
            'choices': <Object?>[
              <String, Object?>{
                'message': <String, Object?>{
                  'role': 'assistant',
                  'content': null,
                  'tool_calls': <Object?>[
                    <String, Object?>{
                      'id': 'call_schedule_1',
                      'type': 'function',
                      'function': <String, String>{
                        'name': 'get_schedule_blocks',
                        'arguments': '{"blockIds":["block-1"]}',
                      },
                    },
                    <String, Object?>{
                      'id': 'call_medication_1',
                      'type': 'function',
                      'function': <String, String>{
                        'name': 'get_medication_plans',
                        'arguments': '{"enabledOnly":true}',
                      },
                    },
                    <String, Object?>{
                      'id': 'call_time_1',
                      'type': 'function',
                      'function': <String, String>{
                        'name': 'get_current_time',
                        'arguments': '{}',
                      },
                    },
                  ],
                },
              },
            ],
          }),
          200,
        );
      }
      return http.Response.bytes(
        utf8.encode(jsonEncode(<String, Object?>{
          'choices': <Object?>[
            <String, Object?>{
              'message': <String, String>{
                'role': 'assistant',
                'content': '你在 08:00 有一段 Python 学习时间。',
              },
            },
          ],
        })),
        200,
        headers: const <String, String>{
          'content-type': 'application/json; charset=utf-8',
        },
      );
    });
    final repository = HttpAiRepository(
      client: client,
      now: () => DateTime.utc(2026, 8, 16, 10, 15, 30),
    );

    final reply = await repository.requestCoachReply(
      settings: const AiSettings(
        baseUrl: 'https://ai.example.com/v1',
        model: 'test-model',
        apiKey: 'test-key',
        enabled: true,
      ),
      userMessage: '我今天上午有什么安排？',
      history: const <AiCoachMessage>[],
      conversationSummary: '长期目标：十月前完成项目。',
      taskTitles: const <String>['完成 Python 项目'],
      scheduleMetrics: const <String, double>{'blockCount': 1},
      focusCompletionMetrics: const <String, double>{},
      sleepAggregates: const <String, double>{},
      scheduleLookup: (arguments) async {
        expect(arguments, <String, Object?>{
          'blockIds': <String>['block-1'],
        });
        return <Map<String, Object?>>[
          <String, Object?>{
            'id': 'block-1',
            'start': '2026-08-16T08:00:00.000Z',
            'end': '2026-08-16T09:00:00.000Z',
            'kind': 'task',
            'isLocked': true,
            'repeatRule': 'none',
            'taskTitle': '完成 Python 项目',
          },
        ];
      },
      medicationLookup: (arguments) async {
        expect(arguments, <String, Object?>{'enabledOnly': true});
        return <Map<String, Object?>>[
          <String, Object?>{
            'id': 'medication-1',
            'name': '示例药物',
            'enabled': true,
          },
        ];
      },
    );

    expect(reply.content, '你在 08:00 有一段 Python 学习时间。');
    expect(
      reply.traces.map((trace) => trace.toolName),
      <String>[
        'get_schedule_blocks',
        'get_medication_plans',
        'get_current_time',
      ],
    );
    expect(reply.traces[0].summary, '已查询 1 条日程。');
    expect(reply.traces[1].summary, '已查询 1 个服药计划。');
    expect(reply.traces[2].summary, '已读取设备当前时间。');
    expect(requests, hasLength(2));
    expect(requests.first['tools'], isNotNull);
    expect(
      requests.first['tool_choice'],
      const <String, Object?>{
        'type': 'function',
        'function': <String, String>{'name': 'get_schedule_blocks'},
      },
    );
    expect(requests.last.containsKey('tool_choice'), isFalse);
    expect(
      (requests.first['messages']! as List).whereType<Map>().map(
            (message) => message['content'],
          ),
      contains(contains('长期目标：十月前完成项目。')),
    );
    final tools = (requests.first['tools']! as List).cast<Map>();
    expect(
      tools.map((tool) => (tool['function']! as Map)['name']).toSet(),
      <String>{
        'get_schedule_blocks',
        'get_current_time',
        'get_schedule_feedback',
        'get_medication_plans',
        'get_tasks',
        'propose_workspace_changes',
      },
    );
    final messages = requests.last['messages']! as List;
    final scheduleToolMessage = messages[messages.length - 3] as Map;
    expect(scheduleToolMessage['role'], 'tool');
    expect(scheduleToolMessage['tool_call_id'], 'call_schedule_1');
    expect(
      jsonDecode(scheduleToolMessage['content']! as String),
      <String, Object?>{
        'blocks': <Object?>[
          <String, Object?>{
            'id': 'block-1',
            'start': '2026-08-16T08:00:00.000Z',
            'end': '2026-08-16T09:00:00.000Z',
            'kind': 'task',
            'isLocked': true,
            'repeatRule': 'none',
            'taskTitle': '完成 Python 项目',
          },
        ],
      },
    );
    final medicationToolMessage = messages[messages.length - 2] as Map;
    expect(medicationToolMessage['role'], 'tool');
    expect(medicationToolMessage['tool_call_id'], 'call_medication_1');
    expect(
      jsonDecode(medicationToolMessage['content']! as String),
      <String, Object?>{
        'plans': <Object?>[
          <String, Object?>{
            'id': 'medication-1',
            'name': '示例药物',
            'enabled': true,
          },
        ],
      },
    );
    final timeToolMessage = messages.last as Map;
    expect(timeToolMessage['role'], 'tool');
    expect(timeToolMessage['tool_call_id'], 'call_time_1');
    expect(
      jsonDecode(timeToolMessage['content']! as String),
      <String, Object?>{
        'currentTime': '2026-08-16T10:15:30.000Z',
        'timeZone': 'UTC',
        'utcOffsetMinutes': 0,
      },
    );
  });

  test('asks the configured model for a concise Chinese memory summary',
      () async {
    final requests = <Map<String, Object?>>[];
    final client = MockClient((request) async {
      requests.add((jsonDecode(request.body) as Map).cast<String, Object?>());
      return http.Response.bytes(
        utf8.encode(jsonEncode(<String, Object?>{
          'choices': <Object?>[
            <String, Object?>{
              'message': <String, String>{
                'role': 'assistant',
                'content': '长期目标：十月前完成项目；偏好：循序调整作息。',
              },
            },
          ],
        })),
        200,
        headers: const <String, String>{
          'content-type': 'application/json; charset=utf-8',
        },
      );
    });

    final summary = await HttpAiRepository(client: client).summarizeCoachMemory(
      settings: const AiSettings(
        baseUrl: 'https://ai.example.com/v1',
        model: 'test-model',
        apiKey: 'test-key',
        enabled: true,
      ),
      existingSummary: '旧目标：保持学习。',
      messages: const <AiCoachMessage>[
        AiCoachMessage.user('我想十月前完成项目。'),
      ],
    );

    expect(summary, '长期目标：十月前完成项目；偏好：循序调整作息。');
    expect(requests, hasLength(1));
    expect(requests.single['tools'], isNull);
    final systemMessage = (requests.single['messages']! as List).first as Map;
    expect(systemMessage['role'], 'system');
    expect(systemMessage['content'], contains('压缩 StudyFlow 私人学习教练'));
  });

  test('converts leaked DSML workspace changes into a safe draft', () async {
    final client = MockClient((_) async => http.Response.bytes(
          utf8.encode(jsonEncode(<String, Object?>{
            'choices': <Object?>[
              <String, Object?>{
                'message': <String, String>{
                  'role': 'assistant',
                  'content': '我已准备好调整方案。\n'
                      '<|DSML|tool_calls><|DSML|invoke '
                      'name="propose_workspace_changes"><|DSML|parameter '
                      'name="changes" string="false">'
                      '[{"entityType":"schedule_block","action":"update",'
                      '"id":"11111111-1111-4111-8111-111111111111",'
                      '"values":{"start":"2026-08-17T17:00:00"}}]'
                      '</|DSML|parameter></|DSML|invoke></|DSML|tool_calls>',
                },
              },
            ],
          })),
          200,
          headers: const <String, String>{
            'content-type': 'application/json; charset=utf-8',
          },
        ));
    final repository = HttpAiRepository(client: client);

    final reply = await repository.requestCoachReply(
      settings: const AiSettings(
        baseUrl: 'https://ai.example.com/v1',
        model: 'test-model',
        apiKey: 'test-key',
        enabled: true,
      ),
      userMessage: '把学习安排到下午五点。',
      history: const <AiCoachMessage>[],
      taskTitles: const <String>[],
      scheduleMetrics: const <String, double>{},
      focusCompletionMetrics: const <String, double>{},
      sleepAggregates: const <String, double>{},
      scheduleLookup: (_) async => const <Map<String, Object?>>[],
      workspaceChangeLookup: (drafts) async => drafts,
    );

    expect(reply.content, '我已准备好调整方案。');
    expect(reply.content, isNot(contains('DSML')));
    expect(reply.drafts, hasLength(1));
    expect(reply.drafts.single.entityType, AiWorkspaceEntityType.scheduleBlock);
    expect(reply.traces.single.toolName, 'propose_workspace_changes');
  });

  test(
      'requires the draft tool when the user explicitly asks to generate a draft',
      () async {
    Map<String, Object?>? requestBody;
    final client = MockClient((request) async {
      requestBody = (jsonDecode(request.body) as Map).cast<String, Object?>();
      return http.Response.bytes(
        utf8.encode(jsonEncode(<String, Object?>{
          'choices': <Object?>[
            <String, Object?>{
              'message': <String, String>{
                'role': 'assistant',
                'content': '我会生成待确认的草案。',
              },
            },
          ],
        })),
        200,
        headers: const <String, String>{
          'content-type': 'application/json; charset=utf-8',
        },
      );
    });

    await HttpAiRepository(client: client).requestCoachReply(
      settings: const AiSettings(
        baseUrl: 'https://ai.example.com/v1',
        model: 'test-model',
        apiKey: 'test-key',
        enabled: true,
      ),
      userMessage: '请生成今天日程的调整草案。',
      history: const <AiCoachMessage>[],
      taskTitles: const <String>[],
      scheduleMetrics: const <String, double>{},
      focusCompletionMetrics: const <String, double>{},
      sleepAggregates: const <String, double>{},
      scheduleLookup: (_) async => const <Map<String, Object?>>[],
      workspaceChangeLookup: (drafts) async => drafts,
    );

    expect(
      requestBody!['tool_choice'],
      const <String, Object?>{
        'type': 'function',
        'function': <String, String>{'name': 'propose_workspace_changes'},
      },
    );
  });

  test('uses the protocol endpoint and authentication headers', () async {
    final requests = <http.Request>[];
    final client = MockClient((request) async {
      requests.add(request);
      return http.Response(
        jsonEncode(<String, Object?>{
          'choices': <Object?>[
            <String, Object?>{
              'message': <String, String>{
                'role': 'assistant',
                'content': 'ok',
              },
            },
          ],
        }),
        200,
      );
    });
    final repository = HttpAiRepository(client: client);

    await repository.testConnection(const AiSettings(
      baseUrl: 'https://x.example/v1',
      model: 'model',
      apiKey: 'sk-abc',
      enabled: true,
    ));
    await repository.testConnection(const AiSettings(
      baseUrl: 'https://x.example/v1',
      model: 'model',
      apiKey: 'sk-abc',
      enabled: true,
      protocol: AiProtocol.openaiResponses,
    ));
    await repository.testConnection(const AiSettings(
      baseUrl: 'https://api.anthropic.com',
      model: 'model',
      apiKey: 'sk-abc',
      enabled: true,
      protocol: AiProtocol.anthropicMessages,
    ));
    await repository.testConnection(const AiSettings(
      baseUrl: 'https://api.anthropic.com/v1',
      model: 'model',
      apiKey: 'sk-abc',
      enabled: true,
      protocol: AiProtocol.anthropicMessages,
    ));

    expect(requests[0].url.path, '/v1/chat/completions');
    expect(requests[0].headers['Authorization'], 'Bearer sk-abc');
    expect(requests[1].url.path, '/v1/responses');
    expect(requests[1].headers['Authorization'], 'Bearer sk-abc');
    expect(requests[2].url.path, '/v1/messages');
    expect(requests[2].headers['x-api-key'], 'sk-abc');
    expect(requests[2].headers['anthropic-version'], '2023-06-01');
    expect(requests[2].headers.containsKey('Authorization'), isFalse);
    expect(requests[3].url.path, '/v1/messages');
  });

  test('parses plain text responses across the three protocols', () async {
    final client = MockClient((request) async {
      if (request.url.path.endsWith('/responses')) {
        return _jsonResponse(<String, Object?>{
          'output': <Object?>[
            <String, Object?>{
              'type': 'message',
              'role': 'assistant',
              'content': <Object?>[
                <String, String>{'type': 'output_text', 'text': 'Responses 回复'},
              ],
            },
          ],
        });
      }
      if (request.url.path.endsWith('/v1/messages')) {
        return _jsonResponse(<String, Object?>{
          'content': <Object?>[
            <String, String>{'type': 'text', 'text': 'Anthropic 回复'},
          ],
        });
      }
      return _jsonResponse(<String, Object?>{
        'choices': <Object?>[
          <String, Object?>{
            'message': <String, String>{
              'role': 'assistant',
              'content': 'Chat 回复',
            },
          },
        ],
      });
    });
    final repository = HttpAiRepository(client: client);

    final chat = await _coachReply(
      repository,
      const AiSettings(
        baseUrl: 'https://x.example/v1',
        model: 'model',
        apiKey: 'key',
        enabled: true,
      ),
    );
    final responses = await _coachReply(
      repository,
      const AiSettings(
        baseUrl: 'https://x.example/v1',
        model: 'model',
        apiKey: 'key',
        enabled: true,
        protocol: AiProtocol.openaiResponses,
      ),
    );
    final anthropic = await _coachReply(
      repository,
      const AiSettings(
        baseUrl: 'https://api.anthropic.com',
        model: 'model',
        apiKey: 'key',
        enabled: true,
        protocol: AiProtocol.anthropicMessages,
      ),
    );

    expect(chat.content, 'Chat 回复');
    expect(responses.content, 'Responses 回复');
    expect(anthropic.content, 'Anthropic 回复');
  });

  test('encodes tool definitions per protocol', () async {
    final bodies = <Map<String, Object?>>[];
    final client = MockClient((request) async {
      bodies.add((jsonDecode(request.body) as Map).cast<String, Object?>());
      if (request.url.path.endsWith('/responses')) {
        return _jsonResponse(<String, Object?>{
          'output': <Object?>[
            <String, Object?>{
              'type': 'message',
              'role': 'assistant',
              'content': <Object?>[
                <String, String>{'type': 'output_text', 'text': 'ok'},
              ],
            },
          ],
        });
      }
      if (request.url.path.endsWith('/v1/messages')) {
        return _jsonResponse(<String, Object?>{
          'content': <Object?>[
            <String, String>{'type': 'text', 'text': 'ok'},
          ],
        });
      }
      return _jsonResponse(<String, Object?>{
        'choices': <Object?>[
          <String, Object?>{
            'message': <String, String>{'role': 'assistant', 'content': 'ok'},
          },
        ],
      });
    });
    final repository = HttpAiRepository(client: client);

    await _coachReply(
      repository,
      const AiSettings(
        baseUrl: 'https://x.example/v1',
        model: 'model',
        apiKey: 'key',
        enabled: true,
      ),
      message: '我今天有什么安排？',
    );
    await _coachReply(
      repository,
      const AiSettings(
        baseUrl: 'https://x.example/v1',
        model: 'model',
        apiKey: 'key',
        enabled: true,
        protocol: AiProtocol.openaiResponses,
      ),
      message: '我今天有什么安排？',
    );
    await _coachReply(
      repository,
      const AiSettings(
        baseUrl: 'https://api.anthropic.com',
        model: 'model',
        apiKey: 'key',
        enabled: true,
        protocol: AiProtocol.anthropicMessages,
      ),
      message: '我今天有什么安排？',
    );

    final chatTools = (bodies[0]['tools']! as List).cast<Map>();
    expect(
      chatTools.map((tool) => (tool['function']! as Map)['name']),
      contains('get_schedule_blocks'),
    );
    final responsesTools = (bodies[1]['tools']! as List).cast<Map>();
    expect(responsesTools.map((tool) => tool['name']), contains('get_schedule_blocks'));
    expect(responsesTools.first['type'], 'function');
    expect(responsesTools.first.containsKey('parameters'), isTrue);
    final anthropicTools = (bodies[2]['tools']! as List).cast<Map>();
    expect(
      anthropicTools.map((tool) => tool['name']),
      contains('get_schedule_blocks'),
    );
    expect(anthropicTools.first.containsKey('input_schema'), isTrue);
  });

  test('OpenAI Responses tool loop returns function_call_output', () async {
    final requests = <Map<String, Object?>>[];
    final client = MockClient((request) async {
      requests.add((jsonDecode(request.body) as Map).cast<String, Object?>());
      if (requests.length == 1) {
        return _jsonResponse(<String, Object?>{
          'output': <Object?>[
            <String, Object?>{
              'type': 'function_call',
              'call_id': 'fc_1',
              'name': 'get_current_time',
              'arguments': '{}',
            },
          ],
        });
      }
      return _jsonResponse(<String, Object?>{
        'output': <Object?>[
          <String, Object?>{
            'type': 'message',
            'role': 'assistant',
            'content': <Object?>[
              <String, String>{'type': 'output_text', 'text': '现在是 10:15。'},
            ],
          },
        ],
      });
    });
    final repository = HttpAiRepository(
      client: client,
      now: () => DateTime.utc(2026, 8, 16, 10, 15, 30),
    );

    final reply = await _coachReply(
      repository,
      const AiSettings(
        baseUrl: 'https://x.example/v1',
        model: 'model',
        apiKey: 'key',
        enabled: true,
        protocol: AiProtocol.openaiResponses,
      ),
      message: '现在几点？',
    );

    expect(reply.content, '现在是 10:15。');
    expect(reply.traces.single.toolName, 'get_current_time');
    final input = requests.last['input']! as List;
    final outputItem = input.last as Map;
    expect(outputItem['type'], 'function_call_output');
    expect(outputItem['call_id'], 'fc_1');
    expect(
      jsonDecode(outputItem['output']! as String),
      <String, Object?>{
        'currentTime': '2026-08-16T10:15:30.000Z',
        'timeZone': 'UTC',
        'utcOffsetMinutes': 0,
      },
    );
  });

  test('OpenAI Responses keeps multiple function calls exactly once', () async {
    final requests = <Map<String, Object?>>[];
    final client = MockClient((request) async {
      requests.add((jsonDecode(request.body) as Map).cast<String, Object?>());
      if (requests.length == 1) {
        return _jsonResponse(<String, Object?>{
          'output': <Object?>[
            <String, Object?>{
              'type': 'function_call',
              'call_id': 'fc_time',
              'name': 'get_current_time',
              'arguments': '{}',
            },
            <String, Object?>{
              'type': 'function_call',
              'call_id': 'fc_schedule',
              'name': 'get_schedule_blocks',
              'arguments': '{}',
            },
          ],
        });
      }
      return _jsonResponse(<String, Object?>{
        'output': <Object?>[
          <String, Object?>{
            'type': 'message',
            'role': 'assistant',
            'content': <Object?>[
              <String, String>{'type': 'output_text', 'text': '已查询。'},
            ],
          },
        ],
      });
    });
    final repository = HttpAiRepository(
      client: client,
      now: () => DateTime.utc(2026, 8, 16, 10, 15, 30),
    );

    await _coachReply(
      repository,
      const AiSettings(
        baseUrl: 'https://x.example/v1',
        model: 'model',
        apiKey: 'key',
        enabled: true,
        protocol: AiProtocol.openaiResponses,
      ),
      message: '今天有什么安排？',
    );

    final input = requests.last['input']! as List;
    final functionCalls = input
        .where((item) => (item as Map)['type'] == 'function_call')
        .cast<Map>()
        .toList();
    final functionCallOutputs = input
        .where((item) => (item as Map)['type'] == 'function_call_output')
        .cast<Map>()
        .toList();
    expect(
      functionCalls.map((item) => item['call_id']),
      <Object?>['fc_time', 'fc_schedule'],
    );
    expect(
      functionCallOutputs.map((item) => item['call_id']),
      <Object?>['fc_time', 'fc_schedule'],
    );
  });

  test('OpenAI Responses preserves reasoning items for the next tool round',
      () async {
    final requests = <Map<String, Object?>>[];
    final client = MockClient((request) async {
      requests.add((jsonDecode(request.body) as Map).cast<String, Object?>());
      if (requests.length == 1) {
        return _jsonResponse(<String, Object?>{
          'output': <Object?>[
            <String, Object?>{
              'type': 'reasoning',
              'id': 'rs_1',
              'summary': <Object?>[],
            },
            <String, Object?>{
              'type': 'function_call',
              'call_id': 'fc_1',
              'name': 'get_current_time',
              'arguments': '{}',
            },
          ],
        });
      }
      return _jsonResponse(<String, Object?>{
        'output': <Object?>[
          <String, Object?>{
            'type': 'message',
            'role': 'assistant',
            'content': <Object?>[
              <String, String>{'type': 'output_text', 'text': '现在是 10:15。'},
            ],
          },
        ],
      });
    });
    final repository = HttpAiRepository(
      client: client,
      now: () => DateTime.utc(2026, 8, 16, 10, 15, 30),
    );

    await _coachReply(
      repository,
      const AiSettings(
        baseUrl: 'https://x.example/v1',
        model: 'model',
        apiKey: 'key',
        enabled: true,
        protocol: AiProtocol.openaiResponses,
      ),
      message: '现在几点？',
    );

    final input = requests.last['input']! as List;
    expect(
      input.where((item) => (item as Map)['type'] == 'reasoning'),
      hasLength(1),
    );
    expect(
      input.where((item) => (item as Map)['type'] == 'reasoning').single['id'],
      'rs_1',
    );
  });

  test('Anthropic Messages tool loop returns tool_result blocks', () async {
    final requests = <Map<String, Object?>>[];
    final client = MockClient((request) async {
      requests.add((jsonDecode(request.body) as Map).cast<String, Object?>());
      if (requests.length == 1) {
        return _jsonResponse(<String, Object?>{
          'content': <Object?>[
            <String, Object?>{
              'type': 'tool_use',
              'id': 'toolu_1',
              'name': 'get_current_time',
              'input': <String, Object?>{},
            },
          ],
        });
      }
      return _jsonResponse(<String, Object?>{
        'content': <Object?>[
          <String, String>{'type': 'text', 'text': '当前是 10:15。'},
        ],
      });
    });
    final repository = HttpAiRepository(
      client: client,
      now: () => DateTime.utc(2026, 8, 16, 10, 15, 30),
    );

    final reply = await _coachReply(
      repository,
      const AiSettings(
        baseUrl: 'https://api.anthropic.com',
        model: 'model',
        apiKey: 'key',
        enabled: true,
        protocol: AiProtocol.anthropicMessages,
      ),
      message: '现在几点？',
    );

    expect(reply.content, '当前是 10:15。');
    expect(requests.first['system'], isA<String>());
    final messages = requests.last['messages']! as List;
    final lastMessage = messages.last as Map;
    expect(lastMessage['role'], 'user');
    final blocks = lastMessage['content']! as List;
    expect((blocks.first as Map)['type'], 'tool_result');
    expect((blocks.first as Map)['tool_use_id'], 'toolu_1');
  });

  test('caps tool rounds at four with a readable error', () async {
    var requestCount = 0;
    final client = MockClient((request) async {
      requestCount++;
      return _jsonResponse(<String, Object?>{
        'choices': <Object?>[
          <String, Object?>{
            'message': <String, Object?>{
              'role': 'assistant',
              'content': null,
              'tool_calls': <Object?>[
                <String, Object?>{
                  'id': 'call_1',
                  'type': 'function',
                  'function': <String, String>{
                    'name': 'get_current_time',
                    'arguments': '{}',
                  },
                },
              ],
            },
          },
        ],
      });
    });
    final repository = HttpAiRepository(client: client);

    await expectLater(
      _coachReply(
        repository,
        const AiSettings(
          baseUrl: 'https://x.example/v1',
          model: 'model',
          apiKey: 'key',
          enabled: true,
        ),
      ),
      throwsA(isA<AiCapabilityFailure>()),
    );
    expect(requestCount, 4);
  });

  test('maps 503 to provider unavailable and never leaks the API key',
      () async {
    final client = MockClient(
      (_) async => http.Response(
        jsonEncode(<String, Object?>{
          'error': <String, String>{'code': 'overloaded', 'message': 'overloaded'},
        }),
        503,
      ),
    );
    final repository = HttpAiRepository(client: client);

    await expectLater(
      repository.testConnection(const AiSettings(
        baseUrl: 'https://x.example/v1',
        model: 'model',
        apiKey: 'sk-very-secret',
        enabled: true,
      )),
      throwsA(
        isA<AiProviderUnavailableFailure>().having(
          (error) => error.message,
          'message',
          allOf(contains('503'), contains('overloaded')),
        ),
      ),
    );
  });

  test('includes top-level provider error code and message for 503', () async {
    final client = MockClient(
      (_) async => http.Response.bytes(
        utf8.encode(jsonEncode(<String, Object?>{
          'code': 'SERVICE_BUSY',
          'message': '安全校验服务暂时不可用',
          'traceId': 'trace-should-not-be-shown',
        })),
        503,
        headers: const <String, String>{
          'content-type': 'application/json; charset=utf-8',
        },
      ),
    );
    final repository = HttpAiRepository(client: client);

    await expectLater(
      repository.testConnection(const AiSettings(
        baseUrl: 'https://x.example/v1',
        model: 'model',
        apiKey: 'sk-very-secret',
        enabled: true,
      )),
      throwsA(
        isA<AiProviderUnavailableFailure>().having(
          (error) => error.message,
          'message',
          allOf(
            contains('SERVICE_BUSY'),
            contains('安全校验服务暂时不可用'),
            isNot(contains('trace-should-not-be-shown')),
          ),
        ),
      ),
    );
  });
}

Future<AiCoachReply> _coachReply(
  AiRepository repository,
  AiSettings settings, {
  String message = '你好',
}) =>
    repository.requestCoachReply(
      settings: settings,
      userMessage: message,
      history: const <AiCoachMessage>[],
      taskTitles: const <String>[],
      scheduleMetrics: const <String, double>{},
      focusCompletionMetrics: const <String, double>{},
      sleepAggregates: const <String, double>{},
      scheduleLookup: (_) async => const <Map<String, Object?>>[],
    );

http.Response _jsonResponse(Map<String, Object?> body) => http.Response.bytes(
      utf8.encode(jsonEncode(body)),
      200,
      headers: const <String, String>{
        'content-type': 'application/json; charset=utf-8',
      },
    );
