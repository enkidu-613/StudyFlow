import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:studyflow/features/checkins/check_in_repository.dart';
import 'package:studyflow/features/focus/focus_repository.dart';
import 'package:studyflow/features/schedule/schedule_repository.dart';
import 'package:studyflow/features/tasks/task_repository.dart';
import 'package:studyflow/platform/platform_bridge.dart';
import 'package:studyflow/security/key_manager.dart';
import 'package:studyflow/security/payload_cipher.dart';
import 'package:studyflow/storage/app_database.dart';
import 'package:studyflow/util/uuid.dart';

final class StudyFlowWorkspace {
  StudyFlowWorkspace._({
    required this.accountId,
    required this.deviceId,
    required this.store,
    required this.cipher,
    required this.tasks,
    required this.schedule,
    required this.focus,
    required this.checkIns,
    required this.platform,
  }) : _logicalClock = DateTime.now().toUtc().microsecondsSinceEpoch;

  static const String _localAccountId = '00000000-0000-4000-8000-000000000000';
  static const String _localDeviceId = '11111111-1111-4111-8111-111111111111';

  final String accountId;
  final String deviceId;
  final AccountScopedStore store;
  final PayloadCipher cipher;
  final TaskRepository tasks;
  final ScheduleRepository schedule;
  final FocusRepository focus;
  final CheckInRepository checkIns;
  final PlatformBridge platform;
  int _logicalClock;

  Future<EncryptedWrite> nextWrite() {
    final now = DateTime.now().toUtc().microsecondsSinceEpoch;
    _logicalClock = max(_logicalClock + 1, now);
    return Future<EncryptedWrite>.value(
      EncryptedWrite(
        operationId: newUuidV4(),
        deviceId: deviceId,
        logicalClock: _logicalClock,
      ),
    );
  }

  Future<int> pendingCount() => store.operations.pendingCount();

  Future<void> close() => store.close();

  static Future<StudyFlowWorkspace> openLocalShell() async {
    final keyManager = KeyManager(accountId: _localAccountId);
    await _ensureAccountKey(keyManager);
    final store = await AccountScopedStore.open(
      activeAccountId: _localAccountId,
      keyManager: keyManager,
    );
    return _create(
      accountId: _localAccountId,
      deviceId: _localDeviceId,
      keyManager: keyManager,
      store: store,
    );
  }

  @visibleForTesting
  static Future<StudyFlowWorkspace> openForTesting({
    required KeyManager keyManager,
    required Directory baseDirectory,
    PlatformBridge? platform,
  }) async {
    await _ensureAccountKey(keyManager);
    // ignore: invalid_use_of_visible_for_testing_member
    final store = await AccountScopedStore.openForTesting(
      activeAccountId: keyManager.accountId,
      keyManager: keyManager,
      baseDirectory: baseDirectory,
    );
    return _create(
      accountId: keyManager.accountId,
      deviceId: _localDeviceId,
      keyManager: keyManager,
      store: store,
      platform: platform,
    );
  }

  static Future<void> _ensureAccountKey(KeyManager keyManager) async {
    try {
      await keyManager.createAccountDataKey();
    } on StateError {
      await keyManager.loadAccountDataKey();
    }
  }

  static StudyFlowWorkspace _create({
    required String accountId,
    required String deviceId,
    required KeyManager keyManager,
    required AccountScopedStore store,
    PlatformBridge? platform,
  }) {
    final cipher = PayloadCipher(keyManager);
    return StudyFlowWorkspace._(
      accountId: accountId,
      deviceId: deviceId,
      store: store,
      cipher: cipher,
      tasks: TaskRepository(store: store, cipher: cipher),
      schedule: ScheduleRepository(store: store, cipher: cipher),
      focus: FocusRepository(store: store, cipher: cipher),
      checkIns: CheckInRepository(store: store, cipher: cipher),
      platform: platform ?? PlatformBridge(),
    );
  }
}
