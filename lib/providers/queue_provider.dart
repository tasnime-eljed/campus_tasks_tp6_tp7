import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

import '../models/client.dart';
import '../models/queue_state.dart';
import '../models/sync_status.dart';
import '../repositories/queue_repository.dart';
import '../services/geolocation_service.dart';

class QueueProvider extends ChangeNotifier {
  final QueueRepository _repository;
  final GeolocationService _geolocation;

  final List<Client> _clients = [];
  QueueState _state = QueueState.initial;
  String? _errorMessage;
  int _page = 0;
  static const int _pageSize = 20;
  bool _hasMore = true;
  bool _isLoadingMore = false;
  bool _disposed = false;
  RealtimeChannel? _channel;

  QueueProvider(
    this._repository,
    this._geolocation,
  );

  List<Client> get clients => List.unmodifiable(_clients);
  QueueState get state => _state;
  bool get hasMore => _hasMore;
  bool get isLoadingMore => _isLoadingMore;
  String? get errorMessage => _errorMessage;

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  Future<void> fetchInitialQueue() async {
    _state = QueueState.loading;
    _page = 0;
    _hasMore = true;
    _errorMessage = null;
    _notify();
    try {
      final remote = await _repository.fetchPage(offset: 0, limit: _pageSize);
      _clients
        ..clear()
        ..addAll(remote);
      if (remote.length < _pageSize) _hasMore = false;
      _state = _clients.isEmpty ? QueueState.empty : QueueState.loaded;
    } catch (_) {
      _errorMessage = 'Impossible de charger la file. Vérifiez votre connexion.';
      _state = QueueState.error;
    }
    _notify();
  }

  Future<void> addClient(String name) async {
    final user = Supabase.instance.client.auth.currentUser;
    if (user == null) throw StateError('Vous devez être connecté.');
    final position = await _geolocation.getCurrentPosition();
    final client = Client(
      id: const Uuid().v4(),
      name: name,
      userId: user.id,
      lat: position?.latitude,
      lng: position?.longitude,
      locationAccuracy: position?.accuracy,
      createdAt: DateTime.now().toUtc(),
      syncStatus: SyncStatus.synced,
    );
    await _repository.registerOnServer(client);
    await fetchInitialQueue();
  }

  Future<void> syncNow() => fetchInitialQueue();

  Future<void> deleteClient(String id) async {
    await _repository.deleteClient(id);
    _clients.removeWhere((client) => client.id == id);
    if (_clients.isEmpty) _state = QueueState.empty;
    _notify();
  }

  Future<void> callNextClient() async {
    final id = await _repository.callNextClient();
    if (id == null) return;
    _clients.removeWhere((client) => client.id == id);
    if (_clients.isEmpty) _state = QueueState.empty;
    _notify();
  }

  Future<void> loadMore() async {
    if (_isLoadingMore || !_hasMore) return;
    _isLoadingMore = true;
    _notify();
    try {
      _page++;
      final next = await _repository.fetchPage(
        offset: _page * _pageSize,
        limit: _pageSize,
      );
      _clients.addAll(next);
      if (next.length < _pageSize) _hasMore = false;
    } catch (_) {
      _page--;
    } finally {
      _isLoadingMore = false;
      _notify();
    }
  }

  void startRealtime() {
    _channel = _repository.subscribeToInserts(handleRealtimeInsert);
  }

  Future<void> handleRealtimeInsert(Client client) async {
    if (_clients.any((existing) => existing.id == client.id)) return;
    _clients.insert(0, client);
    if (_state == QueueState.empty) _state = QueueState.loaded;
    _notify();
  }

  @override
  void dispose() {
    _disposed = true;
    _channel?.unsubscribe();
    super.dispose();
  }
}
