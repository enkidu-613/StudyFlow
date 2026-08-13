import 'package:flutter/widgets.dart';
import 'package:studyflow_platform_contract/platform_contract.dart';

import 'app_localizations.dart';

extension AppLocalizationsX on BuildContext {
  AppLocalizations get l10n => AppLocalizations.of(this);
}

extension PermissionLocalizationX on AppLocalizations {
  String permissionLabel(PlatformPermissionId id) => switch (id) {
        PlatformPermissionId.notifications => permissionNotifications,
        PlatformPermissionId.exactAlarm => permissionExactAlarm,
        PlatformPermissionId.background => permissionBackground,
        PlatformPermissionId.batteryOptimization =>
          permissionBatteryOptimization,
        PlatformPermissionId.usageAccess => permissionUsageAccess,
        PlatformPermissionId.userNotifications => permissionUserNotifications,
        PlatformPermissionId.menuBar => permissionMenuBar,
        PlatformPermissionId.focus => permissionFocus,
      };

  String permissionDetailText(String detail, {required bool allowed}) {
    if (detail.isNotEmpty && detail != 'ok' && detail != 'granted') {
      return detail;
    }
    return allowed ? permissionDetailGranted : permissionDetailRequired;
  }

  String permissionStatusText({required bool available, required bool allowed}) {
    if (!available) {
      return permissionUnavailable;
    }
    return allowed ? permissionAllowed : permissionDenied;
  }
}
