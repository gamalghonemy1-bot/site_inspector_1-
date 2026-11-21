import 'dart:io';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';
import '../core/geofence_service.dart';
import '../core/local_db.dart';
import '../core/sync_service.dart';
import '../models/project.dart';

class ChecklistDef {
  final String key, title;
  final bool critical; // البند الحرج يتطلب صورة حية
  const ChecklistDef(this.key, this.title, this.critical);
}

/// قائمة "تمديدات الأسقف قبل الصب" — يمكن تعديلها أو نقلها لجدول في قاعدة البيانات.
const checklist = [
  ChecklistDef('layout', 'مطابقة مسارات المواسير للمخطط المعتمد', true),
  ChecklistDef('diameter', 'أقطار المواسير مطابقة للمواصفات', true),
  ChecklistDef('fixing', 'تثبيت المواسير بالكلبسات والمسافات بينها', true),
  ChecklistDef('boxes', 'علب التوصيل والمخارج: التثبيت والارتفاع والتغطية', true),
  ChecklistDef('crossing', 'التقاطع مع حديد التسليح والمواسير الأخرى', true),
  ChecklistDef('expansion', 'وصلات التمدد عند فواصل المبنى', false),
  ChecklistDef('sealing', 'سدّ فتحات المواسير ومنع دخول الخرسانة', true),
  ChecklistDef('pull', 'وجود حبل السحب داخل المواسير', false),
  ChecklistDef('earth', 'مواسير ومسارات التأريض', false),
  ChecklistDef('clean', 'نظافة الموقع وخلوه من المخلفات', false),
];

class ItemState {
  String? status; // ok | defect
  String note = '';
  String? photoPath;
  DateTime? capturedAt;
  double? lat, lng;
}

class InspectionForm extends StatefulWidget {
  final Project project;
  const InspectionForm({super.key, required this.project});
  @override
  State<InspectionForm> createState() => _InspectionFormState();
}

class _InspectionFormState extends State<InspectionForm> {
  final _id = const Uuid().v4();
  final _location = TextEditingController();
  final _notes = TextEditingController();
  final _items = {for (final c in checklist) c.key: ItemState()};
  DateTime? _deadline;
  bool _busy = false;

  bool _done(ChecklistDef c) {
    final s = _items[c.key]!;
    if (s.status == null) return false;
    if (s.status == 'defect') return s.note.trim().isNotEmpty && s.photoPath != null;
    return !c.critical || s.photoPath != null;
  }

  bool get _hasDefects => _items.values.any((s) => s.status == 'defect');

  Future<void> _capture(ChecklistDef c) async {
    // الكاميرا فقط — لا يوجد مسار للمعرض
    final x = await ImagePicker().pickImage(source: ImageSource.camera, imageQuality: 70, maxWidth: 1600);
    if (x == null) return;
    final dir = Directory(p.join((await getApplicationDocumentsDirectory()).path, 'photos'))..createSync(recursive: true);
    final saved = await File(x.path).copy(p.join(dir.path, '${const Uuid().v4()}.jpg'));
    Position? pos;
    try { pos = await Geolocator.getCurrentPosition(desiredAccuracy: LocationAccuracy.high, timeLimit: const Duration(seconds: 8)); } catch (_) {}
    setState(() {
      final s = _items[c.key]!;
      s.photoPath = saved.path;
      s.capturedAt = DateTime.now();
      s.lat = pos?.latitude;
      s.lng = pos?.longitude;
    });
  }

  List<String> _validate() {
    final e = <String>[];
    if (_location.text.trim().isEmpty) e.add('اكتب موضع الفحص (مثال: سقف الدور الثاني - غرفة 3).');
    for (final c in checklist) {
      final s = _items[c.key]!;
      if (s.status == null) { e.add('حدد حالة: ${c.title}'); continue; }
      if (s.status == 'defect' && s.note.trim().isEmpty) e.add('اكتب وصف العيب: ${c.title}');
      if ((c.critical || s.status == 'defect') && s.photoPath == null) e.add('صوّر من الكاميرا: ${c.title}');
    }
    if (_hasDefects && _deadline == null) e.add('حدد مهلة التعديل لأن هناك عيوباً.');
    return e;
  }

  Future<void> _submit() async {
    final errors = _validate();
    if (errors.isNotEmpty) {
      await showDialog(context: context, builder: (_) => AlertDialog(
        title: const Text('التقرير غير مكتمل'),
        content: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start,
            children: [for (final x in errors) Padding(padding: const EdgeInsets.symmetric(vertical: 3), child: Text('• $x'))])),
        actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('حسناً'))]));
      return;
    }
    setState(() => _busy = true);
    try {
      // إعادة التحقق من الموقع لحظة الاعتماد
      final geo = await GeofenceService.check(widget.project);
      if (!geo.allowed) {
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(geo.message)));
        return;
      }
      final payload = {
        'id': _id,
        'project_id': widget.project.id,
        'project_name': widget.project.name,
        'supervisor_id': Supabase.instance.client.auth.currentUser!.id,
        'location_label': _location.text.trim(),
        'notes': _notes.text.trim(),
        'fix_deadline': _hasDefects ? _deadline!.toIso8601String().substring(0, 10) : null,
        'has_defects': _hasDefects,
        'submit_lat': geo.position!.latitude,
        'submit_lng': geo.position!.longitude,
        'items': [
          for (final c in checklist)
            {
              'id': const Uuid().v4(),
              'item_key': c.key,
              'title': c.title,
              'critical': c.critical,
              'status': _items[c.key]!.status,
              'note': _items[c.key]!.note.trim(),
              'photo_local': _items[c.key]!.photoPath,
              'photo_path': null,
              'captured_at': _items[c.key]!.capturedAt?.toIso8601String(),
              'lat': _items[c.key]!.lat,
              'lng': _items[c.key]!.lng,
            }
        ],
      };
      await LocalDb.enqueue(payload); // يُحفظ محلياً دائماً (يعمل بدون إنترنت)
      SyncService.instance.syncNow();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('تم حفظ التقرير وسيُرسل تلقائياً عند توفر الإنترنت')));
        Navigator.pop(context);
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final done = checklist.where(_done).length;
    return Scaffold(
      appBar: AppBar(title: Text(widget.project.name),
          bottom: PreferredSize(preferredSize: const Size.fromHeight(6),
              child: LinearProgressIndicator(value: done / checklist.length, minHeight: 6, color: Colors.greenAccent))),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        Text('اكتمل $done من ${checklist.length}', style: const TextStyle(fontWeight: FontWeight.bold)),
        const SizedBox(height: 12),
        TextField(controller: _location, decoration: const InputDecoration(labelText: 'موضع الفحص *')),
        const SizedBox(height: 12),
        for (final c in checklist) _itemCard(c),
        if (_hasDefects)
          Card(color: Colors.red.shade50, child: ListTile(
            leading: const Icon(Icons.event, color: Colors.red),
            title: Text(_deadline == null ? 'حدد مهلة التعديل *' : 'مهلة التعديل: ${_deadline!.toString().substring(0, 10)}'),
            onTap: () async {
              final d = await showDatePicker(context: context, firstDate: DateTime.now(),
                  lastDate: DateTime.now().add(const Duration(days: 60)), initialDate: DateTime.now().add(const Duration(days: 1)));
              if (d != null) setState(() => _deadline = d);
            },
          )),
        const SizedBox(height: 12),
        TextField(controller: _notes, maxLines: 3, decoration: const InputDecoration(labelText: 'ملاحظات عامة')),
        const SizedBox(height: 20),
        FilledButton(onPressed: _busy ? null : _submit, child: _busy ? const CircularProgressIndicator() : const Text('اعتماد وإرسال التقرير')),
        const SizedBox(height: 32),
      ]),
    );
  }

  Widget _itemCard(ChecklistDef c) {
    final s = _items[c.key]!;
    final ok = _done(c);
    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12),
          side: BorderSide(color: ok ? Colors.green : Colors.grey.shade400, width: 2)),
      child: Padding(padding: const EdgeInsets.all(12), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(child: Text(c.title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold))),
          if (c.critical) const Chip(label: Text('حرج'), backgroundColor: Color(0xFFFFE0B2)),
          if (ok) const Icon(Icons.check_circle, color: Colors.green),
        ]),
        const SizedBox(height: 8),
        SegmentedButton<String>(
          emptySelectionAllowed: true,
          segments: const [
            ButtonSegment(value: 'ok', label: Text('مطابق'), icon: Icon(Icons.check)),
            ButtonSegment(value: 'defect', label: Text('عيب'), icon: Icon(Icons.warning)),
          ],
          selected: {if (s.status != null) s.status!},
          onSelectionChanged: (v) => setState(() => s.status = v.isEmpty ? null : v.first),
        ),
        if (s.status == 'defect')
          Padding(padding: const EdgeInsets.only(top: 8), child: TextField(
              decoration: const InputDecoration(labelText: 'وصف العيب *'), onChanged: (v) => setState(() => s.note = v))),
        const SizedBox(height: 8),
        Row(children: [
          Expanded(child: OutlinedButton.icon(
              onPressed: () => _capture(c), icon: const Icon(Icons.photo_camera),
              label: Text(s.photoPath == null ? (c.critical || s.status == 'defect' ? 'تصوير (إجباري)' : 'تصوير') : 'إعادة التصوير'))),
          if (s.photoPath != null) Padding(padding: const EdgeInsets.only(right: 8),
              child: ClipRRect(borderRadius: BorderRadius.circular(8), child: Image.file(File(s.photoPath!), width: 56, height: 56, fit: BoxFit.cover))),
        ]),
      ])),
    );
  }
}
