import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:studyflow/features/ai/ai_repository.dart';
import 'package:studyflow/features/ai/ai_settings_model.dart';
import 'package:studyflow/features/ai/ai_settings_screen.dart';

final class MemoryAiSettingsStore implements AiSettingsStore {
  MemoryAiSettingsStore({this.initial = AiSettings.empty});

  AiSettings initial;

  @override
  Future<AiSettings> read() async => initial;

  @override
  Future<void> write(AiSettings settings) async {
    initial = settings;
  }

  @override
  Future<void> clear() async {
    initial = AiSettings.empty;
  }
}

final class RecordingAiRepository implements AiRepository {
  RecordingAiRepository({this.failTest = false});

  bool failTest;
  AiSettings? lastTestSettings;
  AiSettings? lastRequestSettings;

  @override
  Future<AiRecommendation> requestRecommendation({
    required AiSettings settings,
    required List<String> taskTitles,
    required Map<String, double> scheduleMetrics,
    required Map<String, double> focusCompletionMetrics,
    required Map<String, double> sleepAggregates,
  }) async {
    lastRequestSettings = settings;
    return AiRecommendation(
      summary: 'Focus on the morning study block.',
      reasonCodes: const <String>['morning_focus'],
      candidateChanges: const <CandidateScheduleChange>[],
    );
  }

  @override
  Future<void> testConnection(AiSettings settings) async {
    lastTestSettings = settings;
    if (failTest) {
      throw const AiAuthenticationFailure('API Key 无效，请检查后重试。');
    }
  }
}

void main() {
  testWidgets('loads and shows saved AI settings', (tester) async {
    final store = MemoryAiSettingsStore(
      initial: const AiSettings(
        baseUrl: 'https://api.openai.com/v1',
        model: 'gpt-4o-mini',
        apiKey: 'sk-secret',
        enabled: true,
      ),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: AiSettingsScreen(store: store, repository: RecordingAiRepository()),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      tester
          .widget<TextFormField>(find.byKey(const Key('ai-base-url-field')))
          .controller
          ?.text,
      'https://api.openai.com/v1',
    );
    expect(
      tester
          .widget<TextFormField>(find.byKey(const Key('ai-model-field')))
          .controller
          ?.text,
      'gpt-4o-mini',
    );
    expect(
      tester
          .widget<TextFormField>(find.byKey(const Key('ai-api-key-field')))
          .controller
          ?.text,
      'sk-secret',
    );
    expect(tester.widget<SwitchListTile>(
      find.byKey(const Key('ai-enabled-switch')),
    ).value, isTrue);
  });

  testWidgets('saving persists settings and masks nothing in plain log',
      (tester) async {
    final store = MemoryAiSettingsStore();
    await tester.pumpWidget(
      MaterialApp(
        home: AiSettingsScreen(store: store, repository: RecordingAiRepository()),
      ),
    );
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byKey(const Key('ai-base-url-field')),
      'https://api.openai.com/v1',
    );
    await tester.enterText(
      find.byKey(const Key('ai-model-field')),
      'gpt-4o-mini',
    );
    await tester.enterText(
      find.byKey(const Key('ai-api-key-field')),
      'sk-secret-key',
    );
    await tester.tap(find.byKey(const Key('ai-save-button')));
    await tester.pumpAndSettle();

    expect(store.initial.baseUrl, 'https://api.openai.com/v1');
    expect(store.initial.model, 'gpt-4o-mini');
    expect(store.initial.apiKey, 'sk-secret-key');
    expect(store.initial.enabled, isFalse);
    expect(find.text('已保存'), findsOneWidget);
  });

  testWidgets('connection test reports success', (tester) async {
    final repository = RecordingAiRepository();
    await tester.pumpWidget(
      MaterialApp(
        home: AiSettingsScreen(
          store: MemoryAiSettingsStore(),
          repository: repository,
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byKey(const Key('ai-base-url-field')),
      'https://api.openai.com/v1',
    );
    await tester.enterText(
      find.byKey(const Key('ai-model-field')),
      'gpt-4o-mini',
    );
    await tester.enterText(
      find.byKey(const Key('ai-api-key-field')),
      'sk-secret-key',
    );
    await tester.tap(find.byKey(const Key('ai-test-button')));
    await tester.pumpAndSettle();

    expect(repository.lastTestSettings?.model, 'gpt-4o-mini');
    expect(find.text('连接成功'), findsOneWidget);
  });

  testWidgets('connection test failure shows a readable message',
      (tester) async {
    final repository = RecordingAiRepository(failTest: true);
    await tester.pumpWidget(
      MaterialApp(
        home: AiSettingsScreen(
          store: MemoryAiSettingsStore(),
          repository: repository,
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byKey(const Key('ai-base-url-field')),
      'https://api.openai.com/v1',
    );
    await tester.enterText(
      find.byKey(const Key('ai-model-field')),
      'gpt-4o-mini',
    );
    await tester.enterText(
      find.byKey(const Key('ai-api-key-field')),
      'sk-secret-key',
    );
    await tester.tap(find.byKey(const Key('ai-test-button')));
    await tester.pumpAndSettle();

    expect(find.text('连接失败：API Key 无效，请检查后重试。'), findsOneWidget);
  });

  testWidgets('clear removes the saved configuration after confirmation',
      (tester) async {
    final store = MemoryAiSettingsStore(
      initial: const AiSettings(
        baseUrl: 'https://api.openai.com/v1',
        model: 'gpt-4o-mini',
        apiKey: 'sk-secret',
        enabled: true,
      ),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: AiSettingsScreen(store: store, repository: RecordingAiRepository()),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('ai-clear-button')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('ai-clear-confirm-button')));
    await tester.pumpAndSettle();

    expect(store.initial.baseUrl, isEmpty);
    expect(store.initial.model, isEmpty);
    expect(store.initial.apiKey, isEmpty);
    expect(store.initial.enabled, isFalse);
    expect(find.text('已清除'), findsOneWidget);
  });

  test('AiSettings.toString never contains the API key', () {
    const settings = AiSettings(
      baseUrl: 'https://api.openai.com/v1',
      model: 'gpt-4o-mini',
      apiKey: 'sk-super-secret-key',
      enabled: true,
    );

    final rendered = settings.toString();

    expect(rendered, isNot(contains('sk-super-secret-key')));
    expect(rendered, contains('<redacted>'));
  });

  test('validateAiBaseUrl requires HTTPS', () {
    expect(validateAiBaseUrl('http://api.openai.com/v1'), isNotNull);
    expect(validateAiBaseUrl('https://api.openai.com/v1'), isNull);
    expect(validateAiBaseUrl('http://localhost:8000/v1'), isNull);
  });
}
