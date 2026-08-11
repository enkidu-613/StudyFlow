import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:studyflow/auth/auth_repository.dart';
import 'package:studyflow/storage/app_database.dart';
import 'package:studyflow/sync/sync_api.dart';
import 'package:studyflow/sync/sync_engine.dart';
import 'package:studyflow/sync/sync_status.dart';

final class AppSyncDependencies {
  const AppSyncDependencies({
    required this.api,
    required this.authContext,
    required this.store,
  });

  final SyncApi api;
  final AuthContext authContext;
  final AccountScopedStore store;
}

final Provider<AppSyncDependencies?> appSyncDependenciesProvider =
    Provider<AppSyncDependencies?>((ref) => null);

final Provider<SyncEngine?> syncEngineProvider = Provider<SyncEngine?>((ref) {
  final dependencies = ref.watch(appSyncDependenciesProvider);
  if (dependencies == null) {
    return null;
  }
  final engine = SyncEngine(
    api: dependencies.api,
    authContext: dependencies.authContext,
    store: dependencies.store,
  );
  ref.onDispose(engine.dispose);
  return engine;
});

final Provider<SyncStatusListenable?> syncStatusProvider =
    Provider<SyncStatusListenable?>((ref) {
  return ref.watch(syncEngineProvider)?.status;
});
