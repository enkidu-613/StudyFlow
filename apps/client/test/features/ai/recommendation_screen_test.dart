import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:studyflow/features/ai/ai_repository.dart';
import 'package:studyflow/features/ai/recommendation_screen.dart';

void main() {
  Future<AiRecommendation> recommendation() async => AiRecommendation(
        summary: 'Focus on the morning study block.',
        reasonCodes: const <String>['morning_focus'],
        candidateChanges: const <CandidateScheduleChange>[],
      );

  Future<AiRecommendation> recommendationWithChanges() async =>
      AiRecommendation(
        summary: 'Shift the rest block.',
        reasonCodes: const <String>['rest_alignment'],
        candidateChanges: <CandidateScheduleChange>[
          CandidateScheduleChange(
            action: 'shift_schedule_block',
            blockId: 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb',
            deltaMinutes: 15,
            reason: 'Align with sleep window.',
          ),
        ],
      );

  Future<void> pumpScreen(
    WidgetTester tester,
    Future<AiRecommendation> Function() request,
  ) async {
    await tester.pumpWidget(
      MaterialApp(home: RecommendationScreen(request: request)),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('requests and shows a recommendation', (tester) async {
    await pumpScreen(tester, recommendation);

    await tester.tap(find.byKey(const Key('request-recommendation-button')));
    await tester.pumpAndSettle();

    expect(find.text('Focus on the morning study block.'), findsOneWidget);
    expect(find.text('morning_focus'), findsOneWidget);
    expect(find.text('Request another'), findsOneWidget);
  });

  testWidgets('shows proposed changes as confirmation-only', (tester) async {
    await pumpScreen(tester, recommendationWithChanges);

    await tester.tap(find.byKey(const Key('request-recommendation-button')));
    await tester.pumpAndSettle();

    expect(find.text('Proposed changes (require confirmation)'), findsOneWidget);
    expect(find.text('shift_schedule_block'), findsOneWidget);
    expect(find.text('15 min · Align with sleep window.'), findsOneWidget);
    expect(
      find.textContaining('Nothing was changed'),
      findsOneWidget,
    );
  });

  testWidgets('shows an error card when the request fails', (tester) async {
    Future<AiRecommendation> failingRequest() async =>
        throw const AiNetworkFailure('AI 服务不可用。');

    await pumpScreen(tester, failingRequest);

    await tester.tap(find.byKey(const Key('request-recommendation-button')));
    await tester.pumpAndSettle();

    expect(find.text('Recommendation unavailable'), findsOneWidget);
    expect(find.textContaining('AI 服务不可用'), findsOneWidget);
  });

  testWidgets('requesting again replaces the previous recommendation',
      (tester) async {
    var calls = 0;
    Future<AiRecommendation> alternating() async {
      calls += 1;
      return calls == 1 ? recommendation() : recommendationWithChanges();
    }

    await pumpScreen(tester, alternating);

    await tester.tap(find.byKey(const Key('request-recommendation-button')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('request-recommendation-button')));
    await tester.pumpAndSettle();

    expect(find.text('Shift the rest block.'), findsOneWidget);
    expect(find.text('Focus on the morning study block.'), findsNothing);
  });
}
