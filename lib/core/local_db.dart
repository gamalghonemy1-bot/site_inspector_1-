import 'dart:convert';
import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

/// تخزين محلي: صندوق صادر (outbox) للتقارير غير المرسلة + كاش بسيط.
class LocalDb {
  static Database? _db;
  static Future<Database> get db async => _db ??= await openDatabase(
        p.join(await getDatabasesPath(), 'site_inspector.db'),
        version: 1,
        onCreate: (d, _) async {
          await d.execute('CREATE TABLE outbox(id TEXT PRIMARY KEY, payload TEXT NOT NULL, created_at TEXT NOT NULL)');
          await d.execute('CREATE TABLE cache(k TEXT PRIMARY KEY, v TEXT NOT NULL)');
        },
      );

  static Future<void> enqueue(Map<String, dynamic> payload) async => (await db).insert(
      'outbox', {'id': payload['id'], 'payload': jsonEncode(payload), 'created_at': DateTime.now().toIso8601String()},
      conflictAlgorithm: ConflictAlgorithm.replace);

  static Future<List<Map<String, dynamic>>> pending() async =>
      (await (await db).query('outbox', orderBy: 'created_at')).map((r) => jsonDecode(r['payload'] as String) as Map<String, dynamic>).toList();

  static Future<int> pendingCount() async =>
      Sqflite.firstIntValue(await (await db).rawQuery('SELECT COUNT(*) FROM outbox')) ?? 0;

  static Future<void> remove(String id) async => (await db).delete('outbox', where: 'id=?', whereArgs: [id]);

  static Future<void> putCache(String k, Object v) async =>
      (await db).insert('cache', {'k': k, 'v': jsonEncode(v)}, conflictAlgorithm: ConflictAlgorithm.replace);

  static Future<dynamic> getCache(String k) async {
    final r = await (await db).query('cache', where: 'k=?', whereArgs: [k]);
    return r.isEmpty ? null : jsonDecode(r.first['v'] as String);
  }
}
