import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:studyflow/features/ai/ai_repository.dart';
import 'package:studyflow/features/ai/ai_settings_model.dart';
import 'package:studyflow/features/ai/ai_settings_screen.dart';
import '../../helpers/l10n_test_app.dart';

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
  Future<AiCoachReply> requestCoachReply({
    required AiSettings settings,
    required String userMessage,
    required List<AiCoachMessage> history,
    String conversationSummary = '',
    required List<String> taskTitles,
    required Map<String, double> scheduleMetrics,
    required Map<String, double> focusCompletionMetrics,
    required Map<String, double> sleepAggregates,
    required AiScheduleLookup scheduleLookup,
    AiScheduleFeedbackLookup? feedbackLookup,
    AiMedicationLookup? medicationLookup,
    AiWorkspaceChangeLookup? workspaceChangeLookup,
  }) async =>
      const AiCoachReply('测试回复');

  @override
  Future<String> summarizeCoachMemory({
    required AiSettings settings,
    required String existingSummary,
    required List<AiCoachMessage> messages,
  }) async =>
      existingSummary;

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
    await pumpWithL10n(
      tester,
      AiSettingsScreen(store: store, repository: RecordingAiRepository()),
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
      isEmpty,
    );
    expect(
      tester
          .widget<TextField>(
            find.descendant(
              of: find.byKey(const Key('ai-api-key-field')),
              matching: find.byType(TextField),
            ),
          )
          .decoration
          ?.hintText,
      '已保存，不显示；留空保持不变',
    );
    expect(
      tester
          .widget<TextField>(
            find.descendant(
              of: find.byKey(const Key('ai-api-key-field')),
              matching: find.byType(TextField),
            ),
          )
          .obscureText,
      isFalse,
    );
    expect(
        tester
            .widget<SwitchListTile>(
              find.byKey(const Key('ai-enabled-switch')),
            )
            .value,
        isTrue);
  });

  testWidgets('saving persists settings and masks nothing in plain log',
      (tester) async {
    final store = MemoryAiSettingsStore();
    await pumpWithL10n(
      tester,
      AiSettingsScreen(store: store, repository: RecordingAiRepository()),
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
    expect(
      tester
          .widget<TextFormField>(find.byKey(const Key('ai-api-key-field')))
          .controller
          ?.text,
      isEmpty,
    );
    expect(find.text('已保存'), findsOneWidget);
  });

  testWidgets('saving other fields keeps an existing hidden API key',
      (tester) async {
    final store = MemoryAiSettingsStore(
      initial: const AiSettings(
        baseUrl: 'https://old.example.com/v1',
        model: 'old-model',
        apiKey: 'sk-existing',
        enabled: true,
      ),
    );
    await pumpWithL10n(
      tester,
      AiSettingsScreen(store: store, repository: RecordingAiRepository()),
    );
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byKey(const Key('ai-base-url-field')),
      'https://new.example.com/v1',
    );
    await tester.tap(find.byKey(const Key('ai-save-button')));
    await tester.pumpAndSettle();

    expect(store.initial.baseUrl, 'https://new.example.com/v1');
    expect(store.initial.apiKey, 'sk-existing');
    expect(
      tester
          .widget<TextFormField>(find.byKey(const Key('ai-api-key-field')))
          .controller
          ?.text,
      isEmpty,
    );
  });

  testWidgets('connection test reports success', (tester) async {
    final repository = RecordingAiRepository();
    await pumpWithL10n(
      tester,
      AiSettingsScreen(
        store: MemoryAiSettingsStore(),
        repository: repository,
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
    await pumpWithL10n(
      tester,
      AiSettingsScreen(
        store: MemoryAiSettingsStore(),
        repository: repository,
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
    await pumpWithL10n(
      tester,
      AiSettingsScreen(store: store, repository: RecordingAiRepository()),
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

  test('missing or unknown protocol falls back to Chat Completions', () {
    expect(AiProtocol.fromStorage(null), AiProtocol.openaiChatCompletions);
    expect(AiProtocol.fromStorage('unknown-protocol'), AiProtocol.openaiChatCompletions);
    expect(AiProtocol.fromStorage('openaiResponses'), AiProtocol.openaiResponses);
    expect(AiProtocol.fromStorage('anthropicMessages'), AiProtocol.anthropicMessages);
  });

  test('AiSettings defaults to Chat Completions and never leaks the protocol', () {
    const settings = AiSettings(
      baseUrl: 'https://api.openai.com/v1',
      model: 'gpt-4o-mini',
      apiKey: 'sk-secret',
      enabled: true,
    );

    expect(settings.protocol, AiProtocol.openaiChatCompletions);
    expect(settings.toString(), isNot(contains('sk-secret')));
  });

  testWidgets('selecting and saving a protocol persists it', (tester) async {
    final store = MemoryAiSettingsStore(
      initial: const AiSettings(
        baseUrl: 'https://api.anthropic.com',
        model: 'claude-3-5-haiku',
        apiKey: 'sk-secret',
        enabled: true,
      ),
    );
    await pumpWithL10n(
      tester,
      AiSettingsScreen(store: store, repository: RecordingAiRepository()),
    );
    await tester.pumpAndSettle();

    expect(store.initial.protocol, AiProtocol.openaiChatCompletions);

    await tester.tap(find.byKey(const Key('ai-protocol-field')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Anthropic Messages').last);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('ai-save-button')));
    await tester.pumpAndSettle();

    expect(store.initial.protocol, AiProtocol.anthropicMessages);
    expect(store.initial.baseUrl, 'https://api.anthropic.com');
  });

  testWidgets('saved protocol is shown when the screen loads', (tester) async {
    final store = MemoryAiSettingsStore(
      initial: const AiSettings(
        baseUrl: 'https://x.example/v1',
        model: 'model',
        apiKey: 'sk-secret',
        enabled: true,
        protocol: AiProtocol.openaiResponses,
      ),
    );
    await pumpWithL10n(
      tester,
      AiSettingsScreen(store: store, repository: RecordingAiRepository()),
    );
    await tester.pumpAndSettle();

    expect(
      find.descendant(
        of: find.byKey(const Key('ai-protocol-field')),
        matching: find.text('OpenAI Responses'),
      ),
      findsOneWidget,
    );
  });
}
