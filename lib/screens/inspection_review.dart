import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class InspectionReview extends StatefulWidget {
  final String id;
  const InspectionReview({super.key, required this.id});
  @override
  State<InspectionReview> createState() => _InspectionReviewState();
}

class _InspectionReviewState extends State<InspectionReview> {
  SupabaseClient get _sb => Supabase.instance.client;
  Map<String, dynamic>? _insp;
  List<Map<String, dynamic>> _items = [];
  final _note = TextEditingController();
  DateTime? _deadline;

  @override
  void initState() { super.initState(); _load(); }

  Future<void> _load() async {
    final i = await _sb.from('inspections').select('*,projects(name),profiles!inspections_supervisor_id_fkey(full_name)').eq('id', widget.id).single();
    final it = await _sb.from('inspection_items').select().eq('inspection_id', widget.id).order('critical', ascending: false);
    if (mounted) setState(() { _insp = i; _items = List<Map<String, dynamic>>.from(it); _deadline = i['fix_deadline'] != null ? DateTime.tryParse(i['fix_deadline']) : null; });
  }

  Future<String?> _url(String? path) async =>
      path == null ? null : await _sb.storage.from('inspection-photos').createSignedUrl(path, 3600);

  Future<void> _decide(String status) async {
    if (status == 'needs_fix' && _deadline == null) {
      final d = await showDatePicker(context: context, firstDate: DateTime.now(),
          lastDate: DateTime.now().add(const Duration(days: 60)), initialDate: DateTime.now().add(const Duration(days: 2)));
      if (d == null) return;
      _deadline = d;
    }
    await _sb.from('inspections').update({
      'status': status,
      'review_note': _note.text.trim().isEmpty ? null : _note.text.trim(),
      'fix_deadline': status == 'needs_fix' ? _deadline!.toIso8601String().substring(0, 10) : null,
      'reviewed_by': _sb.auth.currentUser!.id,
      'reviewed_at': DateTime.now().toIso8601String(),
    }).eq('id', widget.id);
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final i = _insp;
    if (i == null) return const Scaffold(body: Center(child: CircularProgressIndicator()));
    return Scaffold(
      appBar: AppBar(title: Text(i['location_label'] ?? '')),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        Text('${i['projects']?['name']} • المشرف: ${i['profiles']?['full_name'] ?? ''}'),
        if ((i['notes'] ?? '').toString().isNotEmpty) Padding(padding: const EdgeInsets.only(top: 8), child: Text('ملاحظات: ${i['notes']}')),
        const SizedBox(height: 12),
        for (final it in _items)
          Card(
            color: it['status'] == 'defect' ? Colors.red.shade50 : null,
            child: Padding(padding: const EdgeInsets.all(12), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Icon(it['status'] == 'defect' ? Icons.warning : Icons.check_circle, color: it['status'] == 'defect' ? Colors.red : Colors.green),
                const SizedBox(width: 8),
                Expanded(child: Text(it['title'], style: const TextStyle(fontWeight: FontWeight.bold))),
              ]),
              if ((it['note'] ?? '').toString().isNotEmpty) Text('العيب: ${it['note']}', style: const TextStyle(color: Colors.red)),
              if (it['captured_at'] != null) Text('صُوّرت: ${it['captured_at'].toString().substring(0, 16).replaceFirst('T', ' ')}', style: const TextStyle(fontSize: 12)),
              FutureBuilder<String?>(
                future: _url(it['photo_path']),
                builder: (c, s) => s.data == null ? const SizedBox() : Padding(padding: const EdgeInsets.only(top: 8),
                    child: GestureDetector(
                      onTap: () => showDialog(context: context, builder: (_) => Dialog(child: InteractiveViewer(child: Image.network(s.data!)))),
                      child: ClipRRect(borderRadius: BorderRadius.circular(8), child: Image.network(s.data!, height: 180, width: double.infinity, fit: BoxFit.cover)))),
              ),
            ])),
          ),
        if (i['status'] == 'submitted') ...[
          TextField(controller: _note, maxLines: 2, decoration: const InputDecoration(labelText: 'ملاحظة المهندس')),
          const SizedBox(height: 12),
          FilledButton.icon(onPressed: () => _decide('approved'), icon: const Icon(Icons.verified), label: const Text('اعتماد — يمكن الصب')),
          const SizedBox(height: 8),
          OutlinedButton.icon(onPressed: () => _decide('needs_fix'), icon: const Icon(Icons.build, color: Colors.red), label: const Text('طلب تعديل مع مهلة')),
        ],
        const SizedBox(height: 32),
      ]),
    );
  }
}
