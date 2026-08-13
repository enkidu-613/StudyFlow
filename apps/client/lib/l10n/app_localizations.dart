import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart' as intl;

import 'app_localizations_en.dart';
import 'app_localizations_zh.dart';

// ignore_for_file: type=lint

/// Callers can lookup localized strings with an instance of AppLocalizations
/// returned by `AppLocalizations.of(context)`.
///
/// Applications need to include `AppLocalizations.delegate()` in their app's
/// `localizationDelegates` list, and the locales they support in the app's
/// `supportedLocales` list. For example:
///
/// ```dart
/// import 'l10n/app_localizations.dart';
///
/// return MaterialApp(
///   localizationsDelegates: AppLocalizations.localizationsDelegates,
///   supportedLocales: AppLocalizations.supportedLocales,
///   home: MyApplicationHome(),
/// );
/// ```
///
/// ## Update pubspec.yaml
///
/// Please make sure to update your pubspec.yaml to include the following
/// packages:
///
/// ```yaml
/// dependencies:
///   # Internationalization support.
///   flutter_localizations:
///     sdk: flutter
///   intl: any # Use the pinned version from flutter_localizations
///
///   # Rest of dependencies
/// ```
///
/// ## iOS Applications
///
/// iOS applications define key application metadata, including supported
/// locales, in an Info.plist file that is built into the application bundle.
/// To configure the locales supported by your app, you’ll need to edit this
/// file.
///
/// First, open your project’s ios/Runner.xcworkspace Xcode workspace file.
/// Then, in the Project Navigator, open the Info.plist file under the Runner
/// project’s Runner folder.
///
/// Next, select the Information Property List item, select Add Item from the
/// Editor menu, then select Localizations from the pop-up menu.
///
/// Select and expand the newly-created Localizations item then, for each
/// locale your application supports, add a new item and select the locale
/// you wish to add from the pop-up menu in the Value field. This list should
/// be consistent with the languages listed in the AppLocalizations.supportedLocales
/// property.
abstract class AppLocalizations {
  AppLocalizations(String locale)
      : localeName = intl.Intl.canonicalizedLocale(locale.toString());

  final String localeName;

  static AppLocalizations of(BuildContext context) {
    return Localizations.of<AppLocalizations>(context, AppLocalizations)!;
  }

  static const LocalizationsDelegate<AppLocalizations> delegate =
      _AppLocalizationsDelegate();

  /// A list of this localizations delegate along with the default localizations
  /// delegates.
  ///
  /// Returns a list of localizations delegates containing this delegate along with
  /// GlobalMaterialLocalizations.delegate, GlobalCupertinoLocalizations.delegate,
  /// and GlobalWidgetsLocalizations.delegate.
  ///
  /// Additional delegates can be added by appending to this list in
  /// MaterialApp. This list does not have to be used at all if a custom list
  /// of delegates is preferred or required.
  static const List<LocalizationsDelegate<dynamic>> localizationsDelegates =
      <LocalizationsDelegate<dynamic>>[
    delegate,
    GlobalMaterialLocalizations.delegate,
    GlobalCupertinoLocalizations.delegate,
    GlobalWidgetsLocalizations.delegate,
  ];

  /// A list of this localizations delegate's supported locales.
  static const List<Locale> supportedLocales = <Locale>[
    Locale('en'),
    Locale('zh')
  ];

  /// No description provided for @appTitle.
  ///
  /// In zh, this message translates to:
  /// **'StudyFlow'**
  String get appTitle;

  /// No description provided for @navToday.
  ///
  /// In zh, this message translates to:
  /// **'今天'**
  String get navToday;

  /// No description provided for @navTasks.
  ///
  /// In zh, this message translates to:
  /// **'任务'**
  String get navTasks;

  /// No description provided for @navSchedule.
  ///
  /// In zh, this message translates to:
  /// **'日程'**
  String get navSchedule;

  /// No description provided for @navFocus.
  ///
  /// In zh, this message translates to:
  /// **'专注'**
  String get navFocus;

  /// No description provided for @navSettings.
  ///
  /// In zh, this message translates to:
  /// **'设置'**
  String get navSettings;

  /// No description provided for @configErrorTitle.
  ///
  /// In zh, this message translates to:
  /// **'API 地址未配置'**
  String get configErrorTitle;

  /// No description provided for @configErrorBody.
  ///
  /// In zh, this message translates to:
  /// **'请使用 --dart-define=STUDYFLOW_API_BASE_URL=https://api.example.com 启动客户端。'**
  String get configErrorBody;

  /// No description provided for @authSignIn.
  ///
  /// In zh, this message translates to:
  /// **'登录'**
  String get authSignIn;

  /// No description provided for @authCreateAccount.
  ///
  /// In zh, this message translates to:
  /// **'注册'**
  String get authCreateAccount;

  /// No description provided for @authEmailLabel.
  ///
  /// In zh, this message translates to:
  /// **'邮箱'**
  String get authEmailLabel;

  /// No description provided for @authPasswordLabel.
  ///
  /// In zh, this message translates to:
  /// **'密码'**
  String get authPasswordLabel;

  /// No description provided for @authConfirmPasswordLabel.
  ///
  /// In zh, this message translates to:
  /// **'确认密码'**
  String get authConfirmPasswordLabel;

  /// No description provided for @authEmailRequired.
  ///
  /// In zh, this message translates to:
  /// **'请输入邮箱'**
  String get authEmailRequired;

  /// No description provided for @authEmailInvalid.
  ///
  /// In zh, this message translates to:
  /// **'请输入有效的邮箱地址'**
  String get authEmailInvalid;

  /// No description provided for @authPasswordRequired.
  ///
  /// In zh, this message translates to:
  /// **'请输入密码'**
  String get authPasswordRequired;

  /// No description provided for @authPasswordTooShort.
  ///
  /// In zh, this message translates to:
  /// **'密码至少需要 {min} 位'**
  String authPasswordTooShort(Object min);

  /// No description provided for @authPasswordTooLong.
  ///
  /// In zh, this message translates to:
  /// **'密码过长'**
  String get authPasswordTooLong;

  /// No description provided for @authPasswordMaxLength.
  ///
  /// In zh, this message translates to:
  /// **'密码最多 {max} 位'**
  String authPasswordMaxLength(Object max);

  /// No description provided for @authPasswordNoSpaces.
  ///
  /// In zh, this message translates to:
  /// **'密码不能包含空格'**
  String get authPasswordNoSpaces;

  /// No description provided for @authPasswordAllDigits.
  ///
  /// In zh, this message translates to:
  /// **'密码不能全为数字'**
  String get authPasswordAllDigits;

  /// No description provided for @authPasswordMatchesEmail.
  ///
  /// In zh, this message translates to:
  /// **'密码不能与注册邮箱相同'**
  String get authPasswordMatchesEmail;

  /// No description provided for @authPasswordMissing.
  ///
  /// In zh, this message translates to:
  /// **'密码必须包含{missing}'**
  String authPasswordMissing(Object missing);

  /// No description provided for @authConfirmRequired.
  ///
  /// In zh, this message translates to:
  /// **'请再次输入密码'**
  String get authConfirmRequired;

  /// No description provided for @authPasswordMismatch.
  ///
  /// In zh, this message translates to:
  /// **'两次输入的密码不一致'**
  String get authPasswordMismatch;

  /// No description provided for @authErrorInvalidCredentials.
  ///
  /// In zh, this message translates to:
  /// **'邮箱或密码错误'**
  String get authErrorInvalidCredentials;

  /// No description provided for @authErrorEmailTaken.
  ///
  /// In zh, this message translates to:
  /// **'该邮箱已被注册'**
  String get authErrorEmailTaken;

  /// No description provided for @authErrorInvalidInput.
  ///
  /// In zh, this message translates to:
  /// **'邮箱或密码格式不正确'**
  String get authErrorInvalidInput;

  /// No description provided for @authErrorTooManyAttempts.
  ///
  /// In zh, this message translates to:
  /// **'尝试次数过多，请稍后再试'**
  String get authErrorTooManyAttempts;

  /// No description provided for @authErrorUnavailable.
  ///
  /// In zh, this message translates to:
  /// **'服务暂时不可用，请稍后重试'**
  String get authErrorUnavailable;

  /// No description provided for @authErrorGeneric.
  ///
  /// In zh, this message translates to:
  /// **'操作失败，请稍后重试'**
  String get authErrorGeneric;

  /// No description provided for @authSessionExpired.
  ///
  /// In zh, this message translates to:
  /// **'登录已过期，请重新登录'**
  String get authSessionExpired;

  /// No description provided for @authNetworkFailed.
  ///
  /// In zh, this message translates to:
  /// **'网络连接失败，请检查网络后重试'**
  String get authNetworkFailed;

  /// No description provided for @authRestoreFailed.
  ///
  /// In zh, this message translates to:
  /// **'无法恢复上次会话：{detail}'**
  String authRestoreFailed(Object detail);

  /// No description provided for @authWorking.
  ///
  /// In zh, this message translates to:
  /// **'正在处理…'**
  String get authWorking;

  /// No description provided for @homeNotifications.
  ///
  /// In zh, this message translates to:
  /// **'通知'**
  String get homeNotifications;

  /// No description provided for @homeNotifGranted.
  ///
  /// In zh, this message translates to:
  /// **'已授权'**
  String get homeNotifGranted;

  /// No description provided for @homeNotifRequired.
  ///
  /// In zh, this message translates to:
  /// **'需要授权'**
  String get homeNotifRequired;

  /// No description provided for @homeCheckIn.
  ///
  /// In zh, this message translates to:
  /// **'打卡'**
  String get homeCheckIn;

  /// No description provided for @homeLastCheckIn.
  ///
  /// In zh, this message translates to:
  /// **'最近打卡'**
  String get homeLastCheckIn;

  /// No description provided for @minutesShort.
  ///
  /// In zh, this message translates to:
  /// **'{count} 分钟'**
  String minutesShort(Object count);

  /// No description provided for @minutesSuffix.
  ///
  /// In zh, this message translates to:
  /// **'分钟'**
  String get minutesSuffix;

  /// No description provided for @tasksEmpty.
  ///
  /// In zh, this message translates to:
  /// **'还没有任务'**
  String get tasksEmpty;

  /// No description provided for @taskNew.
  ///
  /// In zh, this message translates to:
  /// **'新建任务'**
  String get taskNew;

  /// No description provided for @taskEdit.
  ///
  /// In zh, this message translates to:
  /// **'编辑任务'**
  String get taskEdit;

  /// No description provided for @taskTitleLabel.
  ///
  /// In zh, this message translates to:
  /// **'标题'**
  String get taskTitleLabel;

  /// No description provided for @taskDescriptionLabel.
  ///
  /// In zh, this message translates to:
  /// **'描述'**
  String get taskDescriptionLabel;

  /// No description provided for @taskEstimatedMinutes.
  ///
  /// In zh, this message translates to:
  /// **'预计分钟数'**
  String get taskEstimatedMinutes;

  /// No description provided for @taskPriorityLabel.
  ///
  /// In zh, this message translates to:
  /// **'优先级'**
  String get taskPriorityLabel;

  /// No description provided for @taskRepeatLabel.
  ///
  /// In zh, this message translates to:
  /// **'重复'**
  String get taskRepeatLabel;

  /// No description provided for @taskTagsLabel.
  ///
  /// In zh, this message translates to:
  /// **'标签'**
  String get taskTagsLabel;

  /// No description provided for @taskTagsHint.
  ///
  /// In zh, this message translates to:
  /// **'例如：数学, 阅读'**
  String get taskTagsHint;

  /// No description provided for @taskTitleRequired.
  ///
  /// In zh, this message translates to:
  /// **'请输入标题'**
  String get taskTitleRequired;

  /// No description provided for @taskMinutesPositive.
  ///
  /// In zh, this message translates to:
  /// **'分钟数必须为正数'**
  String get taskMinutesPositive;

  /// No description provided for @taskRowSubtitle.
  ///
  /// In zh, this message translates to:
  /// **'{minutes} 分钟 · {priority}'**
  String taskRowSubtitle(Object minutes, Object priority);

  /// No description provided for @commonSave.
  ///
  /// In zh, this message translates to:
  /// **'保存'**
  String get commonSave;

  /// No description provided for @commonCancel.
  ///
  /// In zh, this message translates to:
  /// **'取消'**
  String get commonCancel;

  /// No description provided for @scheduleEmpty.
  ///
  /// In zh, this message translates to:
  /// **'还没有日程块'**
  String get scheduleEmpty;

  /// No description provided for @blockNew.
  ///
  /// In zh, this message translates to:
  /// **'新建日程块'**
  String get blockNew;

  /// No description provided for @blockKindLabel.
  ///
  /// In zh, this message translates to:
  /// **'类型'**
  String get blockKindLabel;

  /// No description provided for @blockTaskLabel.
  ///
  /// In zh, this message translates to:
  /// **'关联任务'**
  String get blockTaskLabel;

  /// No description provided for @blockLocked.
  ///
  /// In zh, this message translates to:
  /// **'锁定'**
  String get blockLocked;

  /// No description provided for @blockEndAfterStart.
  ///
  /// In zh, this message translates to:
  /// **'结束时间必须晚于开始时间'**
  String get blockEndAfterStart;

  /// No description provided for @focusStart.
  ///
  /// In zh, this message translates to:
  /// **'开始'**
  String get focusStart;

  /// No description provided for @focusPause.
  ///
  /// In zh, this message translates to:
  /// **'暂停'**
  String get focusPause;

  /// No description provided for @focusResume.
  ///
  /// In zh, this message translates to:
  /// **'继续'**
  String get focusResume;

  /// No description provided for @focusFinish.
  ///
  /// In zh, this message translates to:
  /// **'结束'**
  String get focusFinish;

  /// No description provided for @focusTaskLabel.
  ///
  /// In zh, this message translates to:
  /// **'任务'**
  String get focusTaskLabel;

  /// No description provided for @focusSessionsTitle.
  ///
  /// In zh, this message translates to:
  /// **'历史记录'**
  String get focusSessionsTitle;

  /// No description provided for @focusDefaultTitle.
  ///
  /// In zh, this message translates to:
  /// **'StudyFlow 专注'**
  String get focusDefaultTitle;

  /// No description provided for @checkInsEmpty.
  ///
  /// In zh, this message translates to:
  /// **'还没有打卡记录'**
  String get checkInsEmpty;

  /// No description provided for @checkInNew.
  ///
  /// In zh, this message translates to:
  /// **'新建打卡'**
  String get checkInNew;

  /// No description provided for @checkInSleepMinutes.
  ///
  /// In zh, this message translates to:
  /// **'睡眠时长'**
  String get checkInSleepMinutes;

  /// No description provided for @checkInSleepQuality.
  ///
  /// In zh, this message translates to:
  /// **'睡眠质量'**
  String get checkInSleepQuality;

  /// No description provided for @checkInEnergy.
  ///
  /// In zh, this message translates to:
  /// **'精力'**
  String get checkInEnergy;

  /// No description provided for @checkInMood.
  ///
  /// In zh, this message translates to:
  /// **'心情'**
  String get checkInMood;

  /// No description provided for @checkInFeedback.
  ///
  /// In zh, this message translates to:
  /// **'反馈'**
  String get checkInFeedback;

  /// No description provided for @checkInSleepInvalid.
  ///
  /// In zh, this message translates to:
  /// **'睡眠时长必须是非负数字'**
  String get checkInSleepInvalid;

  /// No description provided for @checkInRowTitle.
  ///
  /// In zh, this message translates to:
  /// **'睡眠 {minutes} 分钟 · 精力 {energy}'**
  String checkInRowTitle(Object energy, Object minutes);

  /// No description provided for @settingsUsageSummary.
  ///
  /// In zh, this message translates to:
  /// **'使用统计'**
  String get settingsUsageSummary;

  /// No description provided for @settingsPermissions.
  ///
  /// In zh, this message translates to:
  /// **'权限'**
  String get settingsPermissions;

  /// No description provided for @permissionAvailable.
  ///
  /// In zh, this message translates to:
  /// **'可用'**
  String get permissionAvailable;

  /// No description provided for @permissionUnavailable.
  ///
  /// In zh, this message translates to:
  /// **'不可用'**
  String get permissionUnavailable;

  /// No description provided for @permissionAllowed.
  ///
  /// In zh, this message translates to:
  /// **'已允许'**
  String get permissionAllowed;

  /// No description provided for @permissionDenied.
  ///
  /// In zh, this message translates to:
  /// **'未允许'**
  String get permissionDenied;

  /// No description provided for @permissionNotifications.
  ///
  /// In zh, this message translates to:
  /// **'通知'**
  String get permissionNotifications;

  /// No description provided for @permissionExactAlarm.
  ///
  /// In zh, this message translates to:
  /// **'精确闹钟'**
  String get permissionExactAlarm;

  /// No description provided for @permissionBackground.
  ///
  /// In zh, this message translates to:
  /// **'后台运行'**
  String get permissionBackground;

  /// No description provided for @permissionBatteryOptimization.
  ///
  /// In zh, this message translates to:
  /// **'电池优化白名单'**
  String get permissionBatteryOptimization;

  /// No description provided for @permissionUsageAccess.
  ///
  /// In zh, this message translates to:
  /// **'使用情况访问'**
  String get permissionUsageAccess;

  /// No description provided for @permissionUserNotifications.
  ///
  /// In zh, this message translates to:
  /// **'用户通知'**
  String get permissionUserNotifications;

  /// No description provided for @permissionMenuBar.
  ///
  /// In zh, this message translates to:
  /// **'菜单栏'**
  String get permissionMenuBar;

  /// No description provided for @permissionFocus.
  ///
  /// In zh, this message translates to:
  /// **'专注模式'**
  String get permissionFocus;

  /// No description provided for @permissionDetailGranted.
  ///
  /// In zh, this message translates to:
  /// **'已授权'**
  String get permissionDetailGranted;

  /// No description provided for @permissionDetailRequired.
  ///
  /// In zh, this message translates to:
  /// **'需要授权'**
  String get permissionDetailRequired;

  /// No description provided for @settingsAiEntry.
  ///
  /// In zh, this message translates to:
  /// **'AI 设置'**
  String get settingsAiEntry;

  /// No description provided for @settingsAiSubtitle.
  ///
  /// In zh, this message translates to:
  /// **'配置 Base URL、模型和 API Key'**
  String get settingsAiSubtitle;

  /// No description provided for @settingsSignOut.
  ///
  /// In zh, this message translates to:
  /// **'退出登录'**
  String get settingsSignOut;

  /// No description provided for @settingsLanguage.
  ///
  /// In zh, this message translates to:
  /// **'语言'**
  String get settingsLanguage;

  /// No description provided for @settingsLanguageSystem.
  ///
  /// In zh, this message translates to:
  /// **'跟随系统'**
  String get settingsLanguageSystem;

  /// No description provided for @settingsLanguageZh.
  ///
  /// In zh, this message translates to:
  /// **'简体中文'**
  String get settingsLanguageZh;

  /// No description provided for @settingsLanguageEn.
  ///
  /// In zh, this message translates to:
  /// **'English'**
  String get settingsLanguageEn;

  /// No description provided for @syncPendingTitle.
  ///
  /// In zh, this message translates to:
  /// **'待同步'**
  String get syncPendingTitle;

  /// No description provided for @syncIdle.
  ///
  /// In zh, this message translates to:
  /// **'已同步或等待变更'**
  String get syncIdle;

  /// No description provided for @syncSyncing.
  ///
  /// In zh, this message translates to:
  /// **'正在同步记录…'**
  String get syncSyncing;

  /// No description provided for @syncOffline.
  ///
  /// In zh, this message translates to:
  /// **'当前离线，本地更改已安全保存'**
  String get syncOffline;

  /// No description provided for @syncFailed.
  ///
  /// In zh, this message translates to:
  /// **'同步失败：{category}'**
  String syncFailed(Object category);

  /// No description provided for @syncNow.
  ///
  /// In zh, this message translates to:
  /// **'立即同步'**
  String get syncNow;

  /// No description provided for @syncRetryOnline.
  ///
  /// In zh, this message translates to:
  /// **'联网后重试'**
  String get syncRetryOnline;

  /// No description provided for @syncUnknown.
  ///
  /// In zh, this message translates to:
  /// **'未知'**
  String get syncUnknown;

  /// No description provided for @aiEnabledTitle.
  ///
  /// In zh, this message translates to:
  /// **'启用 AI 建议'**
  String get aiEnabledTitle;

  /// No description provided for @aiEnabledSubtitle.
  ///
  /// In zh, this message translates to:
  /// **'API Key 只保存在本机安全存储，不会上传。'**
  String get aiEnabledSubtitle;

  /// No description provided for @aiBaseUrlLabel.
  ///
  /// In zh, this message translates to:
  /// **'Base URL'**
  String get aiBaseUrlLabel;

  /// No description provided for @aiModelLabel.
  ///
  /// In zh, this message translates to:
  /// **'Model'**
  String get aiModelLabel;

  /// No description provided for @aiApiKeyLabel.
  ///
  /// In zh, this message translates to:
  /// **'API Key'**
  String get aiApiKeyLabel;

  /// No description provided for @aiBaseUrlRequired.
  ///
  /// In zh, this message translates to:
  /// **'Base URL 不能为空'**
  String get aiBaseUrlRequired;

  /// No description provided for @aiBaseUrlInvalid.
  ///
  /// In zh, this message translates to:
  /// **'请输入有效的 URL'**
  String get aiBaseUrlInvalid;

  /// No description provided for @aiBaseUrlRequireHttps.
  ///
  /// In zh, this message translates to:
  /// **'Base URL 必须使用 HTTPS'**
  String get aiBaseUrlRequireHttps;

  /// No description provided for @aiModelRequired.
  ///
  /// In zh, this message translates to:
  /// **'Model 名称不能为空'**
  String get aiModelRequired;

  /// No description provided for @aiApiKeyRequired.
  ///
  /// In zh, this message translates to:
  /// **'API Key 不能为空'**
  String get aiApiKeyRequired;

  /// No description provided for @aiSave.
  ///
  /// In zh, this message translates to:
  /// **'保存'**
  String get aiSave;

  /// No description provided for @aiTestConnection.
  ///
  /// In zh, this message translates to:
  /// **'测试连接'**
  String get aiTestConnection;

  /// No description provided for @aiClearConfig.
  ///
  /// In zh, this message translates to:
  /// **'清除配置'**
  String get aiClearConfig;

  /// No description provided for @aiClearTitle.
  ///
  /// In zh, this message translates to:
  /// **'清除 AI 配置'**
  String get aiClearTitle;

  /// No description provided for @aiClearBody.
  ///
  /// In zh, this message translates to:
  /// **'将删除本机的 Base URL、模型和 API Key，确定吗？'**
  String get aiClearBody;

  /// No description provided for @aiClearConfirm.
  ///
  /// In zh, this message translates to:
  /// **'清除'**
  String get aiClearConfirm;

  /// No description provided for @aiSaved.
  ///
  /// In zh, this message translates to:
  /// **'已保存'**
  String get aiSaved;

  /// No description provided for @aiCleared.
  ///
  /// In zh, this message translates to:
  /// **'已清除'**
  String get aiCleared;

  /// No description provided for @aiConnectionSuccess.
  ///
  /// In zh, this message translates to:
  /// **'连接成功'**
  String get aiConnectionSuccess;

  /// No description provided for @aiConnectionFailed.
  ///
  /// In zh, this message translates to:
  /// **'连接失败：{reason}'**
  String aiConnectionFailed(Object reason);

  /// No description provided for @aiConnectionFailedGeneric.
  ///
  /// In zh, this message translates to:
  /// **'连接失败，请稍后重试'**
  String get aiConnectionFailedGeneric;

  /// No description provided for @aiRecommendTitle.
  ///
  /// In zh, this message translates to:
  /// **'AI 建议'**
  String get aiRecommendTitle;

  /// No description provided for @aiRecommendError.
  ///
  /// In zh, this message translates to:
  /// **'暂时无法获取建议'**
  String get aiRecommendError;

  /// No description provided for @aiProposedChanges.
  ///
  /// In zh, this message translates to:
  /// **'建议的变更（需确认后生效）'**
  String get aiProposedChanges;

  /// No description provided for @aiChangeRow.
  ///
  /// In zh, this message translates to:
  /// **'{minutes} 分钟 · {reason}'**
  String aiChangeRow(Object minutes, Object reason);

  /// No description provided for @aiNothingChanged.
  ///
  /// In zh, this message translates to:
  /// **'尚未做任何修改，请在日程页确认后再应用。'**
  String get aiNothingChanged;

  /// No description provided for @aiRequest.
  ///
  /// In zh, this message translates to:
  /// **'获取建议'**
  String get aiRequest;

  /// No description provided for @aiRequestAgain.
  ///
  /// In zh, this message translates to:
  /// **'再获取一条'**
  String get aiRequestAgain;
}

class _AppLocalizationsDelegate
    extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();

  @override
  Future<AppLocalizations> load(Locale locale) {
    return SynchronousFuture<AppLocalizations>(lookupAppLocalizations(locale));
  }

  @override
  bool isSupported(Locale locale) =>
      <String>['en', 'zh'].contains(locale.languageCode);

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}

AppLocalizations lookupAppLocalizations(Locale locale) {
  // Lookup logic when only language code is specified.
  switch (locale.languageCode) {
    case 'en':
      return AppLocalizationsEn();
    case 'zh':
      return AppLocalizationsZh();
  }

  throw FlutterError(
      'AppLocalizations.delegate failed to load unsupported locale "$locale". This is likely '
      'an issue with the localizations generation tool. Please file an issue '
      'on GitHub with a reproducible sample app and the gen-l10n configuration '
      'that was used.');
}
