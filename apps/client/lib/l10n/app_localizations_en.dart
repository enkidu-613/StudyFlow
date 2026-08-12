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
  String get scheduleEmpty => 'No schedule blocks';

  @override
  String get blockNew => 'New block';

  @override
  String get blockKindLabel => 'Kind';

  @override
  String get blockTaskLabel => 'Task';

  @override
  String get blockLocked => 'Locked';

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
  String get settingsAiEntry => 'AI settings';

  @override
  String get settingsAiSubtitle => 'Configure Base URL, model, and API key';

  @override
  String get settingsSignOut => 'Sign out';

  @override
  String get syncPendingTitle => 'Pending sync';

  @override
  String get syncIdle => 'Synchronized or waiting for changes';

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
  String get aiBaseUrlLabel => 'Base URL';

  @override
  String get aiModelLabel => 'Model';

  @override
  String get aiApiKeyLabel => 'API Key';

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
