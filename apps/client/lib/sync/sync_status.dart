import 'package:flutter/foundation.dart';

enum SyncStatusKind { idle, syncing, offline, failed }

enum SyncFailureCategory {
  network,
  authentication,
  payload,
  schema,
  protocol,
}

enum SyncRunOutcome { succeeded, failed }

typedef SyncRetry = Future<SyncRunResult> Function();

final class SyncStatus {
  const SyncStatus({
    required this.kind,
    required this.pendingCount,
    this.failureCategory,
    this.failureMessage,
    this.retry,
  });

  const SyncStatus.idle({required int pendingCount})
      : this(kind: SyncStatusKind.idle, pendingCount: pendingCount);

  const SyncStatus.syncing({required int pendingCount})
      : this(kind: SyncStatusKind.syncing, pendingCount: pendingCount);

  final SyncStatusKind kind;
  final int pendingCount;
  final SyncFailureCategory? failureCategory;
  final String? failureMessage;
  final SyncRetry? retry;
}

final class SyncRunResult {
  const SyncRunResult({
    required this.outcome,
    required this.pushedCount,
    required this.pulledCount,
    required this.pendingCount,
    required this.cursor,
    this.failureCategory,
    this.failureMessage,
  });

  final SyncRunOutcome outcome;
  final int pushedCount;
  final int pulledCount;
  final int pendingCount;
  final int cursor;
  final SyncFailureCategory? failureCategory;
  final String? failureMessage;
}

typedef SyncStatusListenable = ValueListenable<SyncStatus>;
