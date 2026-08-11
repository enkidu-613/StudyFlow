import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:studyflow/features/ai/ai_settings_model.dart';

/// A validated AI recommendation that never mutates local tasks or schedule
/// blocks on its own; any change requires explicit user confirmation.
final class AiRecommendation {
  AiRecommendation({
    required this.summary,
    required this.candidateChanges,
    required this.reasonCodes,
  });

  factory AiRecommendation.fromJson(Map<String, Object?> json) {
    final changes = json['candidateChanges'];
    if (changes is! List) {
      throw const AiSchemaFailure('AI response must contain a changes list.');
    }
    return AiRecommendation(
      summary: _requiredString(json, 'summary'),
      candidateChanges: changes
          .map(
            (change) => CandidateScheduleChange.fromJson(
              _object(change, 'candidate change').cast<String, Object?>(),
            ),
          )
          .toList(growable: false),
      reasonCodes: _optionalStringList(json['reasonCodes'], 'reasonCodes'),
    );
  }

  final String summary;
  final List<CandidateScheduleChange> candidateChanges;
  final List<String> reasonCodes;
}

final class CandidateScheduleChange {
  CandidateScheduleChange({
    required this.action,
    required this.blockId,
    required this.deltaMinutes,
    required this.reason,
  });

  factory CandidateScheduleChange.fromJson(Map<String, Object?> json) =>
      CandidateScheduleChange(
        action: _requiredString(json, 'action'),
        blockId: _requiredString(json, 'blockId'),
        deltaMinutes: json['deltaMinutes']! as int,
        reason: _requiredString(json, 'reason'),
      );

  final String action;
  final String blockId;
  final int deltaMinutes;
  final String reason;
}

/// Calls the user-configured OpenAI-compatible endpoint from the client.
/// The API key stays in the device secure storage and never leaves it.
abstract interface class AiRepository {
  Future<AiRecommendation> requestRecommendation({
    required AiSettings settings,
    required List<String> taskTitles,
    required Map<String, double> scheduleMetrics,
    required Map<String, double> focusCompletionMetrics,
    required Map<String, double> sleepAggregates,
  });

  Future<void> testConnection(AiSettings settings);
}

final class HttpAiRepository implements AiRepository {
  HttpAiRepository({http.Client? client})
      : _client = client ?? http.Client();

  static const _timeout = Duration(seconds: 30);

  final http.Client _client;

  @override
  Future<AiRecommendation> requestRecommendation({
    required AiSettings settings,
    required List<String> taskTitles,
    required Map<String, double> scheduleMetrics,
    required Map<String, double> focusCompletionMetrics,
    required Map<String, double> sleepAggregates,
  }) async {
    final prompt = _buildPrompt(
      taskTitles: taskTitles,
      scheduleMetrics: scheduleMetrics,
      focusCompletionMetrics: focusCompletionMetrics,
      sleepAggregates: sleepAggregates,
    );
    final body = <String, Object?>{
      'model': settings.model,
      'messages': <Object?>[
        <String, Object?>{'role': 'system', 'content': _systemPrompt},
        <String, Object?>{'role': 'user', 'content': prompt},
      ],
      'temperature': 0.4,
    };
    try {
      final response = await _client
          .post(
            _chatUri(settings),
            headers: _headers(settings),
            body: jsonEncode(body),
          )
          .timeout(_timeout);
      final content = _extractContent(response);
      return AiRecommendation.fromJson(
        _object(jsonDecode(content), 'AI content').cast<String, Object?>(),
      );
    } on AiApiFailure {
      rethrow;
    } on SocketException catch (error) {
      throw AiNetworkFailure('网络连接失败，请检查网络后重试。', cause: error);
    } on http.ClientException catch (error) {
      throw AiNetworkFailure('AI 请求失败。', cause: error);
    } on TimeoutException catch (error) {
      throw AiNetworkFailure('AI 请求超时。', cause: error);
    } on FormatException catch (error) {
      throw AiSchemaFailure('AI 响应不是有效的 JSON。', cause: error);
    }
  }

  @override
  Future<void> testConnection(AiSettings settings) async {
    final body = <String, Object?>{
      'model': settings.model,
      'messages': <Object?>[
        <String, Object?>{'role': 'user', 'content': 'ping'},
      ],
      'max_tokens': 1,
    };
    try {
      final response = await _client
          .post(
            _chatUri(settings),
            headers: _headers(settings),
            body: jsonEncode(body),
          )
          .timeout(_timeout);
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw AiNetworkFailure('AI 服务返回 HTTP ${response.statusCode}。');
      }
    } on AiApiFailure {
      rethrow;
    } on SocketException catch (error) {
      throw AiNetworkFailure('无法连接 AI 服务，请检查网络与地址。', cause: error);
    } on http.ClientException catch (error) {
      throw AiNetworkFailure('AI 请求失败。', cause: error);
    } on TimeoutException catch (error) {
      throw AiNetworkFailure('AI 请求超时。', cause: error);
    }
  }

  String _extractContent(http.Response response) {
    if (response.statusCode == 401 || response.statusCode == 403) {
      throw const AiAuthenticationFailure('API Key 无效，请检查后重试。');
    }
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw AiNetworkFailure('AI 服务返回 HTTP ${response.statusCode}。');
    }
    final json = _object(jsonDecode(response.body), 'AI response');
    final choices = json['choices'];
    if (choices is! List || choices.isEmpty) {
      throw const AiSchemaFailure('AI 响应缺少 choices。');
    }
    final first = _object(choices.first, 'AI choice');
    final message = _object(first['message'], 'AI message');
    final content = message['content'];
    if (content is! String || content.isEmpty) {
      throw const AiSchemaFailure('AI 响应缺少消息内容。');
    }
    return content;
  }

  Map<String, String> _headers(AiSettings settings) => <String, String>{
        'Accept': 'application/json',
        'Content-Type': 'application/json',
        'Authorization': 'Bearer ${settings.apiKey}',
      };

  Uri _chatUri(AiSettings settings) {
    final base = Uri.parse(settings.baseUrl.trim());
    final path = base.path.endsWith('/')
        ? '${base.path}chat/completions'
        : '${base.path}/chat/completions';
    return base.replace(path: path);
  }

  String _buildPrompt({
    required List<String> taskTitles,
    required Map<String, double> scheduleMetrics,
    required Map<String, double> focusCompletionMetrics,
    required Map<String, double> sleepAggregates,
  }) =>
      jsonEncode(<String, Object?>{
        'taskTitles': taskTitles,
        'scheduleMetrics': scheduleMetrics,
        'focusCompletionMetrics': focusCompletionMetrics,
        'sleepAggregates': sleepAggregates,
      });

  static const String _systemPrompt =
      'You are a study-schedule assistant. Return ONLY a JSON object with '
      'keys "summary" (string), "reasonCodes" (string array), and '
      '"candidateChanges" (array of objects with "action", "blockId", '
      '"deltaMinutes" int, and "reason"). Never invent schedule blocks that '
      'do not exist.';
}

sealed class AiApiFailure implements Exception {
  const AiApiFailure(this.message, {this.cause});

  final String message;
  final Object? cause;

  @override
  String toString() {
    final causeText = cause == null ? '' : ' (cause: $cause)';
    return '$message$causeText';
  }
}

final class AiAuthenticationFailure extends AiApiFailure {
  const AiAuthenticationFailure(super.message, {super.cause});
}

final class AiNetworkFailure extends AiApiFailure {
  const AiNetworkFailure(super.message, {super.cause});
}

final class AiSchemaFailure extends AiApiFailure {
  const AiSchemaFailure(super.message, {super.cause});
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

List<String> _optionalStringList(Object? value, String label) {
  if (value == null) {
    return const <String>[];
  }
  if (value is! List || value.any((item) => item is! String)) {
    throw AiSchemaFailure('$label must be a string list.');
  }
  return value.cast<String>();
}
