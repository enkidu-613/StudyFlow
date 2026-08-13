// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Chinese (`zh`).
class AppLocalizationsZh extends AppLocalizations {
  AppLocalizationsZh([String locale = 'zh']) : super(locale);

  @override
  String get appTitle => 'StudyFlow';

  @override
  String get navToday => '今天';

  @override
  String get navTasks => '任务';

  @override
  String get navSchedule => '日程';

  @override
  String get navFocus => '专注';

  @override
  String get navSettings => '设置';

  @override
  String get configErrorTitle => 'API 地址未配置';

  @override
  String get configErrorBody =>
      '请使用 --dart-define=STUDYFLOW_API_BASE_URL=https://api.example.com 启动客户端。';

  @override
  String get authSignIn => '登录';

  @override
  String get authCreateAccount => '注册';

  @override
  String get authEmailLabel => '邮箱';

  @override
  String get authPasswordLabel => '密码';

  @override
  String get authConfirmPasswordLabel => '确认密码';

  @override
  String get authEmailRequired => '请输入邮箱';

  @override
  String get authEmailInvalid => '请输入有效的邮箱地址';

  @override
  String get authPasswordRequired => '请输入密码';

  @override
  String authPasswordTooShort(Object min) {
    return '密码至少需要 $min 位';
  }

  @override
  String get authPasswordTooLong => '密码过长';

  @override
  String authPasswordMaxLength(Object max) {
    return '密码最多 $max 位';
  }

  @override
  String get authPasswordNoSpaces => '密码不能包含空格';

  @override
  String get authPasswordAllDigits => '密码不能全为数字';

  @override
  String get authPasswordMatchesEmail => '密码不能与注册邮箱相同';

  @override
  String authPasswordMissing(Object missing) {
    return '密码必须包含$missing';
  }

  @override
  String get authConfirmRequired => '请再次输入密码';

  @override
  String get authPasswordMismatch => '两次输入的密码不一致';

  @override
  String get authErrorInvalidCredentials => '邮箱或密码错误';

  @override
  String get authErrorEmailTaken => '该邮箱已被注册';

  @override
  String get authErrorInvalidInput => '邮箱或密码格式不正确';

  @override
  String get authErrorTooManyAttempts => '尝试次数过多，请稍后再试';

  @override
  String get authErrorUnavailable => '服务暂时不可用，请稍后重试';

  @override
  String get authErrorGeneric => '操作失败，请稍后重试';

  @override
  String get authSessionExpired => '登录已过期，请重新登录';

  @override
  String get authNetworkFailed => '网络连接失败，请检查网络后重试';

  @override
  String authRestoreFailed(Object detail) {
    return '无法恢复上次会话：$detail';
  }

  @override
  String get authWorking => '正在处理…';

  @override
  String get homeNotifications => '通知';

  @override
  String get homeNotifGranted => '已授权';

  @override
  String get homeNotifRequired => '需要授权';

  @override
  String get homeCheckIn => '打卡';

  @override
  String get homeLastCheckIn => '最近打卡';

  @override
  String minutesShort(Object count) {
    return '$count 分钟';
  }

  @override
  String get minutesSuffix => '分钟';

  @override
  String get tasksEmpty => '还没有任务';

  @override
  String get taskNew => '新建任务';

  @override
  String get taskEdit => '编辑任务';

  @override
  String get taskTitleLabel => '标题';

  @override
  String get taskDescriptionLabel => '描述';

  @override
  String get taskEstimatedMinutes => '预计分钟数';

  @override
  String get taskPriorityLabel => '优先级';

  @override
  String get taskRepeatLabel => '重复';

  @override
  String get taskTagsLabel => '标签';

  @override
  String get taskTagsHint => '例如：数学, 阅读';

  @override
  String get taskTitleRequired => '请输入标题';

  @override
  String get taskMinutesPositive => '分钟数必须为正数';

  @override
  String taskRowSubtitle(Object minutes, Object priority) {
    return '$minutes 分钟 · $priority';
  }

  @override
  String get commonSave => '保存';

  @override
  String get commonCancel => '取消';

  @override
  String get scheduleEmpty => '还没有日程块';

  @override
  String get blockNew => '新建日程块';

  @override
  String get blockKindLabel => '类型';

  @override
  String get blockTaskLabel => '关联任务';

  @override
  String get blockLocked => '锁定';

  @override
  String get blockEndAfterStart => '结束时间必须晚于开始时间';

  @override
  String get focusStart => '开始';

  @override
  String get focusPause => '暂停';

  @override
  String get focusResume => '继续';

  @override
  String get focusFinish => '结束';

  @override
  String get focusTaskLabel => '任务';

  @override
  String get focusSessionsTitle => '历史记录';

  @override
  String get focusDefaultTitle => 'StudyFlow 专注';

  @override
  String get checkInsEmpty => '还没有打卡记录';

  @override
  String get checkInNew => '新建打卡';

  @override
  String get checkInSleepMinutes => '睡眠时长';

  @override
  String get checkInSleepQuality => '睡眠质量';

  @override
  String get checkInEnergy => '精力';

  @override
  String get checkInMood => '心情';

  @override
  String get checkInFeedback => '反馈';

  @override
  String get checkInSleepInvalid => '睡眠时长必须是非负数字';

  @override
  String checkInRowTitle(Object energy, Object minutes) {
    return '睡眠 $minutes 分钟 · 精力 $energy';
  }

  @override
  String get settingsUsageSummary => '使用统计';

  @override
  String get settingsPermissions => '权限';

  @override
  String get permissionAvailable => '可用';

  @override
  String get permissionUnavailable => '不可用';

  @override
  String get permissionAllowed => '已允许';

  @override
  String get permissionDenied => '未允许';

  @override
  String get permissionNotifications => '通知';

  @override
  String get permissionExactAlarm => '精确闹钟';

  @override
  String get permissionBackground => '后台运行';

  @override
  String get permissionBatteryOptimization => '电池优化白名单';

  @override
  String get permissionUsageAccess => '使用情况访问';

  @override
  String get permissionUserNotifications => '用户通知';

  @override
  String get permissionMenuBar => '菜单栏';

  @override
  String get permissionFocus => '专注模式';

  @override
  String get permissionDetailGranted => '已授权';

  @override
  String get permissionDetailRequired => '需要授权';

  @override
  String get settingsAiEntry => 'AI 设置';

  @override
  String get settingsAiSubtitle => '配置 Base URL、模型和 API Key';

  @override
  String get settingsSignOut => '退出登录';

  @override
  String get settingsLanguage => '语言';

  @override
  String get settingsLanguageSystem => '跟随系统';

  @override
  String get settingsLanguageZh => '简体中文';

  @override
  String get settingsLanguageEn => 'English';

  @override
  String get syncPendingTitle => '待同步';

  @override
  String get syncIdle => '已同步或等待变更';

  @override
  String get syncSyncing => '正在同步记录…';

  @override
  String get syncOffline => '当前离线，本地更改已安全保存';

  @override
  String syncFailed(Object category) {
    return '同步失败：$category';
  }

  @override
  String get syncNow => '立即同步';

  @override
  String get syncRetryOnline => '联网后重试';

  @override
  String get syncUnknown => '未知';

  @override
  String get aiEnabledTitle => '启用 AI 建议';

  @override
  String get aiEnabledSubtitle => 'API Key 只保存在本机安全存储，不会上传。';

  @override
  String get aiBaseUrlLabel => 'Base URL';

  @override
  String get aiModelLabel => 'Model';

  @override
  String get aiApiKeyLabel => 'API Key';

  @override
  String get aiBaseUrlRequired => 'Base URL 不能为空';

  @override
  String get aiBaseUrlInvalid => '请输入有效的 URL';

  @override
  String get aiBaseUrlRequireHttps => 'Base URL 必须使用 HTTPS';

  @override
  String get aiModelRequired => 'Model 名称不能为空';

  @override
  String get aiApiKeyRequired => 'API Key 不能为空';

  @override
  String get aiSave => '保存';

  @override
  String get aiTestConnection => '测试连接';

  @override
  String get aiClearConfig => '清除配置';

  @override
  String get aiClearTitle => '清除 AI 配置';

  @override
  String get aiClearBody => '将删除本机的 Base URL、模型和 API Key，确定吗？';

  @override
  String get aiClearConfirm => '清除';

  @override
  String get aiSaved => '已保存';

  @override
  String get aiCleared => '已清除';

  @override
  String get aiConnectionSuccess => '连接成功';

  @override
  String aiConnectionFailed(Object reason) {
    return '连接失败：$reason';
  }

  @override
  String get aiConnectionFailedGeneric => '连接失败，请稍后重试';

  @override
  String get aiRecommendTitle => 'AI 建议';

  @override
  String get aiRecommendError => '暂时无法获取建议';

  @override
  String get aiProposedChanges => '建议的变更（需确认后生效）';

  @override
  String aiChangeRow(Object minutes, Object reason) {
    return '$minutes 分钟 · $reason';
  }

  @override
  String get aiNothingChanged => '尚未做任何修改，请在日程页确认后再应用。';

  @override
  String get aiRequest => '获取建议';

  @override
  String get aiRequestAgain => '再获取一条';
}
