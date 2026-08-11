import 'dart:convert';

import 'package:http/http.dart' as http;

/// A validated AI recommendation that never mutates local tasks or schedule
/// blocks on its own; any change requires explicit user confirmation.
final class AiRecommendation {
  AiRecommendation({
    required this.recommendationId,
    required this.permissionLevel,
    required this.summary,
    required this.reasonCodes,
    required this.confidence,
    required this.requiresConfirmation,
    required this.candidateChanges,
  });

  factory AiRecommendation.fromJson(Map<String, Object?> json) {
    final recommendation =
        _object(json['recommendation'], 'recommendation response');
    const expectedKeys = <String>{
      'recommendationId',
      'permissionLevel',
      'summary',
      'reasonCodes',
      'confidence',
      'requiresConfirmation',
      'candidateChanges',
    };
    if (recommendation.keys.toSet().difference(expectedKeys).isNotEmpty ||
        expectedKeys.difference(recommendation.keys.toSet()).isNotEmpty) {
      throw const AiSchemaFailure(
          'AI recommendation has unexpected fields.');
    }
    final changes = recommendation['candidateChanges']! as List<Object?>;
    return AiRecommendation(
      recommendationId:
          _requiredString(recommendation, 'recommendationId'),
      permissionLevel:
          _requiredString(recommendation, 'permissionLevel'),
      summary: _requiredString(recommendation, 'summary'),
      reasonCodes: changes.isEmpty
          ? const <String>[]
          : _stringList(recommendation['reasonCodes'], 'reasonCodes'),
      confidence: _requiredDouble(recommendation, 'confidence'),
      requiresConfirmation:
          recommendation['requiresConfirmation']! as bool,
      candidateChanges: changes
          .map(
            (change) => CandidateScheduleChange.fromJson(
              _object(change, 'candidate change').cast<String, Object?>(),
            ),
          )
          .toList(growable: false),
    );
  }

  final String recommendationId;
  final String permissionLevel;
  final String summary;
  final List<String> reasonCodes;
  final double confidence;
  final bool requiresConfirmation;
  final List<CandidateScheduleChange> candidateChanges;
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

/// Fetches L1 recommendations from the StudyFlow API.
abstract interface class AiRepository {
  Future<AiRecommendation> requestRecommendation({
    required String accessToken,
    required String deviceId,
    required String permissionLevel,
    required List<String> taskTitles,
    required Map<String, double> scheduleMetrics,
    required Map<String, double> focusCompletionMetrics,
    required Map<String, double> sleepAggregates,
  });
}

final class HttpAiRepository implements AiRepository {
  HttpAiRepository({required Uri baseUri, http.Client? client})
      : _baseUri = baseUri,
        _client = client ?? http.Client();

  final Uri _baseUri;
  final http.Client _client;

  @override
  Future<AiRecommendation> requestRecommendation({
    required String accessToken,
    required String deviceId,
    required String permissionLevel,
    required List<String> taskTitles,
    required Map<String, double> scheduleMetrics,
    required Map<String, double> focusCompletionMetrics,
    required Map<String, double> sleepAggregates,
  }) async {
    final response = await _client.post(
      _baseUri.resolve('/v1/ai/recommendations'),
      headers: <String, String>{
        'Accept': 'application/json',
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $accessToken',
        'X-Device-Id': deviceId,
      },
      body: jsonEncode(<String, Object?>{
        'summary': <String, Object?>{
          'permissionLevel': permissionLevel,
          'taskIds': <Object?>[],
          'taskTitles': taskTitles,
          'scheduleMetrics': scheduleMetrics,
          'focusCompletionMetrics': focusCompletionMetrics,
          'sleepAggregates': sleepAggregates,
        },
      }),
    );
    if (response.statusCode == 401 || response.statusCode == 403) {
      throw const AiAuthenticationFailure(
          'AI recommendation credentials were rejected.');
    }
    if (response.statusCode == 503) {
      throw const AiUnavailableFailure(
          'AI recommendations are not configured on the server.');
    }
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw AiNetworkFailure(
          'AI server returned HTTP ${response.statusCode}.');
    }
    try {
      return AiRecommendation.fromJson(
        _object(jsonDecode(response.body), 'AI response')
            .cast<String, Object?>(),
      );
    } on AiApiFailure {
      rethrow;
    } on FormatException catch (error) {
      throw AiSchemaFailure(
          'AI response was not valid JSON.',
          cause: error);
    }
  }

  void close() => _client.close();
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

final class AiUnavailableFailure extends AiApiFailure {
  const AiUnavailableFailure(super.message, {super.cause});
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

double _requiredDouble(Map<String, Object?> json, String key) {
  final value = json[key];
  if (value is! num) {
    throw AiSchemaFailure('$key must be a number.');
  }
  return value.toDouble();
}

List<String> _stringList(Object? value, String label) {
  if (value is! List || value.any((item) => item is! String)) {
    throw AiSchemaFailure('$label must be a string list.');
  }
  return value.cast<String>();
}
