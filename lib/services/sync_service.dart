import '../models/client.dart';
import '../models/sync_status.dart';
import '../repositories/queue_repository.dart';
import '../storage/local_queue_storage.dart';

class SyncService {
  final LocalQueueStorage _storage;
  final QueueRepository _repository;
  bool _isSyncing = false;

  SyncService(this._storage, this._repository);

  /// Renvoie true si au moins un client a été synchronisé
  Future<bool> synchronize() async {
    if (_isSyncing) return false;
    _isSyncing = true;
    var changed = false;

    try {
      final pending = await _storage.getPendingClients();
      for (final record in pending) {
        final id = record['id'] as String;
        try {
          await _storage.updateSyncStatus(id, SyncStatus.syncing);
          await _repository.registerOnServer(Client.fromLocalMap(record));
          await _storage.updateSyncStatus(id, SyncStatus.synced);
          changed = true;
        } catch (_) {
          await _storage.updateSyncStatus(id, SyncStatus.failed);
        }
      }
    } finally {
      _isSyncing = false;
    }
    return changed;
  }
}
