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
    final normalized = detail.trim().toLowerCase();
    if (normalized.isNotEmpty &&
        normalized != 'ok' &&
        normalized != 'granted') {
      final isChinese = localeName.toLowerCase().startsWith('zh');
      return switch (normalized) {
        'not restricted' =>
          isChinese ? '系统未限制后台运行' : 'Background is not restricted',
        'background restricted' =>
          isChinese ? '系统限制了后台运行' : 'Background activity is restricted',
        'allowed' => isChinese ? '已允许' : 'Allowed',
        'restricted' => isChinese ? '受限制' : 'Restricted',
        'not granted' => isChinese ? '未授权' : 'Not granted',
        'not granted; open permissions → alarms & reminders and enable it' =>
          isChinese
              ? '未授权；系统不允许应用直接申请，请手动开启：设置 → 应用 → StudyFlow → 权限 → 闹钟和提醒'
              : 'Not granted; open Permissions → Alarms & reminders and enable it',
        'restricted; open battery → background power consumption management and allow studyflow' =>
          isChinese
              ? '受限制；请手动设置：设置 → 电池 → 后台耗电管理 → 允许 StudyFlow 后台运行'
              : 'Restricted; open Battery → Background power consumption management and allow StudyFlow',
        'not applicable on android' =>
          isChinese ? 'Android 不支持菜单栏' : 'Menu bar is not available on Android',
        'in-app focus workflow' =>
          isChinese ? '应用内专注流程已启用' : 'In-app focus workflow is enabled',
        _ => detail,
      };
    }
    return allowed ? permissionDetailGranted : permissionDetailRequired;
  }

  String permissionStatusText(
      {required bool available, required bool allowed}) {
    if (!available) {
      return permissionUnavailable;
    }
    return allowed ? permissionAllowed : permissionDenied;
  }
}
