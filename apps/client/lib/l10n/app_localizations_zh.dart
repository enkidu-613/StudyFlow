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
  String get taskEmptyFiltered => '当前筛选下没有任务';

  @override
  String get taskEmptyHint => '点击右下角按钮新建第一个任务';

  @override
  String get taskFilterAll => '全部';

  @override
  String get taskFilterTodo => '待办';

  @override
  String get taskFilterInProgress => '进行中';

  @override
  String get taskFilterCompleted => '已完成';

  @override
  String taskGroupInProgress(Object count) {
    return '进行中 · $count';
  }

  @override
  String taskGroupTodo(Object count) {
    return '待办 · $count';
  }

  @override
  String taskGroupCompleted(Object count) {
    return '已完成 · $count';
  }

  @override
  String get taskMarkInProgress => '标记进行中';

  @override
  String get taskMarkCompleted => '标记完成';

  @override
  String get taskMarkCancelled => '标记取消';

  @override
  String get taskDelete => '删除任务';

  @override
  String get taskDeleteBody => '删除后不可恢复，确定删除该任务吗？';

  @override
  String get taskDeleted => '已删除任务';

  @override
  String get taskEditAction => '编辑';

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
  String get commonDelete => '删除';

  @override
  String get scheduleEmpty => '还没有日程块';

  @override
  String get scheduleEmptyHint => '点击右下角按钮添加日程块';

  @override
  String get scheduleGroupToday => '今天';

  @override
  String get scheduleGroupTomorrow => '明天';

  @override
  String get blockNew => '新建日程块';

  @override
  String get blockEdit => '编辑日程块';

  @override
  String get blockDelete => '删除日程块';

  @override
  String get blockDeleteBody => '删除后不可恢复，确定删除该日程块吗？';

  @override
  String get blockDeleted => '已删除日程块';

  @override
  String get blockLockedHint => '该日程块已锁定，无法修改';

  @override
  String blockReminderBody(Object time) {
    return '$time 开始';
  }

  @override
  String get blockReminderDefaultTitle => '日程提醒';

  @override
  String get blockKindTask => '任务';

  @override
  String get blockKindRest => '休息';

  @override
  String get blockKindSleep => '睡眠';

  @override
  String get blockKindBreakTime => '小憩';

  @override
  String get blockUnknownTask => '未知任务';

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
  String get focusTimeRemaining => '剩余时间';

  @override
  String get focusPausedRemaining => '剩余时间（已暂停）';

  @override
  String get focusCompleted => '专注结束';

  @override
  String focusCompletedTitle(Object title) {
    return '$title 专注完成';
  }

  @override
  String get focusCompletedBody => '任务专注时长已到，休息一下吧。';

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
  String get permissionPromptDeclined => '通知权限未开启，可稍后到系统设置中开启';

  @override
  String get permissionPromptDenied => '已打开系统设置，请在通知中允许 StudyFlow';

  @override
  String get permissionPromptFailed => '权限请求失败，请稍后重试';

  @override
  String get permissionUnavailableTitle => '该权限在 macOS 上不可用';

  @override
  String permissionUnavailableMessage(Object permission) {
    return '$permission 是移动平台专属权限，macOS 上不需要授权。';
  }

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
  String get settingsBackupsEntry => '客户端备份';

  @override
  String get settingsBackupsSubtitle => '将客户端记录备份到服务器';

  @override
  String get backupsCreate => '新建备份';

  @override
  String get backupsCapacityTitle => '备份容量';

  @override
  String backupsCapacityText(Object max, Object used) {
    return '已用 $used/$max';
  }

  @override
  String get backupsCapacityFull => '已达上限，请先删除部分备份';

  @override
  String get backupsEmpty => '还没有备份';

  @override
  String get backupsEmptyHint => '点击下方按钮创建第一个备份';

  @override
  String backupsDefaultName(Object date) {
    return '备份 $date';
  }

  @override
  String backupsItemSubtitle(Object date, Object operations, Object size) {
    return '$date · $size · $operations 条记录';
  }

  @override
  String get backupsRename => '重命名';

  @override
  String get backupsRenameTitle => '重命名备份';

  @override
  String get backupsRenameLabel => '备份名称';

  @override
  String get backupsRenameRequired => '请输入备份名称';

  @override
  String backupsRenameTooLong(Object max) {
    return '名称最多 $max 个字符';
  }

  @override
  String get backupsRenameSuccess => '已重命名';

  @override
  String get backupsDelete => '删除';

  @override
  String get backupsDeleteTitle => '删除备份';

  @override
  String get backupsDeleteBody => '删除后不可恢复，确定删除该备份吗？';

  @override
  String get backupsDeleteSuccess => '已删除';

  @override
  String get backupsLimitTitle => '已达备份上限';

  @override
  String backupsLimitBody(Object max) {
    return '每个账户最多可保留 $max 个备份，请先删除部分备份。';
  }

  @override
  String get backupsLimitGoDelete => '去删除';

  @override
  String get backupsCreateSuccess => '已创建备份';

  @override
  String backupsOperationFailed(Object reason) {
    return '操作失败：$reason';
  }

  @override
  String get backupsCreateTooFrequent => '创建备份过于频繁，请稍后再试';

  @override
  String get backupsLoadFailed => '加载备份失败，请稍后重试';

  @override
  String get backupsLoadFailedOffline => '网络连接失败，请检查网络后重试';

  @override
  String get backupsRetry => '重试';

  @override
  String get backupsEdit => '编辑';

  @override
  String backupsSelectionTitle(Object count) {
    return '已选 $count 项';
  }

  @override
  String get backupsSelectAll => '全选';

  @override
  String get backupsSelectNone => '全不选';

  @override
  String backupsDeleteSelected(Object count) {
    return '删除 ($count)';
  }

  @override
  String get backupsBatchDeleteTitle => '删除所选备份';

  @override
  String backupsBatchDeleteBody(Object count) {
    return '将删除 $count 个备份，删除后不可恢复。确定继续吗？';
  }

  @override
  String backupsBatchDeleteSuccess(Object count) {
    return '已删除 $count 个备份';
  }

  @override
  String backupsBatchDeletePartial(Object deleted, Object notFound) {
    return '已删除 $deleted 个，$notFound 个不存在';
  }

  @override
  String get syncUpToDate => '同步完成';

  @override
  String get syncPending => '待同步';

  @override
  String syncPendingCount(Object count) {
    return '$count 条更改待同步';
  }

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
