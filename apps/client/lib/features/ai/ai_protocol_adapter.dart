import 'dart:convert';

import 'package:studyflow/features/ai/ai_errors.dart';
import 'package:studyflow/features/ai/ai_settings_model.dart';

/// A single tool call requested by the model, in protocol-independent form.
final class AiProtocolToolCall {
  const AiProtocolToolCall({
    required this.id,
    required this.name,
    required this.arguments,
  });

  final String id;
  final String name;
  final Map<String, Object?> arguments;
}

/// A tool result to send back to the model, keyed by the original call ID.
final class AiProtocolToolResult {
  const AiProtocolToolResult({
    required this.toolCallId,
    required this.content,
  });

  final String toolCallId;
  final String content;
}

/// A tool definition exposed to the model across all three protocols.
final class AiProtocolTool {
  const AiProtocolTool({
    required this.name,
    required this.description,
    required this.parameters,
  });

  final String name;
  final String description;
  final Map<String, Object?> parameters;
}

enum AiProtocolMessageRole { system, user, assistant, tool }

/// One conversation message in protocol-independent form.
///
/// Tool results are carried as a batch on a single `tool` message; each
/// protocol adapter expands them into its own wire format.
final class AiProtocolRequestMessage {
  const AiProtocolRequestMessage._(
    this.role,
    this.content, {
    this.toolCalls = const <AiProtocolToolCall>[],
    this.toolResults = const <AiProtocolToolResult>[],
    this.responsesOutputItems = const <Map<String, Object?>>[],
  });

  const AiProtocolRequestMessage.system(String content)
      : this._(AiProtocolMessageRole.system, content);

  const AiProtocolRequestMessage.user(String content)
      : this._(AiProtocolMessageRole.user, content);

  const AiProtocolRequestMessage.assistant(
    String content, {
    List<AiProtocolToolCall> toolCalls = const <AiProtocolToolCall>[],
    List<Map<String, Object?>> responsesOutputItems =
        const <Map<String, Object?>>[],
  }) : this._(
          AiProtocolMessageRole.assistant,
          content,
          toolCalls: toolCalls,
          responsesOutputItems: responsesOutputItems,
        );

  const AiProtocolRequestMessage.toolResults(List<AiProtocolToolResult> results)
      : this._(AiProtocolMessageRole.tool, '', toolResults: results);

  final AiProtocolMessageRole role;
  final String content;
  final List<AiProtocolToolCall> toolCalls;
  final List<AiProtocolToolResult> toolResults;

  /// Raw OpenAI Responses output items, including reasoning and function-call
  /// items. Only the Responses adapter reads this field.
  final List<Map<String, Object?>> responsesOutputItems;
}

/// Which tool the first request should steer the model toward.
final class AiProtocolToolChoice {
  const AiProtocolToolChoice.auto()
      : type = 'auto',
        name = null;

  const AiProtocolToolChoice.tool(String this.name) : type = 'tool';

  final String type;
  final String? name;
}

/// A decoded model response plus the protocol-specific assistant turn that
/// must be appended before tool results are sent back.
final class AiProtocolResponse {
  const AiProtocolResponse({
    required this.text,
    required this.toolCalls,
    required this.appendMessages,
    this.outputItems = const <Map<String, Object?>>[],
  });

  final String text;
  final List<AiProtocolToolCall> toolCalls;
  final List<AiProtocolRequestMessage> appendMessages;

  /// Original OpenAI Responses output items needed for the next manual
  /// context round. This keeps reasoning and all function calls intact.
  final List<Map<String, Object?>> outputItems;
}

/// Adapts one AI provider protocol: endpoint, authentication, request
/// encoding, response normalization, and tool-result framing.
abstract interface class AiProtocolAdapter {
  String get label;

  Uri endpoint(AiSettings settings);

  Map<String, String> headers(AiSettings settings);

  Map<String, Object?> encodeRequest({
    required AiSettings settings,
    required List<AiProtocolRequestMessage> messages,
    List<AiProtocolTool> tools = const <AiProtocolTool>[],
    AiProtocolToolChoice? toolChoice,
    double temperature = 0.5,
    int maxTokens = 1024,
  });

  AiProtocolResponse decodeResponse(String body);

  /// Messages to append after the assistant turn: the assistant's own turn
  /// plus one message carrying all tool results.
  List<AiProtocolRequestMessage> toolResultMessages(
    AiProtocolResponse response,
    List<AiProtocolToolResult> results,
  );
}

/// OpenAI Chat Completions: `POST {base}/chat/completions` with
/// `Authorization: Bearer`. Default protocol, unchanged behavior.
final class OpenAiChatCompletionsAdapter implements AiProtocolAdapter {
  const OpenAiChatCompletionsAdapter();

  @override
  String get label => 'OpenAI Chat Completions';

  @override
  Uri endpoint(AiSettings settings) {
    final base = Uri.parse(settings.baseUrl.trim());
    final path = base.path.endsWith('/')
        ? '${base.path}chat/completions'
        : '${base.path}/chat/completions';
    return base.replace(path: path);
  }

  @override
  Map<String, String> headers(AiSettings settings) => <String, String>{
        'Accept': 'application/json',
        'Content-Type': 'application/json',
        'Authorization': 'Bearer ${settings.apiKey}',
      };

  @override
  Map<String, Object?> encodeRequest({
    required AiSettings settings,
    required List<AiProtocolRequestMessage> messages,
    List<AiProtocolTool> tools = const <AiProtocolTool>[],
    AiProtocolToolChoice? toolChoice,
    double temperature = 0.5,
    int maxTokens = 1024,
  }) =>
      <String, Object?>{
        'model': settings.model,
        'messages': <Object?>[
          for (final message in messages) ..._encodeMessage(message),
        ],
        'temperature': temperature,
        if (tools.isNotEmpty)
          'tools': <Object?>[
            for (final tool in tools)
              <String, Object?>{
                'type': 'function',
                'function': <String, Object?>{
                  'name': tool.name,
                  'description': tool.description,
                  'parameters': tool.parameters,
                },
              },
          ],
        if (toolChoice != null) 'tool_choice': _encodeToolChoice(toolChoice),
        'max_tokens': maxTokens,
      };

  @override
  AiProtocolResponse decodeResponse(String body) {
    final payload = _object(jsonDecode(body), 'AI response');
    final choices = payload['choices'];
    if (choices is! List || choices.isEmpty) {
      throw const AiSchemaFailure('AI 响应缺少 choices。');
    }
    final message = _object(
      _object(choices.first, 'AI choice')['message'],
      'AI message',
    );
    final rawContent = message['content'];
    final text = rawContent is String ? rawContent : '';
    final toolCalls = <AiProtocolToolCall>[];
    final rawCalls = message['tool_calls'];
    if (rawCalls is List) {
      for (final rawCall in rawCalls) {
        final call = _object(rawCall, 'tool call');
        final function = _object(call['function'], 'tool function');
        toolCalls.add(
          AiProtocolToolCall(
            id: _requiredString(call, 'id'),
            name: _requiredString(function, 'name'),
            arguments: _object(
              jsonDecode(_requiredString(function, 'arguments')),
              'tool arguments',
            ),
          ),
        );
      }
    }
    if (text.trim().isEmpty && toolCalls.isEmpty) {
      throw const AiSchemaFailure('AI 响应缺少消息内容。');
    }
    return AiProtocolResponse(
      text: text.trim(),
      toolCalls: toolCalls,
      appendMessages: <AiProtocolRequestMessage>[
        AiProtocolRequestMessage.assistant(text, toolCalls: toolCalls),
      ],
    );
  }

  @override
  List<AiProtocolRequestMessage> toolResultMessages(
    AiProtocolResponse response,
    List<AiProtocolToolResult> results,
  ) =>
      <AiProtocolRequestMessage>[
        ...response.appendMessages,
        AiProtocolRequestMessage.toolResults(results),
      ];

  List<Map<String, Object?>> _encodeMessage(
    AiProtocolRequestMessage message,
  ) {
    switch (message.role) {
      case AiProtocolMessageRole.system:
        return <Map<String, Object?>>[
          <String, Object?>{'role': 'system', 'content': message.content},
        ];
      case AiProtocolMessageRole.user:
        return <Map<String, Object?>>[
          <String, Object?>{'role': 'user', 'content': message.content},
        ];
      case AiProtocolMessageRole.assistant:
        return <Map<String, Object?>>[
          <String, Object?>{
            'role': 'assistant',
            'content': message.content,
            if (message.toolCalls.isNotEmpty)
              'tool_calls': <Object?>[
                for (final call in message.toolCalls)
                  <String, Object?>{
                    'id': call.id,
                    'type': 'function',
                    'function': <String, Object?>{
                      'name': call.name,
                      'arguments': jsonEncode(call.arguments),
                    },
                  },
              ],
          },
        ];
      case AiProtocolMessageRole.tool:
        return <Map<String, Object?>>[
          for (final result in message.toolResults)
            <String, Object?>{
              'role': 'tool',
              'tool_call_id': result.toolCallId,
              'content': result.content,
            },
        ];
    }
  }

  Object? _encodeToolChoice(AiProtocolToolChoice choice) =>
      switch (choice.type) {
        'auto' => 'auto',
        _ => <String, Object?>{
            'type': 'function',
            'function': <String, String>{'name': choice.name!},
          },
      };
}

/// OpenAI Responses API: `POST {base}/responses` with
/// `Authorization: Bearer` and `function_call` / `function_call_output`
/// input items for tool rounds.
final class OpenAiResponsesAdapter implements AiProtocolAdapter {
  const OpenAiResponsesAdapter();

  @override
  String get label => 'OpenAI Responses';

  @override
  Uri endpoint(AiSettings settings) {
    final base = Uri.parse(settings.baseUrl.trim());
    final path = base.path.endsWith('/')
        ? '${base.path}responses'
        : '${base.path}/responses';
    return base.replace(path: path);
  }

  @override
  Map<String, String> headers(AiSettings settings) => <String, String>{
        'Accept': 'application/json',
        'Content-Type': 'application/json',
        'Authorization': 'Bearer ${settings.apiKey}',
      };

  @override
  Map<String, Object?> encodeRequest({
    required AiSettings settings,
    required List<AiProtocolRequestMessage> messages,
    List<AiProtocolTool> tools = const <AiProtocolTool>[],
    AiProtocolToolChoice? toolChoice,
    double temperature = 0.5,
    int maxTokens = 1024,
  }) =>
      <String, Object?>{
        'model': settings.model,
        'input': <Object?>[
          for (final message in messages) ..._encodeMessage(message),
        ],
        'temperature': temperature,
        if (tools.isNotEmpty)
          'tools': <Object?>[
            for (final tool in tools)
              <String, Object?>{
                'type': 'function',
                'name': tool.name,
                'description': tool.description,
                'parameters': tool.parameters,
              },
          ],
        if (toolChoice != null) 'tool_choice': _encodeToolChoice(toolChoice),
        'max_output_tokens': maxTokens,
      };

  @override
  AiProtocolResponse decodeResponse(String body) {
    final payload = _object(jsonDecode(body), 'AI response');
    final output = payload['output'];
    if (output is! List) {
      throw const AiSchemaFailure('AI 响应缺少 output。');
    }
    final textParts = <String>[];
    final toolCalls = <AiProtocolToolCall>[];
    final outputItems = <Map<String, Object?>>[];
    for (final rawItem in output) {
      final item = _object(rawItem, 'response item');
      outputItems.add(item);
      switch (item['type']) {
        case 'function_call':
          final rawId = item['call_id'] ?? item['id'];
          if (rawId is! String || rawId.isEmpty) {
            throw const AiSchemaFailure('AI 响应缺少 function_call 调用 ID。');
          }
          final name = _requiredString(item, 'name');
          final rawArguments = item['arguments'];
          final arguments = _object(
            jsonDecode(rawArguments is String ? rawArguments : '{}'),
            'tool arguments',
          );
          toolCalls.add(
            AiProtocolToolCall(id: rawId, name: name, arguments: arguments),
          );
        case 'message':
          final rawContent = item['content'];
          if (rawContent is List) {
            for (final rawBlock in rawContent) {
              final block = _object(rawBlock, 'content block');
              if (block['type'] == 'output_text' &&
                  block['text'] is String) {
                final text = block['text'] as String;
                textParts.add(text);
              }
            }
          }
        default:
          break;
      }
    }
    final text = textParts.join();
    if (text.trim().isEmpty && toolCalls.isEmpty) {
      throw const AiSchemaFailure('AI 响应缺少消息内容。');
    }
    return AiProtocolResponse(
      text: text.trim(),
      toolCalls: toolCalls,
      appendMessages: <AiProtocolRequestMessage>[
        AiProtocolRequestMessage.assistant(
          '',
          responsesOutputItems: outputItems,
        ),
      ],
      outputItems: outputItems,
    );
  }

  @override
  List<AiProtocolRequestMessage> toolResultMessages(
    AiProtocolResponse response,
    List<AiProtocolToolResult> results,
  ) =>
      <AiProtocolRequestMessage>[
        AiProtocolRequestMessage.assistant(
          '',
          responsesOutputItems: response.outputItems,
        ),
        AiProtocolRequestMessage.toolResults(results),
      ];

  List<Map<String, Object?>> _encodeMessage(
    AiProtocolRequestMessage message,
  ) {
    if (message.responsesOutputItems.isNotEmpty) {
      return message.responsesOutputItems;
    }
    switch (message.role) {
      case AiProtocolMessageRole.system:
      case AiProtocolMessageRole.user:
        return <Map<String, Object?>>[
          <String, Object?>{
            'type': 'message',
            'role': message.role == AiProtocolMessageRole.system
                ? 'system'
                : 'user',
            'content': <Object?>[
              <String, String>{'type': 'input_text', 'text': message.content},
            ],
          },
        ];
      case AiProtocolMessageRole.assistant:
        if (message.toolCalls.isNotEmpty) {
          return <Map<String, Object?>>[
            for (final call in message.toolCalls)
              <String, Object?>{
                'type': 'function_call',
                'call_id': call.id,
                'name': call.name,
                'arguments': jsonEncode(call.arguments),
              },
          ];
        }
        return <Map<String, Object?>>[
          <String, Object?>{
            'type': 'message',
            'role': 'assistant',
            'content': <Object?>[
              <String, String>{
                'type': 'output_text',
                'text': message.content,
              },
            ],
          },
        ];
      case AiProtocolMessageRole.tool:
        return <Map<String, Object?>>[
          for (final result in message.toolResults)
            <String, Object?>{
              'type': 'function_call_output',
              'call_id': result.toolCallId,
              'output': result.content,
            },
        ];
    }
  }

  Object? _encodeToolChoice(AiProtocolToolChoice choice) =>
      switch (choice.type) {
        'auto' => 'auto',
        _ => <String, Object?>{
            'type': 'function',
            'name': choice.name!,
          },
      };
}

/// Anthropic Messages API: `POST {base}/v1/messages` with `x-api-key` and
/// `anthropic-version` headers, top-level `system`, and `tool_use` /
/// `tool_result` content blocks.
final class AnthropicMessagesAdapter implements AiProtocolAdapter {
  const AnthropicMessagesAdapter();

  static const _apiVersion = '2023-06-01';

  @override
  String get label => 'Anthropic Messages';

  @override
  Uri endpoint(AiSettings settings) {
    final base = Uri.parse(settings.baseUrl.trim());
    var path = base.path;
    if (path.endsWith('/')) {
      path = path.substring(0, path.length - 1);
    }
    if (path.endsWith('/v1')) {
      path = path.substring(0, path.length - 3);
    }
    return base.replace(path: '$path/v1/messages');
  }

  @override
  Map<String, String> headers(AiSettings settings) => <String, String>{
        'Accept': 'application/json',
        'Content-Type': 'application/json',
        'x-api-key': settings.apiKey,
        'anthropic-version': _apiVersion,
      };

  @override
  Map<String, Object?> encodeRequest({
    required AiSettings settings,
    required List<AiProtocolRequestMessage> messages,
    List<AiProtocolTool> tools = const <AiProtocolTool>[],
    AiProtocolToolChoice? toolChoice,
    double temperature = 0.5,
    int maxTokens = 1024,
  }) {
    final systemParts = <String>[];
    final anthropicMessages = <Object?>[];
    for (final message in messages) {
      switch (message.role) {
        case AiProtocolMessageRole.system:
          if (message.content.trim().isNotEmpty) {
            systemParts.add(message.content.trim());
          }
        case AiProtocolMessageRole.user:
          anthropicMessages.add(<String, Object?>{
            'role': 'user',
            'content': <Object?>[
              <String, String>{'type': 'text', 'text': message.content},
            ],
          });
        case AiProtocolMessageRole.assistant:
          final blocks = <Object?>[];
          if (message.content.trim().isNotEmpty) {
            blocks.add(<String, String>{
              'type': 'text',
              'text': message.content.trim(),
            });
          }
          for (final call in message.toolCalls) {
            blocks.add(<String, Object?>{
              'type': 'tool_use',
              'id': call.id,
              'name': call.name,
              'input': call.arguments,
            });
          }
          if (blocks.isEmpty) {
            continue;
          }
          anthropicMessages.add(<String, Object?>{
            'role': 'assistant',
            'content': blocks,
          });
        case AiProtocolMessageRole.tool:
          if (message.toolResults.isEmpty) {
            continue;
          }
          anthropicMessages.add(<String, Object?>{
            'role': 'user',
            'content': <Object?>[
              for (final result in message.toolResults)
                <String, Object?>{
                  'type': 'tool_result',
                  'tool_use_id': result.toolCallId,
                  'content': result.content,
                },
            ],
          });
      }
    }
    return <String, Object?>{
      'model': settings.model,
      'max_tokens': maxTokens,
      'temperature': temperature,
      if (systemParts.isNotEmpty) 'system': systemParts.join('\n\n'),
      'messages': anthropicMessages,
      if (tools.isNotEmpty)
        'tools': <Object?>[
          for (final tool in tools)
            <String, Object?>{
              'name': tool.name,
              'description': tool.description,
              'input_schema': tool.parameters,
            },
        ],
      if (toolChoice != null) 'tool_choice': _encodeToolChoice(toolChoice),
    };
  }

  @override
  AiProtocolResponse decodeResponse(String body) {
    final payload = _object(jsonDecode(body), 'AI response');
    final rawContent = payload['content'];
    if (rawContent is! List) {
      throw const AiSchemaFailure('AI 响应缺少 content。');
    }
    final textParts = <String>[];
    final toolCalls = <AiProtocolToolCall>[];
    final blocks = <Object?>[];
    for (final rawBlock in rawContent) {
      final block = _object(rawBlock, 'content block');
      switch (block['type']) {
        case 'text':
          if (block['text'] is String && (block['text'] as String).isNotEmpty) {
            final text = block['text'] as String;
            textParts.add(text);
            blocks.add(<String, String>{'type': 'text', 'text': text});
          }
        case 'tool_use':
          final id = _requiredString(block, 'id');
          final name = _requiredString(block, 'name');
          final rawInput = block['input'];
          if (rawInput is! Map) {
            throw const AiSchemaFailure('工具参数必须是对象。');
          }
          final arguments = _object(rawInput, 'tool input');
          toolCalls.add(
            AiProtocolToolCall(id: id, name: name, arguments: arguments),
          );
          blocks.add(<String, Object?>{
            'type': 'tool_use',
            'id': id,
            'name': name,
            'input': arguments,
          });
        default:
          break;
      }
    }
    final text = textParts.join();
    if (text.trim().isEmpty && toolCalls.isEmpty) {
      throw const AiSchemaFailure('AI 响应缺少消息内容。');
    }
    return AiProtocolResponse(
      text: text.trim(),
      toolCalls: toolCalls,
      appendMessages: <AiProtocolRequestMessage>[
        AiProtocolRequestMessage.assistant(text, toolCalls: toolCalls),
      ],
    );
  }

  @override
  List<AiProtocolRequestMessage> toolResultMessages(
    AiProtocolResponse response,
    List<AiProtocolToolResult> results,
  ) =>
      <AiProtocolRequestMessage>[
        ...response.appendMessages,
        AiProtocolRequestMessage.toolResults(results),
      ];

  Object? _encodeToolChoice(AiProtocolToolChoice choice) =>
      switch (choice.type) {
        'auto' => 'auto',
        _ => <String, Object?>{
            'type': 'tool',
            'name': choice.name!,
          },
      };
}

Map<String, Object?> _object(Object? value, String label) {
  if (value is! Map) {
    throw AiSchemaFailure('$label must be an object.');
  }
  final result = <String, Object?>{};
  for (final entry in value.entries) {
    if (entry.key is! String) {
      throw AiSchemaFailure('$label contains a non-string key.');
    }
    result[entry.key as String] = entry.value;
  }
  return result;
}

String _requiredString(Map<String, Object?> json, String key) {
  final value = json[key];
  if (value is! String || value.isEmpty) {
    throw AiSchemaFailure('$key must be a non-empty string.');
  }
  return value;
}
