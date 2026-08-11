import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:studyflow/platform/platform_bridge.dart';
import 'package:studyflow_platform_contract/platform_contract.dart';

final class UnsupportedPlatform implements PlatformMethodChannel {
  @override
  Future<Object?> invokeMethod(String method, [Object? arguments]) async {
    throw MissingPluginException('$method has no native implementation.');
  }
}

final class FakePlatform implements PlatformMethodChannel {
  final Map<String, Object?> responses;

  FakePlatform(this.responses);

  final List<String> methods = <String>[];

  @override
  Future<Object?> invokeMethod(String method, [Object? arguments]) async {
    methods.add(method);
    final response = responses[method];
    if (response is Exception) {
      throw response;
    }
    return response;
  }
}

RestrictionRule rule() => RestrictionRule(
      id: 'rule-1',
      scope: RestrictionScope.app,
      target: 'com.example.study',
      startsAt: DateTime.utc(2026, 8, 11, 9),
      endsAt: DateTime.utc(2026, 8, 11, 10),
      enabled: true,
    );

void main() {
  test('unsupported restriction capability is explicit', () async {
    final bridge = PlatformBridge(channel: UnsupportedPlatform());

    final result = await bridge.applyRestriction(rule());

    expect(result.kind, CapabilityResultKind.unsupported);
    expect(result.message, contains('not supported'));
  });

  test('all capability methods fail explicitly without a native channel',
      () async {
    final bridge = PlatformBridge(channel: UnsupportedPlatform());

    final results = await Future.wait(<Future<CapabilityResult>>[
      bridge.scheduleReminder(
        title: 'Algebra',
        at: DateTime.utc(2026, 8, 11, 10),
      ),
      bridge.startFocusSession(title: 'Algebra'),
      bridge.getUsageSummary(),
      bridge.applyRestriction(rule()),
      bridge.clearRestriction(rule()),
    ]);

    expect(
      results.map((result) => result.kind),
      everyElement(CapabilityResultKind.unsupported),
    );
  });

  test('permission denial maps to a typed permission result', () async {
    final bridge = PlatformBridge(
      channel: FakePlatform(<String, Object?>{
        'scheduleReminder': PlatformException(
          code: 'permission_denied',
          message: 'Notifications are not authorized.',
        ),
      }),
    );

    final result = await bridge.scheduleReminder(
      title: 'Algebra',
      at: DateTime.utc(2026, 8, 11, 10),
    );

    expect(result.kind, CapabilityResultKind.permissionMissing);
    expect(result.message, contains('not authorized'));
  });

  test('supported native result remains typed', () async {
    final platform = FakePlatform(<String, Object?>{
      'startFocusSession': <String, Object?>{
        'kind': 'supported',
        'message': 'Focus notification posted.',
      },
    });
    final bridge = PlatformBridge(channel: platform);

    final result = await bridge.startFocusSession(title: 'Algebra');

    expect(result.kind, CapabilityResultKind.supported);
    expect(platform.methods, <String>['startFocusSession']);
  });

  test('permission health is unavailable when the channel is missing',
      () async {
    final bridge = PlatformBridge(channel: UnsupportedPlatform());

    final health = await bridge.getPermissionStatus();

    expect(health.states, isNotEmpty);
    expect(health.states.every((state) => !state.available), isTrue);
    expect(
      health.stateFor(PlatformPermissionId.notifications)?.detail,
      contains('not supported'),
    );
  });

  test('permission health parses native states without extra fields',
      () async {
    final bridge = PlatformBridge(
      channel: FakePlatform(<String, Object?>{
        'getPermissionStatus': <Object?>[
          <String, Object?>{
            'id': 'notifications',
            'available': true,
            'allowed': true,
            'detail': 'authorized',
          },
          <String, Object?>{
            'id': 'usageAccess',
            'available': false,
            'allowed': false,
            'detail': 'separate authorization required',
          },
        ],
      }),
    );

    final health = await bridge.getPermissionStatus();

    expect(health.stateFor(PlatformPermissionId.notifications)?.allowed, isTrue);
    expect(
      health.stateFor(PlatformPermissionId.usageAccess)?.available,
      isFalse,
    );
  });
}
