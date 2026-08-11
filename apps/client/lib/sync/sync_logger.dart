import 'sync_status.dart';

enum SyncLogEventKind {
  started,
  pushSucceeded,
  pullApplied,
  failed,
}

final class SyncLogEvent {
  const SyncLogEvent({
    required this.kind,
    this.operationIds = const <String>[],
    this.pushedCount,
    this.pulledCount,
    this.pendingCount,
    this.cursor,
    this.failureCategory,
  });

  final SyncLogEventKind kind;
  final List<String> operationIds;
  final int? pushedCount;
  final int? pulledCount;
  final int? pendingCount;
  final int? cursor;
  final SyncFailureCategory? failureCategory;

  Map<String, Object?> toJson() => <String, Object?>{
        'kind': kind.name,
        'operationIds': operationIds,
        if (pushedCount != null) 'pushedCount': pushedCount,
        if (pulledCount != null) 'pulledCount': pulledCount,
        if (pendingCount != null) 'pendingCount': pendingCount,
        if (cursor != null) 'cursor': cursor,
        if (failureCategory != null) 'failureCategory': failureCategory!.name,
      };
}

abstract interface class SyncLogger {
  void write(SyncLogEvent event);
}

final class NoopSyncLogger implements SyncLogger {
  const NoopSyncLogger();

  @override
  void write(SyncLogEvent event) {}
}
