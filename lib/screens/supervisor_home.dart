import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../core/geofence_service.dart';
import '../core/local_db.dart';
import '../core/sync_service.dart';
import '../models/project.dart';
import 'inspection_form.dart';

const statusAr = {
  'draft': 'مسودة', 'submitted': 'بانتظار المهندس', 'approved': 'معتمد',
  'needs_fix': 'مطلوب تعديل', 'pending_sync': 'بانتظار المزامنة',
};
const statusColor = {
  'draft': Colors.grey, 'submitted': Colors.orange, 'approved': Colors.green,
  'needs_fix': Colors.red, 'pending_sync': Colors.blueGrey,
};

class SupervisorHome extends StatefulWidget {
  final String name;
  const SupervisorHome({super.key, required this.name});
  @override
  State<SupervisorHome> createState() => _SupervisorHomeState();
}

class _SupervisorHomeState extends State<SupervisorHome> {
  SupabaseClient get _sb => Supabase.instance.client;
  List<Project> _projects = [];
  List<Map<String, dynamic>> _reports = [];
  bool _checking = false;

  @override
  void initState() {
    super.initState();
    _load();
    SyncService.instance.pendingCount.addListener(_load);
  }

  @override
  void dispose() {
    SyncService.instance.pendingCount.removeListener(_load);
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final pr = await _sb.from('projects').select();
      await LocalDb.putCache('projects', pr);
      final rp = await _sb.from('inspections').select('id,location_label,status,fix_deadline,review_note,created_at,projects(name)')
          .eq('supervisor_id', _sb.auth.currentUser!.id).order('created_at', ascending: false).limit(50);
      await LocalDb.putCache('reports', rp);
    } catch (_) {/* offline: نستخدم الكاش */}
    final pr = (await LocalDb.getCache('projects') as List? ?? []).cast<Map<String, dynamic>>();
    final rp = (await LocalDb.getCache('reports') as List? ?? []).cast<Map<String, dynamic>>();
    final pending = await LocalDb.pending();
    if (!mounted) return;
    setState(() {
      _projects = pr.map(Project.fromJson).toList();
      _reports = [
        for (final p in pending)
          {'location_label': p['location_label'], 'status': 'pending_sync', 'projects': {'name': p['project_name']}},
        ...rp
      ];
    });
  }

  Future<void> _open(Project p) async {
    setState(() => _checking = true);
    try {
      final r = await GeofenceService.check(p);
      if (!mounted) return;
      if (!r.allowed) {
        await showDialog(context: context, builder: (_) => AlertDialog(
          icon: const Icon(Icons.location_off, color: Colors.red, size: 48),
          title: const Text('لا يمكن فتح الاستمارة'), content: Text(r.message),
          actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('حسناً'))]));
        return;
      }
      await Navigator.push(context, MaterialPageRoute(builder: (_) => InspectionForm(project: p)));
      _load();
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('تعذر تحديد الموقع: $e')));
    } finally {
      if (mounted) setState(() => _checking = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(
          title: Text('مرحباً ${widget.name}'),
          actions: [
            ValueListenableBuilder<int>(
              valueListenable: SyncService.instance.pendingCount,
              builder: (_, n, __) => IconButton(
                  onPressed: () async { await SyncService.instance.syncNow(); _load(); },
                  icon: Badge(isLabelVisible: n > 0, label: Text('$n'), child: const Icon(Icons.sync))),
            ),
            IconButton(onPressed: () => _sb.auth.signOut(), icon: const Icon(Icons.logout)),
          ],
        ),
        body: Stack(children: [
          RefreshIndicator(
            onRefresh: _load,
            child: ListView(padding: const EdgeInsets.all(16), children: [
              const Text('مشاريعي — اضغط لبدء فحص جديد', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              for (final p in _projects)
                Card(child: ListTile(
                  leading: const Icon(Icons.location_on, color: Color(0xFF0D47A1), size: 32),
                  title: Text(p.name, style: const TextStyle(fontWeight: FontWeight.bold)),
                  subtitle: Text('نطاق ${p.radiusM.round()} م'),
                  trailing: const Icon(Icons.chevron_left),
                  onTap: _checking ? null : () => _open(p),
                )),
              const Divider(height: 32),
              const Text('تقاريري', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              for (final r in _reports)
                Card(child: ListTile(
                  title: Text(r['location_label'] ?? ''),
                  subtitle: Text([
                    r['projects']?['name'] ?? '',
                    if (r['status'] == 'needs_fix' && r['fix_deadline'] != null) 'المهلة: ${r['fix_deadline']}',
                    if (r['review_note'] != null) '${r['review_note']}',
                  ].where((s) => s.toString().isNotEmpty).join(' • ')),
                  trailing: Chip(
                    label: Text(statusAr[r['status']] ?? '', style: const TextStyle(color: Colors.white)),
                    backgroundColor: statusColor[r['status']] ?? Colors.grey),
                )),
            ]),
          ),
          if (_checking) const Center(child: Card(child: Padding(padding: EdgeInsets.all(24), child: Column(mainAxisSize: MainAxisSize.min, children: [
            CircularProgressIndicator(), SizedBox(height: 12), Text('جارٍ تحديد موقعك...')])))),
        ]),
      );
}
