final class BackupSummary {
  const BackupSummary({
    required this.backupId,
    required this.name,
    required this.createdAt,
    required this.sizeBytes,
    required this.operationCount,
    required this.status,
  });

  factory BackupSummary.fromApiJson(Map<String, Object?> json) {
    const expectedKeys = <String>{
      'backup_id',
      'name',
      'created_at',
      'size_bytes',
      'operation_count',
      'status',
    };
    if (json.keys.toSet().difference(expectedKeys).isNotEmpty ||
        expectedKeys.difference(json.keys.toSet()).isNotEmpty) {
      throw const FormatException('Backup has unexpected fields.');
    }
    final backupId = json['backup_id'];
    final name = json['name'];
    final createdAt = json['created_at'];
    final sizeBytes = json['size_bytes'];
    final operationCount = json['operation_count'];
    final status = json['status'];
    if (backupId is! String ||
        name is! String ||
        createdAt is! String ||
        sizeBytes is! int ||
        operationCount is! int ||
        status is! String) {
      throw const FormatException('Backup has invalid field types.');
    }
    return BackupSummary(
      backupId: backupId.toLowerCase(),
      name: name,
      createdAt: DateTime.parse(createdAt).toUtc(),
      sizeBytes: sizeBytes,
      operationCount: operationCount,
      status: status,
    );
  }

  final String backupId;
  final String name;
  final DateTime createdAt;
  final int sizeBytes;
  final int operationCount;
  final String status;

  bool get isReady => status == 'ready';
}

final class BackupListResult {
  BackupListResult({required Iterable<BackupSummary> backups})
      : backups = List<BackupSummary>.unmodifiable(backups);

  final List<BackupSummary> backups;
}

const int maxBackupsPerAccount = 5;

String formatBackupBytes(int bytes) {
  if (bytes < 1024) {
    return '$bytes B';
  }
  if (bytes < 1024 * 1024) {
    return '${(bytes / 1024).toStringAsFixed(1)} KB';
  }
  return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
}
