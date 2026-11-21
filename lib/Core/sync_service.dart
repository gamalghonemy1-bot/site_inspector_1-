import 'dart:async';
import 'dart:io';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'local_db.dart';

/// مزامنة تلقائية: ترفع الصور ثم التقرير ثم تعتمده (status=submitted) بترتيب آمن وقابل للإعادة.
class SyncService {
  static final instance = SyncService._();
  SyncService._();
  final pendingCount = ValueNotifier<int>(0);
  bool _running = false;
  StreamSubscription? _sub;
  SupabaseClient get _sb => Supabase.instance.client;

  void start() {
    _sub ??= Connectivity().onConnectivityChanged.listen((r) {
      if (!r.contains(ConnectivityResult.none)) syncNow();
    });
    syncNow();
  }

  Future<void> syncNow() async {
    if (_running || _sb.auth.currentUser == null) return;
    _running = true;
    try {
      for (final p in await LocalDb.pending()) {
        try {
          await _push(p);
          await LocalDb.remove(p['id']);
        } catch (e) {
          debugPrint('sync failed for ${p['id']}: $e');
          if (e is PostgrestException && e.message.contains('GEOFENCE')) {
            // مرفوض نهائياً من السيرفر: لا نعيد المحاولة للأبد
            await LocalDb.remove(p['id']);
          }
        }
      }
    } finally {
      _running = false;
      pendingCount.value = await LocalDb.pendingCount();
    }
  }

  Future<void> _push(Map<String, dynamic> p) async {
    final id = p['id'] as String;
    final existing = await _sb.from('inspections').select('status').eq('id', id).maybeSingle();
    if (existing != null && existing['status'] != 'draft') return; // تم إرساله سابقاً

    final items = (p['items'] as List).cast<Map<String, dynamic>>();
    // 1) الصور
    for (final it in items) {
      final local = it['photo_local'] as String?;
      if (local != null && it['photo_path'] == null) {
        final path = '${p['project_id']}/$id/${it['item_key']}.jpg';
        await _sb.storage.from('inspection-photos').upload(path, File(local),
            fileOptions: const FileOptions(upsert: true, contentType: 'image/jpeg'));
        it['photo_path'] = path;
      }
    }
    // 2) التقرير كمسودة
    await _sb.from('inspections').upsert({
      'id': id,
      'project_id': p['project_id'],
      'supervisor_id': p['supervisor_id'],
      'location_label': p['location_label'],
      'notes': p['notes'],
      'fix_deadline': p['fix_deadline'],
      'has_defects': p['has_defects'],
      'expected_items': items.length,
      'submit_lat': p['submit_lat'],
      'submit_lng': p['submit_lng'],
      'status': 'draft',
    });
    // 3) البنود
    await _sb.from('inspection_items').upsert([
      for (final it in items)
        {
          'id': it['id'],
          'inspection_id': id,
          'item_key': it['item_key'],
          'title': it['title'],
          'critical': it['critical'],
          'status': it['status'],
          'note': it['note'],
          'photo_path': it['photo_path'],
          'captured_at': it['captured_at'],
          'lat': it['lat'],
          'lng': it['lng'],
        }
    ]);
    // 4) الاعتماد: السيرفر يتحقق من النطاق الجغرافي ومن اكتمال البنود
    await _sb.from('inspections').update({'status': 'submitted', 'submitted_at': DateTime.now().toIso8601String()}).eq('id', id);
  }
}
