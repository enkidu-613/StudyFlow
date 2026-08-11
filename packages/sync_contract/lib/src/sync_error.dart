class SyncContractException implements Exception {
  const SyncContractException(this.message);

  final String message;

  @override
  String toString() => 'SyncContractException: $message';
}
