import 'dart:async';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'inspection_review.dart';
import 'supervisor_home.dart' show statusAr, statusColor;

class EngineerHome extends StatefulWidget {
  final String name;
  const EngineerHome({super.key, required this.name});
  @override
  State<EngineerHome> createState() => _EngineerHomeState();
}

class _EngineerHomeState extends State<EngineerHome> {
  SupabaseClient get _sb => Supabase.instance.client;
  List<Map<String, dynamic>> _list = [];
  String _filter = 'submitted';
  StreamSubscription? _notifSub;

  @override
  void initState() {
    super.initState();
    _load();
    // تنبيه فوري عند وصول تقرير/عيب جديد (Realtime)
    _notifSub = _sb.from('notifications').stream(primaryKey: ['id']).eq('user_id', _sb.auth.currentUser!.id).listen((rows) {
      final fresh = rows.where((r) => r['read'] == false).toList();
      if (fresh.isNotEmpty && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            duration: const Duration(seconds: 6), backgroundColor: Colors.red.shade800,
            content: Text(fresh.last['message'] ?? 'تنبيه جديد')));
        _sb.from('notifications').update({'read': true}).eq('user_id', _sb.auth.currentUser!.id).eq('read', false);
        _load();
      }
    });
  }

  @override
  void dispose() { _notifSub?.cancel(); super.dispose(); }

  Future<void> _load() async {
    final r = await _sb.from('inspections')
        .select('id,location_label,status,has_defects,fix_deadline,submitted_at,projects(name),profiles!inspections_supervisor_id_fkey(full_name)')
        .eq('status', _filter).order('created_at', ascending: false).limit(100);
    if (mounted) setState(() => _list = List<Map<String, dynamic>>.from(r));
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: Text('م. ${widget.name}'), actions: [
          IconButton(onPressed: _load, icon: const Icon(Icons.refresh)),
          IconButton(onPressed: () => _sb.auth.signOut(), icon: const Icon(Icons.logout)),
        ]),
        body: Column(children: [
          Padding(padding: const EdgeInsets.all(12), child: SegmentedButton<String>(
            segments: const [
              ButtonSegment(value: 'submitted', label: Text('بانتظار المراجعة')),
              ButtonSegment(value: 'needs_fix', label: Text('تعديل')),
              ButtonSegment(value: 'approved', label: Text('معتمد')),
            ],
            selected: {_filter},
            onSelectionChanged: (v) { setState(() => _filter = v.first); _load(); },
          )),
          Expanded(child: RefreshIndicator(onRefresh: _load, child: ListView(children: [
            if (_list.isEmpty) const Padding(padding: EdgeInsets.all(40), child: Center(child: Text('لا توجد تقارير'))),
            for (final r in _list)
              Card(margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6), child: ListTile(
                leading: Icon(r['has_defects'] == true ? Icons.warning_amber : Icons.fact_check,
                    color: r['has_defects'] == true ? Colors.red : Colors.green, size: 32),
                title: Text(r['location_label'] ?? '', style: const TextStyle(fontWeight: FontWeight.bold)),
                subtitle: Text('${r['projects']?['name'] ?? ''} • ${r['profiles']?['full_name'] ?? ''}'),
                trailing: Chip(label: Text(statusAr[r['status']] ?? '', style: const TextStyle(color: Colors.white)),
                    backgroundColor: statusColor[r['status']]),
                onTap: () async {
                  await Navigator.push(context, MaterialPageRoute(builder: (_) => InspectionReview(id: r['id'])));
                  _load();
                },
              )),
          ]))),
        ]),
      );
}
