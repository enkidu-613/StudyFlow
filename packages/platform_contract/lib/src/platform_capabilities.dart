enum CapabilityResultKind { supported, permissionMissing, unsupported, failed }

final class CapabilityResult {
  const CapabilityResult({
    required this.kind,
    required this.message,
    this.details,
  });

  const CapabilityResult.supported({
    this.message = 'ok',
    this.details,
  }) : kind = CapabilityResultKind.supported;

  const CapabilityResult.permissionMissing(
    String message, {
    this.details,
  })  : kind = CapabilityResultKind.permissionMissing,
        message = message;

  const CapabilityResult.unsupported(
    String reason, {
    this.details,
  })  : kind = CapabilityResultKind.unsupported,
        message = reason;

  const CapabilityResult.failed(
    String message, {
    this.details,
  })  : kind = CapabilityResultKind.failed,
        message = message;

  final CapabilityResultKind kind;
  final String message;
  final Map<String, Object?>? details;

  bool get isSupported => kind == CapabilityResultKind.supported;
}

enum PlatformPermissionId {
  notifications,
  exactAlarm,
  background,
  batteryOptimization,
  usageAccess,
  userNotifications,
  menuBar,
  focus,
}

final class PermissionState {
  const PermissionState({
    required this.id,
    required this.available,
    required this.allowed,
    required this.detail,
  });

  final PlatformPermissionId id;
  final bool available;
  final bool allowed;
  final String detail;
}

final class PermissionHealth {
  PermissionHealth({required Iterable<PermissionState> states})
      : states = List<PermissionState>.unmodifiable(states);

  final List<PermissionState> states;

  PermissionState? stateFor(PlatformPermissionId id) {
    for (final state in states) {
      if (state.id == id) {
        return state;
      }
    }
    return null;
  }
}

enum RestrictionScope { app, website }

final class RestrictionRule {
  RestrictionRule({
    required this.id,
    required this.scope,
    required this.target,
    required DateTime startsAt,
    required DateTime endsAt,
    required this.enabled,
  })  : startsAt = startsAt.toUtc(),
        endsAt = endsAt.toUtc() {
    if (id.trim().isEmpty || target.trim().isEmpty) {
      throw ArgumentError('Restriction id and target must not be empty.');
    }
    if (!this.endsAt.isAfter(this.startsAt)) {
      throw ArgumentError.value(
        endsAt,
        'endsAt',
        'must be after startsAt',
      );
    }
  }

  factory RestrictionRule.fromJson(Map<String, Object?> json) =>
      RestrictionRule(
        id: json['id']! as String,
        scope: RestrictionScope.values.byName(json['scope']! as String),
        target: json['target']! as String,
        startsAt: DateTime.parse(json['startsAt']! as String),
        endsAt: DateTime.parse(json['endsAt']! as String),
        enabled: json['enabled']! as bool,
      );

  final String id;
  final RestrictionScope scope;
  final String target;
  final DateTime startsAt;
  final DateTime endsAt;
  final bool enabled;

  Map<String, Object?> toJson() => <String, Object?>{
        'id': id,
        'scope': scope.name,
        'target': target,
        'startsAt': startsAt.toIso8601String(),
        'endsAt': endsAt.toIso8601String(),
        'enabled': enabled,
      };
}
