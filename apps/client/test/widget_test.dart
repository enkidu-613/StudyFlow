import 'package:flutter_test/flutter_test.dart';

import 'package:studyflow/main.dart';

void main() {
  testWidgets('StudyFlow app displays its title', (WidgetTester tester) async {
    await tester.pumpWidget(const StudyFlowApp());

    expect(find.text('StudyFlow'), findsOneWidget);
  });
}
