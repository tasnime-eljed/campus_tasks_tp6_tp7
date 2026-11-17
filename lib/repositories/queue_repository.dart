import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/client.dart';

class QueueRepository {
  final SupabaseClient _supabase;

  QueueRepository(this._supabase);

  /// Page de clients, du plus récent au plus ancien
  Future<List<Client>> fetchPage({
    required int offset,
    required int limit,
  }) async {
    final data = await _supabase
        .from('clients')
        .select()
        .order('created_at', ascending: true)
        .order('id', ascending: true)
        .range(offset, offset + limit - 1);

    return (data as List)
        .map((row) => Client.fromSupabaseMap(row as Map<String, dynamic>))
        .toList();
  }

  /// Inscription idempotente via la fonction SQL
  Future<void> registerOnServer(Client client) async {
    await _supabase.rpc(
      'register_queue_client_secure',
      params: {
        'p_id': client.id,
        'p_name': client.name,
        'p_lat': client.lat,
        'p_lng': client.lng,
        'p_accuracy': client.locationAccuracy,
        'p_created_at': client.createdAt.toUtc().toIso8601String(),
      },
    );
  }

  Future<void> deleteClient(String id) async {
    await _supabase.from('clients').delete().eq('id', id);
  }

  Future<String?> callNextClient() async {
    final result = await _supabase.rpc('call_next_queue_client');
    return result?.toString();
  }

  /// Flux realtime des insertions
  RealtimeChannel subscribeToInserts(void Function(Client) onInsert) {
    return _supabase
        .channel('public:clients')
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'clients',
          callback: (payload) =>
              onInsert(Client.fromSupabaseMap(payload.newRecord)),
        )
        .subscribe();
  }
}
