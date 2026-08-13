import 'package:flutter/services.dart';
import 'package:studyflow_platform_contract/platform_contract.dart';

abstract interface class PlatformMethodChannel {
  Future<Object?> invokeMethod(String method, [Object? arguments]);
}

final class FlutterPlatformMethodChannel implements PlatformMethodChannel {
  FlutterPlatformMethodChannel({String channelName = _channelName})
      : _channel = MethodChannel(channelName);

  static const String _channelName = 'studyflow/platform';

  final MethodChannel _channel;

  @override
  Future<Object?> invokeMethod(String method, [Object? arguments]) =>
      _channel.invokeMethod<Object?>(method, arguments);
}

final class PlatformBridge {
  PlatformBridge({PlatformMethodChannel? channel})
      : _channel = channel ?? FlutterPlatformMethodChannel();

  final PlatformMethodChannel _channel;

  Future<CapabilityResult> scheduleReminder({
    required String title,
    required DateTime at,
    String? payload,
  }) =>
      _invokeCapability(
        'scheduleReminder',
        <String, Object?>{
          'title': title,
          'at': at.toUtc().millisecondsSinceEpoch,
          if (payload != null) 'text': payload,
        },
      );

  Future<CapabilityResult> startFocusSession({required String title}) =>
      _invokeCapability(
        'startFocusSession',
        <String, Object?>{'title': title},
      );

  Future<CapabilityResult> getUsageSummary({
    DateTime? from,
    DateTime? to,
  }) =>
      _invokeCapability(
        'getUsageSummary',
        <String, Object?>{
          if (from != null) 'from': from.toUtc().millisecondsSinceEpoch,
          if (to != null) 'to': to.toUtc().millisecondsSinceEpoch,
        },
      );

  Future<CapabilityResult> applyRestriction(RestrictionRule rule) =>
      _invokeCapability(
        'applyRestriction',
        rule.toJson(),
      );

  Future<CapabilityResult> clearRestriction(RestrictionRule rule) =>
      _invokeCapability(
        'clearRestriction',
        rule.toJson(),
      );

  Future<bool> openPermissionSettings() async {
    try {
      final raw = await _channel.invokeMethod('openPermissionSettings');
      return raw is bool ? raw : false;
    } on Object {
      return false;
    }
  }

  Future<PermissionHealth> getPermissionStatus() async {
    try {
      final raw = await _channel.invokeMethod('getPermissionStatus');
      if (raw is! List) {
        return _unavailableHealth('Permission status was not a list.');
      }
      final states = <PermissionState>[];
      for (final item in raw) {
        if (item is! Map) {
          continue;
        }
        final json = item.cast<String, Object?>();
        final idName = json['id'];
        final available = json['available'];
        final allowed = json['allowed'];
        final detail = json['detail'];
        if (idName is! String || available is! bool || allowed is! bool) {
          continue;
        }
        final id = PlatformPermissionId.values
            .where((permission) => permission.name == idName)
            .firstOrNull;
        if (id == null) {
          continue;
        }
        states.add(
          PermissionState(
            id: id,
            available: available,
            allowed: allowed,
            detail: detail is String ? detail : '',
          ),
        );
      }
      return PermissionHealth(states: states);
    } on MissingPluginException {
      return _unavailableHealth('not supported on this device');
    } on PlatformException {
      return _unavailableHealth('permission status could not be read');
    }
  }

  Future<CapabilityResult> _invokeCapability(
    String method,
    Map<String, Object?> arguments,
  ) async {
    try {
      final raw = await _channel.invokeMethod(method, arguments);
      return _capabilityFromResult(raw, method);
    } on MissingPluginException {
      return CapabilityResult.unsupported(
        '$method is not supported on this device.',
      );
    } on PlatformException catch (error) {
      final code = error.code.toLowerCase();
      if (code.contains('permission')) {
        return CapabilityResult.permissionMissing(
          error.message ?? 'The platform permission is required.',
        );
      }
      return CapabilityResult.failed(
        error.message ?? '$method failed on the platform.',
      );
    } on Object catch (error) {
      return CapabilityResult.failed(
        '$method failed on the platform.',
        details: <String, Object?>{'cause': error.toString()},
      );
    }
  }

  CapabilityResult _capabilityFromResult(Object? raw, String method) {
    if (raw is! Map) {
      return CapabilityResult.failed('$method returned an invalid result.');
    }
    final json = raw.cast<String, Object?>();
    final kind = json['kind'];
    final message = json['message'];
    if (kind is! String || message is! String) {
      return CapabilityResult.failed('$method returned an invalid result.');
    }
    return switch (kind) {
      'supported' => CapabilityResult.supported(message: message),
      'permission_missing' => CapabilityResult.permissionMissing(message),
      'unsupported' => CapabilityResult.unsupported(message),
      'failed' => CapabilityResult.failed(message),
      _ => CapabilityResult.failed('$method returned an unknown status.'),
    };
  }

  PermissionHealth _unavailableHealth(String detail) => PermissionHealth(
        states: <PermissionState>[
          for (final id in PlatformPermissionId.values)
            PermissionState(
              id: id,
              available: false,
              allowed: false,
              detail: detail,
            ),
        ],
      );
}
