import 'package:path/path.dart';
import 'package:sqflite/sqflite.dart';

import '../models/sync_status.dart';

class LocalQueueStorage {
  static Database? _database;
  final bool _inMemory;

  LocalQueueStorage({this._inMemory = false});
  Future<Database> get database async {
    if (_database != null) return _database!;
    final path = _inMemory
        ? inMemoryDatabasePath
        : join(await getDatabasesPath(), 'waiting_queue.db');
    _database = await openDatabase(
      path,
      version: 1,
      onCreate: (db, version) async {
        await db.execute('''
          CREATE TABLE clients (
            id TEXT PRIMARY KEY,
            name TEXT NOT NULL,
            lat REAL,
            lng REAL,
            location_accuracy_m REAL,
            created_at TEXT NOT NULL,
            sync_status TEXT NOT NULL
          )
        ''');
      },
    );
    return _database!;
  }

  Future<void> saveClient(Map<String, dynamic> client) async {
    final db = await database;
    await db.insert(
      'clients',
      client,
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<List<Map<String, dynamic>>> getClients() async {
    final db = await database;
    return db.query('clients', orderBy: 'created_at DESC, id DESC');
  }

  /// Pending + failed : les deux sont à renvoyer
  Future<List<Map<String, dynamic>>> getPendingClients() async {
    final db = await database;
    return db.query(
      'clients',
      where: 'sync_status = ? OR sync_status = ?',
      whereArgs: ['pending', 'failed'],
      orderBy: 'created_at ASC, id ASC',
    );
  }

  Future<void> updateSyncStatus(String id, SyncStatus status) async {
    final db = await database;
    await db.update(
      'clients',
      {'sync_status': status.name},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<void> close() async {
    final db = _database;
    if (db != null) {
      await db.close();
      _database = null;
    }
  }
}
