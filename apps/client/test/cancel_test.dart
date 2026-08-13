import 'package:flutter_test/flutter_test.dart';
import 'package:studyflow/platform/platform_bridge.dart';

void main() {
  test('cancelReminder does not hang in test env', () async {
    final bridge = PlatformBridge();
    final result = await bridge.cancelReminder('abc').timeout(
          const Duration(seconds: 2),
        );
    expect(result.kind, isNotNull);
  });
}
