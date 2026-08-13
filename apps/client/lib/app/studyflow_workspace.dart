import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:studyflow/auth/auth_repository.dart';
import 'package:studyflow/features/checkins/check_in_repository.dart';
import 'package:studyflow/features/focus/focus_repository.dart';
import 'package:studyflow/features/schedule/schedule_alarm_service.dart';
import 'package:studyflow/features/schedule/schedule_repository.dart';
import 'package:studyflow/features/tasks/task_repository.dart';
import 'package:studyflow/platform/platform_bridge.dart';
import 'package:studyflow/storage/app_database.dart';
import 'package:studyflow/util/uuid.dart';

final class StudyFlowWorkspace {
  StudyFlowWorkspace._({
    required this.accountId,
    required this.store,
    required this.tasks,
    required this.schedule,
    required this.focus,
    required this.checkIns,
    required this.platform,
  }) : _logicalClock = DateTime.now().toUtc().microsecondsSinceEpoch;

  static const String _localAccountId = '00000000-0000-4000-8000-000000000000';

  final String accountId;
  final AccountScopedStore store;
  final TaskRepository tasks;
  final ScheduleRepository schedule;
  final FocusRepository focus;
  final CheckInRepository checkIns;
  final PlatformBridge platform;
  late final ScheduleAlarmService alarms;
  int _logicalClock;

  Future<Write> nextWrite() {
    final now = DateTime.now().toUtc().microsecondsSinceEpoch;
    _logicalClock = max(_logicalClock + 1, now);
    return Future<Write>.value(
      Write(
        operationId: newUuidV4(),
        logicalClock: _logicalClock,
      ),
    );
  }

  Future<int> pendingCount() => store.operations.pendingCount();

  Future<void> close() {
    alarms.dispose();
    return store.close();
  }

  static Future<StudyFlowWorkspace> openLocalShell() async {
    final store = await AccountScopedStore.open(
      activeAccountId: _localAccountId,
    );
    return _create(
      accountId: _localAccountId,
      store: store,
    );
  }

  static Future<StudyFlowWorkspace> openAuthenticated({
    required AuthContext authContext,
  }) async {
    final store = await AccountScopedStore.open(
      activeAccountId: authContext.userId,
    );
    return _create(
      accountId: authContext.userId,
      store: store,
    );
  }

  @visibleForTesting
  static Future<StudyFlowWorkspace> openForTesting({
    required String accountId,
    required Directory baseDirectory,
    PlatformBridge? platform,
  }) async {
    // ignore: invalid_use_of_visible_for_testing_member
    final store = await AccountScopedStore.openForTesting(
      activeAccountId: accountId,
      baseDirectory: baseDirectory,
    );
    return _create(
      accountId: accountId,
      store: store,
      platform: platform,
      alarmsEnabled: false,
    );
  }

  static StudyFlowWorkspace _create({
    required String accountId,
    required AccountScopedStore store,
    PlatformBridge? platform,
    bool alarmsEnabled = true,
  }) {
    final workspace = StudyFlowWorkspace._(
      accountId: accountId,
      store: store,
      tasks: TaskRepository(store: store),
      schedule: ScheduleRepository(store: store),
      focus: FocusRepository(store: store),
      checkIns: CheckInRepository(store: store),
      platform: platform ?? PlatformBridge(),
    );
    workspace.alarms = ScheduleAlarmService(
      workspace: workspace,
      enabled: alarmsEnabled,
    );
    return workspace;
  }
}
