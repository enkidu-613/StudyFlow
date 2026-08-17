// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for English (`en`).
class AppLocalizationsEn extends AppLocalizations {
  AppLocalizationsEn([String locale = 'en']) : super(locale);

  @override
  String get appTitle => 'StudyFlow';

  @override
  String get navToday => 'Today';

  @override
  String get navTasks => 'Tasks';

  @override
  String get navSchedule => 'Schedule';

  @override
  String get navFocus => 'Focus';

  @override
  String get navSettings => 'Settings';

  @override
  String get configErrorTitle => 'API address not configured';

  @override
  String get configErrorBody =>
      'Start the client with --dart-define=STUDYFLOW_API_BASE_URL=https://api.example.com';

  @override
  String get authSignIn => 'Sign in';

  @override
  String get authCreateAccount => 'Create account';

  @override
  String get authEmailLabel => 'Email';

  @override
  String get authPasswordLabel => 'Password';

  @override
  String get authConfirmPasswordLabel => 'Confirm password';

  @override
  String get authEmailRequired => 'Email is required';

  @override
  String get authEmailInvalid => 'Enter a valid email address';

  @override
  String get authPasswordRequired => 'Password is required';

  @override
  String authPasswordTooShort(Object min) {
    return 'Password must be at least $min characters';
  }

  @override
  String get authPasswordTooLong => 'Password is too long';

  @override
  String authPasswordMaxLength(Object max) {
    return 'Password must be at most $max characters';
  }

  @override
  String get authPasswordNoSpaces => 'Password must not contain spaces';

  @override
  String get authPasswordAllDigits => 'Password must not be all digits';

  @override
  String get authPasswordMatchesEmail =>
      'Password must not match the account email';

  @override
  String authPasswordMissing(Object missing) {
    return 'Password must contain $missing';
  }

  @override
  String get authConfirmRequired => 'Confirm your password';

  @override
  String get authPasswordMismatch => 'Passwords do not match';

  @override
  String get authErrorInvalidCredentials => 'Invalid email or password';

  @override
  String get authErrorEmailTaken => 'This email is already registered';

  @override
  String get authErrorInvalidInput => 'Invalid email or password format';

  @override
  String get authErrorTooManyAttempts => 'Too many attempts. Try again later.';

  @override
  String get authErrorUnavailable => 'Service unavailable. Try again later.';

  @override
  String get authErrorGeneric => 'Operation failed. Try again later.';

  @override
  String get authSessionExpired =>
      'Your session has expired. Please sign in again.';

  @override
  String get authNetworkFailed =>
      'Network error. Check your connection and retry.';

  @override
  String authRestoreFailed(Object detail) {
    return 'Could not restore previous session: $detail';
  }

  @override
  String get authWorking => 'Working…';

  @override
  String get homeNotifications => 'Notifications';

  @override
  String get homeNotifGranted => 'granted';

  @override
  String get homeNotifRequired => 'permission required';

  @override
  String get homeCheckIn => 'Check in';

  @override
  String get homeLastCheckIn => 'Last check-in';

  @override
  String minutesShort(Object count) {
    return '$count min';
  }

  @override
  String get minutesSuffix => 'min';

  @override
  String get tasksEmpty => 'No tasks';

  @override
  String get taskEmptyFiltered => 'No tasks match the current filter';

  @override
  String get taskEmptyHint => 'Tap + to create your first task';

  @override
  String get taskFilterAll => 'All';

  @override
  String get taskFilterTodo => 'To do';

  @override
  String get taskFilterInProgress => 'In progress';

  @override
  String get taskFilterCompleted => 'Completed';

  @override
  String taskGroupInProgress(Object count) {
    return 'In progress · $count';
  }

  @override
  String taskGroupTodo(Object count) {
    return 'To do · $count';
  }

  @override
  String taskGroupCompleted(Object count) {
    return 'Completed · $count';
  }

  @override
  String get taskMarkInProgress => 'Mark in progress';

  @override
  String get taskMarkCompleted => 'Mark completed';

  @override
  String get taskMarkCancelled => 'Mark cancelled';

  @override
  String get taskDelete => 'Delete task';

  @override
  String get taskDeleteBody => 'This cannot be undone. Delete this task?';

  @override
  String get taskDeleted => 'Task deleted';

  @override
  String get taskEditAction => 'Edit';

  @override
  String get taskNew => 'New task';

  @override
  String get taskEdit => 'Edit task';

  @override
  String get taskTitleLabel => 'Title';

  @override
  String get taskDescriptionLabel => 'Description';

  @override
  String get taskEstimatedMinutes => 'Estimated minutes';

  @override
  String get taskPriorityLabel => 'Priority';

  @override
  String get taskRepeatLabel => 'Repeat';

  @override
  String get taskTagsLabel => 'Tags';

  @override
  String get taskTagsHint => 'e.g. math, reading';

  @override
  String get taskTitleRequired => 'Title is required';

  @override
  String get taskMinutesPositive => 'Minutes must be positive';

  @override
  String taskRowSubtitle(Object minutes, Object priority) {
    return '$minutes min · $priority';
  }

  @override
  String get commonSave => 'Save';

  @override
  String get commonCancel => 'Cancel';

  @override
  String get commonDelete => 'Delete';

  @override
  String get scheduleEmpty => 'No schedule blocks';

  @override
  String get scheduleEmptyHint => 'Tap + to add a schedule block';

  @override
  String get scheduleGroupToday => 'Today';

  @override
  String get scheduleGroupTomorrow => 'Tomorrow';

  @override
  String get blockNew => 'New block';

  @override
  String get blockEdit => 'Edit block';

  @override
  String get blockDelete => 'Delete block';

  @override
  String get blockDeleteBody => 'This cannot be undone. Delete this block?';

  @override
  String get blockDeleted => 'Block deleted';

  @override
  String get blockLockedHint => 'This block is locked and cannot be edited';

  @override
  String blockReminderBody(Object time) {
    return 'Starts at $time';
  }

  @override
  String get blockReminderDefaultTitle => 'Schedule reminder';

  @override
  String get blockKindTask => 'Task';

  @override
  String get blockKindRest => 'Rest';

  @override
  String get blockKindSleep => 'Sleep';

  @override
  String get blockKindBreakTime => 'Break';

  @override
  String get blockUnknownTask => 'Unknown task';

  @override
  String get blockKindLabel => 'Kind';

  @override
  String get blockTaskLabel => 'Task';

  @override
  String get blockLocked => 'Locked';

  @override
  String get blockRepeatLabel => 'Repeat';

  @override
  String get blockRepeatNone => 'Does not repeat';

  @override
  String get blockRepeatDaily => 'Every day';

  @override
  String get blockRepeatWeekdays => 'Weekdays (Mon-Fri)';

  @override
  String get blockRepeatWeekends => 'Weekends (Sat-Sun)';

  @override
  String get blockRepeatWeekly => 'Every week';

  @override
  String get blockEndAfterStart => 'End must be after start';

  @override
  String get focusStart => 'Start';

  @override
  String get focusPause => 'Pause';

  @override
  String get focusResume => 'Resume';

  @override
  String get focusFinish => 'Finish';

  @override
  String get focusTaskLabel => 'Task';

  @override
  String get focusSessionsTitle => 'Sessions';

  @override
  String get focusDefaultTitle => 'StudyFlow focus';

  @override
  String get focusTimeRemaining => 'Time remaining';

  @override
  String get focusPausedRemaining => 'Time remaining (paused)';

  @override
  String get focusCompleted => 'Focus session complete';

  @override
  String focusCompletedTitle(Object title) {
    return '$title focus complete';
  }

  @override
  String get focusCompletedBody => 'Time for a break.';

  @override
  String get checkInsEmpty => 'No check-ins yet';

  @override
  String get checkInNew => 'New check-in';

  @override
  String get checkInSleepMinutes => 'Sleep minutes';

  @override
  String get checkInSleepQuality => 'Sleep quality';

  @override
  String get checkInEnergy => 'Energy';

  @override
  String get checkInMood => 'Mood';

  @override
  String get checkInFeedback => 'Feedback';

  @override
  String get checkInSleepInvalid =>
      'Sleep minutes must be a non-negative number';

  @override
  String checkInRowTitle(Object energy, Object minutes) {
    return '$minutes min sleep · energy $energy';
  }

  @override
  String get settingsUsageSummary => 'Usage summary';

  @override
  String get settingsPermissions => 'Permissions';

  @override
  String get permissionAvailable => 'available';

  @override
  String get permissionUnavailable => 'unavailable';

  @override
  String get permissionAllowed => 'Allowed';

  @override
  String get permissionDenied => 'Denied';

  @override
  String get permissionNotifications => 'Notifications';

  @override
  String get permissionExactAlarm => 'Exact alarm';

  @override
  String get permissionBackground => 'Background';

  @override
  String get permissionBatteryOptimization => 'Battery optimization';

  @override
  String get permissionUsageAccess => 'Usage access';

  @override
  String get permissionUserNotifications => 'User notifications';

  @override
  String get permissionMenuBar => 'Menu bar';

  @override
  String get permissionFocus => 'Focus mode';

  @override
  String get permissionDetailGranted => 'granted';

  @override
  String get permissionDetailRequired => 'permission required';

  @override
  String get permissionPromptDeclined =>
      'Notifications are not enabled. You can allow them in System Settings later.';

  @override
  String get permissionPromptSettingsOpened =>
      'System settings opened. Allow the StudyFlow permission there.';

  @override
  String get permissionPromptDenied =>
      'System Settings opened. Allow notifications for StudyFlow there.';

  @override
  String get permissionPromptFailed =>
      'Permission request failed. Try again later.';

  @override
  String get permissionUnavailableTitle =>
      'This permission cannot be requested here';

  @override
  String permissionUnavailableMessage(Object permission) {
    return '$permission must be configured in system settings. StudyFlow cannot open a direct authorization prompt for it.';
  }

  @override
  String get settingsAiEntry => 'AI settings';

  @override
  String get settingsAiSubtitle => 'Configure Base URL, model, and API key';

  @override
  String get settingsSignOut => 'Sign out';

  @override
  String get settingsLanguage => 'Language';

  @override
  String get settingsLanguageSystem => 'System default';

  @override
  String get settingsLanguageZh => '简体中文';

  @override
  String get settingsLanguageEn => 'English';

  @override
  String get settingsBackupsEntry => 'Client backups';

  @override
  String get settingsBackupsSubtitle => 'Back up client records to the server';

  @override
  String get backupsCreate => 'Create backup';

  @override
  String get backupsCapacityTitle => 'Storage used';

  @override
  String backupsCapacityText(Object max, Object used) {
    return '$used/$max used';
  }

  @override
  String get backupsCapacityFull => 'Limit reached. Delete some backups first.';

  @override
  String get backupsEmpty => 'No backups yet';

  @override
  String get backupsEmptyHint => 'Create your first backup below';

  @override
  String backupsDefaultName(Object date) {
    return 'Backup $date';
  }

  @override
  String backupsItemSubtitle(Object date, Object operations, Object size) {
    return '$date · $size · $operations records';
  }

  @override
  String get backupsRename => 'Rename';

  @override
  String get backupsRenameTitle => 'Rename backup';

  @override
  String get backupsRenameLabel => 'Backup name';

  @override
  String get backupsRenameRequired => 'Name is required';

  @override
  String backupsRenameTooLong(Object max) {
    return 'Name must be at most $max characters';
  }

  @override
  String get backupsRenameSuccess => 'Renamed';

  @override
  String get backupsDelete => 'Delete';

  @override
  String get backupsDeleteTitle => 'Delete backup';

  @override
  String get backupsDeleteBody => 'This cannot be undone. Delete this backup?';

  @override
  String get backupsDeleteSuccess => 'Deleted';

  @override
  String get backupsLimitTitle => 'Backup limit reached';

  @override
  String backupsLimitBody(Object max) {
    return 'Each account can keep up to $max backups. Delete some first.';
  }

  @override
  String get backupsLimitGoDelete => 'Delete some';

  @override
  String get backupsCreateSuccess => 'Backup created';

  @override
  String backupsOperationFailed(Object reason) {
    return 'Operation failed: $reason';
  }

  @override
  String get backupsCreateTooFrequent =>
      'Creating backups too frequently. Try again later.';

  @override
  String get backupsLoadFailed => 'Could not load backups. Try again later.';

  @override
  String get backupsLoadFailedOffline =>
      'Network error. Check your connection and retry.';

  @override
  String get backupsRetry => 'Retry';

  @override
  String get backupsEdit => 'Edit';

  @override
  String backupsSelectionTitle(Object count) {
    return '$count selected';
  }

  @override
  String get backupsSelectAll => 'Select all';

  @override
  String get backupsSelectNone => 'Select none';

  @override
  String backupsDeleteSelected(Object count) {
    return 'Delete ($count)';
  }

  @override
  String get backupsBatchDeleteTitle => 'Delete selected backups';

  @override
  String backupsBatchDeleteBody(Object count) {
    return 'This permanently deletes $count backups and cannot be undone. Continue?';
  }

  @override
  String backupsBatchDeleteSuccess(Object count) {
    return 'Deleted $count backups';
  }

  @override
  String backupsBatchDeletePartial(Object deleted, Object notFound) {
    return 'Deleted $deleted, $notFound not found';
  }

  @override
  String get syncUpToDate => 'Up to date';

  @override
  String get syncPending => 'Pending sync';

  @override
  String syncPendingCount(Object count) {
    return '$count changes pending';
  }

  @override
  String get syncSyncing => 'Synchronizing records…';

  @override
  String get syncOffline => 'Offline; local changes are safe';

  @override
  String syncFailed(Object category) {
    return 'Sync failed: $category';
  }

  @override
  String get syncNow => 'Sync now';

  @override
  String get syncRetryOnline => 'Retry when online';

  @override
  String get syncUnknown => 'unknown';

  @override
  String get aiEnabledTitle => 'Enable AI suggestions';

  @override
  String get aiEnabledSubtitle =>
      'API key stays in the device secure storage and is never uploaded.';

  @override
  String get aiProtocolLabel => 'API protocol';

  @override
  String get aiProtocolChat => 'OpenAI Chat Completions';

  @override
  String get aiProtocolResponses => 'OpenAI Responses';

  @override
  String get aiProtocolAnthropic => 'Anthropic Messages';

  @override
  String get aiEndpointHintChat =>
      'Base URL example: https://provider.example/v1 → requests .../chat/completions';

  @override
  String get aiEndpointHintResponses =>
      'Base URL example: https://provider.example/v1 → requests .../responses';

  @override
  String get aiEndpointHintAnthropic =>
      'Base URL example: https://api.anthropic.com (do not append /v1 again if present)';

  @override
  String get aiBaseUrlLabel => 'Base URL';

  @override
  String get aiModelLabel => 'Model';

  @override
  String get aiApiKeyLabel => 'API Key';

  @override
  String get aiApiKeyHint => 'Enter API Key';

  @override
  String get aiApiKeySavedHint => 'Saved and hidden; leave blank to keep it';

  @override
  String get aiBaseUrlRequired => 'Base URL is required';

  @override
  String get aiBaseUrlInvalid => 'Enter a valid URL';

  @override
  String get aiBaseUrlRequireHttps => 'Base URL must use HTTPS';

  @override
  String get aiModelRequired => 'Model name is required';

  @override
  String get aiApiKeyRequired => 'API key is required';

  @override
  String get aiSave => 'Save';

  @override
  String get aiTestConnection => 'Test connection';

  @override
  String get aiClearConfig => 'Clear configuration';

  @override
  String get aiClearTitle => 'Clear AI configuration';

  @override
  String get aiClearBody =>
      'This removes the local Base URL, model, and API key. Continue?';

  @override
  String get aiClearConfirm => 'Clear';

  @override
  String get aiSaved => 'Saved';

  @override
  String get aiCleared => 'Cleared';

  @override
  String get aiConnectionSuccess => 'Connection successful';

  @override
  String aiConnectionFailed(Object reason) {
    return 'Connection failed: $reason';
  }

  @override
  String get aiConnectionFailedGeneric => 'Connection failed. Try again later.';

  @override
  String get aiRecommendTitle => 'AI Recommendations';

  @override
  String get aiRecommendError => 'Recommendation unavailable';

  @override
  String get aiProposedChanges => 'Proposed changes (require confirmation)';

  @override
  String aiChangeRow(Object minutes, Object reason) {
    return '$minutes min · $reason';
  }

  @override
  String get aiNothingChanged =>
      'Nothing was changed. Confirm in the schedule screen after review.';

  @override
  String get aiRequest => 'Request recommendation';

  @override
  String get aiRequestAgain => 'Request another';
}
