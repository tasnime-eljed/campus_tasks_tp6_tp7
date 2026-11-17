import 'sync_status.dart';

class Client {
  final String id;
  final String name;
  final String? userId;
  final double? lat;
  final double? lng;
  final double? locationAccuracy;
  final DateTime createdAt;
  final SyncStatus syncStatus;

  const Client({
    required this.id,
    required this.name,
    this.userId,
    this.lat,
    this.lng,
    this.locationAccuracy,
    required this.createdAt,
    this.syncStatus = SyncStatus.synced,
  });

  bool get hasLocation => lat != null && lng != null;

  String get locationText {
    if (!hasLocation) return 'Location not captured';
    return '${lat!.toStringAsFixed(4)}, ${lng!.toStringAsFixed(4)}';
  }

  /// Données métier uniquement (jamais de sync_status)
  Map<String, dynamic> toSupabaseMap() => {
    'id': id,
    'name': name,
    'user_id': userId,
    'lat': lat,
    'lng': lng,
    'location_accuracy_m': locationAccuracy,
    'created_at': createdAt.toUtc().toIso8601String(),
  };

  /// Données locales (avec sync_status)
  Map<String, dynamic> toLocalMap() => {
    'id': id,
    'name': name,
    'user_id': userId,
    'lat': lat,
    'lng': lng,
    'location_accuracy_m': locationAccuracy,
    'created_at': createdAt.toUtc().toIso8601String(),
    'sync_status': syncStatus.name,
  };

  factory Client.fromSupabaseMap(Map<String, dynamic> map) => Client(
    id: map['id'].toString(),
    name: map['name'] as String,
    userId: map['user_id'] as String?,
    lat: (map['lat'] as num?)?.toDouble(),
    lng: (map['lng'] as num?)?.toDouble(),
    locationAccuracy: (map['location_accuracy_m'] as num?)?.toDouble(),
    createdAt: DateTime.parse(map['created_at'] as String),
    syncStatus: SyncStatus.synced,
  );

  factory Client.fromLocalMap(Map<String, dynamic> map) => Client(
    id: map['id'] as String,
    name: map['name'] as String,
    userId: map['user_id'] as String?,
    lat: (map['lat'] as num?)?.toDouble(),
    lng: (map['lng'] as num?)?.toDouble(),
    locationAccuracy: (map['location_accuracy_m'] as num?)?.toDouble(),
    createdAt: DateTime.parse(map['created_at'] as String),
    syncStatus: SyncStatus.values.firstWhere(
      (s) => s.name == map['sync_status'],
      orElse: () => SyncStatus.pending,
    ),
  );
}
