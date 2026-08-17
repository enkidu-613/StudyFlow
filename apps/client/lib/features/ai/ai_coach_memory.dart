import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:studyflow/features/ai/ai_repository.dart';

/// Stores the coach conversation on this device only, isolated by account.
abstract interface class AiCoachMemoryStore {
  Future<AiCoachMemory> load({required String accountId});

  Future<void> save({
    required String accountId,
    required AiCoachMemory memory,
  });

  Future<void> clear({required String accountId});
}

final class AiCoachMemory {
  const AiCoachMemory({
    required this.summary,
    required this.messages,
    this.tracesByMessageIndex = const <int, List<AiToolTrace>>{},
  });

  const AiCoachMemory.empty()
      : summary = '',
        messages = const <AiCoachMessage>[],
        tracesByMessageIndex = const <int, List<AiToolTrace>>{};

  final String summary;
  final List<AiCoachMessage> messages;
  final Map<int, List<AiToolTrace>> tracesByMessageIndex;

  Map<String, Object?> toJson() => <String, Object?>{
        'summary': summary,
        'messages': messages.map((message) => message.toJson()).toList(),
        'traces': tracesByMessageIndex.map<String, Object?>(
          (index, traces) => MapEntry<String, Object?>(
            '$index',
            traces.map((trace) => trace.toJson()).toList(),
          ),
        ),
      };

  static AiCoachMemory fromJson(Object? value) {
    if (value is List) {
      return AiCoachMemory(
        summary: '',
        messages: _messagesFromJson(value),
      );
    }
    final object = _jsonObject(value, 'conversation memory');
    final summary = object['summary'];
    final messages = object['messages'];
    if (summary is! String || messages is! List) {
      throw const FormatException('Conversation memory has an invalid shape.');
    }
    return AiCoachMemory(
      summary: summary,
      messages: _messagesFromJson(messages),
      tracesByMessageIndex: _tracesFromJson(object['traces']),
    );
  }

  static List<AiCoachMessage> _messagesFromJson(List values) => values
      .map(
        (item) => AiCoachMessage.fromJson(
          _jsonObject(item, 'conversation message'),
        ),
      )
      .toList(growable: false);

  static Map<int, List<AiToolTrace>> _tracesFromJson(Object? value) {
    if (value == null) return const <int, List<AiToolTrace>>{};
    final object = _jsonObject(value, 'conversation tool traces');
    final traces = <int, List<AiToolTrace>>{};
    for (final entry in object.entries) {
      final index = int.tryParse(entry.key);
      if (index == null || index < 0 || entry.value is! List) {
        throw const FormatException('Conversation tool traces are invalid.');
      }
      traces[index] = (entry.value as List)
          .map(
            (item) => AiToolTrace.fromJson(
              _jsonObject(item, 'conversation tool trace'),
            ),
          )
          .toList(growable: false);
    }
    return traces;
  }
}

final class SecureAiCoachMemoryStore implements AiCoachMemoryStore {
  SecureAiCoachMemoryStore({FlutterSecureStorage? storage})
      : _storage = storage ??
            const FlutterSecureStorage(
              aOptions: AndroidOptions(
                resetOnError: false,
                storageNamespace: 'studyflow.ai-coach.v1',
              ),
              mOptions: MacOsOptions(
                accessibility: KeychainAccessibility.unlocked_this_device,
                synchronizable: false,
                usesDataProtectionKeychain: false,
              ),
            );

  static const _keyPrefix = 'studyflow.ai-coach.history.v1.';
  final FlutterSecureStorage _storage;

  @override
  Future<AiCoachMemory> load({required String accountId}) async {
    final encoded = await _storage.read(key: _key(accountId));
    if (encoded == null || encoded.isEmpty) return const AiCoachMemory.empty();
    try {
      return AiCoachMemory.fromJson(jsonDecode(encoded));
    } on FormatException {
      await clear(accountId: accountId);
      return const AiCoachMemory.empty();
    } on AiSchemaFailure {
      await clear(accountId: accountId);
      return const AiCoachMemory.empty();
    }
  }

  @override
  Future<void> save({
    required String accountId,
    required AiCoachMemory memory,
  }) =>
      _storage.write(
        key: _key(accountId),
        value: jsonEncode(memory.toJson()),
      );

  @override
  Future<void> clear({required String accountId}) =>
      _storage.delete(key: _key(accountId));

  String _key(String accountId) => '$_keyPrefix$accountId';
}

Map<String, Object?> _jsonObject(Object? value, String label) {
  if (value is! Map) {
    throw FormatException('$label must be an object.');
  }
  return value.map<String, Object?>((key, value) {
    if (key is! String) {
      throw FormatException('$label contains a non-string key.');
    }
    return MapEntry<String, Object?>(key, value);
  });
}
