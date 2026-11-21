import 'package:flutter/material.dart';
import 'package:geocoding/geocoding.dart';
import 'package:geolocator/geolocator.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/project.dart';

/// إنشاء/تعديل مشروع: الموقع يتحدد إما بالبحث باسم المشروع/عنوانه، أو بموقعك الحالي (وأنت واقف في الموقع).
class ProjectEdit extends StatefulWidget {
  final Project? project;
  const ProjectEdit({super.key, this.project});
  @override
  State<ProjectEdit> createState() => _ProjectEditState();
}

class _ProjectEditState extends State<ProjectEdit> {
  SupabaseClient get _sb => Supabase.instance.client;
  final _name = TextEditingController();
  final _email = TextEditingController();
  double? _lat, _lng;
  double _radius = 150;
  bool _busy = false;
  List<Map<String, dynamic>> _members = [];
  Project? _p;

  @override
  void initState() {
    super.initState();
    _p = widget.project;
    if (_p != null) {
      _name.text = _p!.name; _lat = _p!.lat; _lng = _p!.lng; _radius = _p!.radiusM.clamp(30, 1000).toDouble();
      _loadMembers();
    }
  }

  void _msg(String m) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));

  Future<void> _loadMembers() async {
    try {
      final r = await _sb.rpc('list_members', params: {'p_project': _p!.id});
      if (mounted) setState(() => _members = List<Map<String, dynamic>>.from(r));
    } catch (_) {}
  }

  /// البحث باسم المشروع أو عنوانه (يحتاج إنترنت)
  Future<void> _searchByName() async {
    final q = _name.text.trim();
    if (q.isEmpty) { _msg('اكتب اسم المشروع أو عنوانه أولاً'); return; }
    setState(() => _busy = true);
    try {
      final locs = (await locationFromAddress(q)).take(5).toList();
      if (locs.isEmpty) { _msg('لم أجد الموقع بهذا الاسم. جرّب إضافة المدينة، أو استخدم موقعك الحالي.'); return; }
      final choices = <Map<String, dynamic>>[];
      for (final l in locs) {
        String addr = '';
        try {
          final pm = (await placemarkFromCoordinates(l.latitude, l.longitude)).first;
          addr = [pm.street, pm.locality, pm.administrativeArea].where((s) => (s ?? '').isNotEmpty).join('، ');
        } catch (_) {}
        choices.add({'lat': l.latitude, 'lng': l.longitude, 'addr': addr});
      }
      if (!mounted) return;
      final c = await showDialog<Map<String, dynamic>>(context: context, builder: (_) => SimpleDialog(
        title: const Text('اختر الموقع الصحيح'),
        children: [for (final c in choices) SimpleDialogOption(
          onPressed: () => Navigator.pop(context, c),
          child: Text('${c['addr'] == '' ? 'موقع' : c['addr']}\n(${(c['lat'] as double).toStringAsFixed(5)}, ${(c['lng'] as double).toStringAsFixed(5)})'))],
      ));
      if (c != null) setState(() { _lat = c['lat']; _lng = c['lng']; });
    } catch (e) {
      _msg('تعذر البحث (تحقق من الإنترنت). استخدم موقعك الحالي.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// تحديد الموقع من الـ GPS وأنت واقف في المشروع (الأدق)
  Future<void> _useCurrent() async {
    setState(() => _busy = true);
    try {
      var perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied) perm = await Geolocator.requestPermission();
      if (perm == LocationPermission.denied || perm == LocationPermission.deniedForever) { _msg('اسمح للتطبيق باستخدام الموقع'); return; }
      final pos = await Geolocator.getCurrentPosition(desiredAccuracy: LocationAccuracy.best, timeLimit: const Duration(seconds: 20));
      setState(() { _lat = pos.latitude; _lng = pos.longitude; });
      _msg('تم أخذ موقعك الحالي (دقة ${pos.accuracy.round()} م)');
    } catch (_) {
      _msg('تعذر تحديد الموقع. فعّل الـ GPS وأعد المحاولة.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _save() async {
    if (_name.text.trim().isEmpty || _lat == null || _lng == null) { _msg('اكتب الاسم وحدد الموقع أولاً'); return; }
    setState(() => _busy = true);
    try {
      if (_p == null) {
        final id = await _sb.rpc('create_project', params: {'p_name': _name.text.trim(), 'p_lat': _lat, 'p_lng': _lng, 'p_radius': _radius});
        _p = Project(id: id as String, name: _name.text.trim(), lat: _lat!, lng: _lng!, radiusM: _radius);
        _msg('تم إنشاء المشروع. أضف المشرفين الآن.');
        await _loadMembers();
      } else {
        await _sb.rpc('update_project', params: {'p_project': _p!.id, 'p_name': _name.text.trim(), 'p_lat': _lat, 'p_lng': _lng, 'p_radius': _radius});
        _msg('تم حفظ التعديلات');
      }
      setState(() {});
    } on PostgrestException catch (e) {
      _msg(e.message);
    } catch (_) {
      _msg('تعذر الحفظ. تحقق من الإنترنت.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _addMember() async {
    if (_email.text.trim().isEmpty) return;
    try {
      final nm = await _sb.rpc('add_member', params: {'p_project': _p!.id, 'p_email': _email.text.trim()});
      _msg('تمت إضافة ${nm ?? ''}');
      _email.clear();
      _loadMembers();
    } on PostgrestException catch (e) {
      _msg(e.message);
    }
  }

  Future<void> _removeMember(String uid) async {
    try {
      await _sb.rpc('remove_member', params: {'p_project': _p!.id, 'p_user': uid});
      _loadMembers();
    } on PostgrestException catch (e) {
      _msg(e.message);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: Text(_p == null ? 'مشروع جديد' : 'تعديل المشروع')),
        body: ListView(padding: const EdgeInsets.all(16), children: [
          TextField(controller: _name, decoration: const InputDecoration(labelText: 'اسم المشروع / عنوانه *', helperText: 'مثال: مركز التميز للطاقة المتجددة بلبيس الشرقية')),
          const SizedBox(height: 12),
          OutlinedButton.icon(onPressed: _busy ? null : _searchByName, icon: const Icon(Icons.search), label: const Text('تحديد الموقع من الاسم')),
          const SizedBox(height: 8),
          OutlinedButton.icon(onPressed: _busy ? null : _useCurrent, icon: const Icon(Icons.my_location), label: const Text('استخدم موقعي الحالي (وأنا في المشروع)')),
          const SizedBox(height: 12),
          Card(color: _lat == null ? Colors.orange.shade50 : Colors.green.shade50, child: ListTile(
            leading: Icon(_lat == null ? Icons.location_off : Icons.location_on, color: _lat == null ? Colors.orange : Colors.green),
            title: Text(_lat == null ? 'لم يتحدد الموقع بعد' : 'الموقع: ${_lat!.toStringAsFixed(5)}, ${_lng!.toStringAsFixed(5)}'),
          )),
          const SizedBox(height: 12),
          Text('نطاق السماح: ${_radius.round()} متر', style: const TextStyle(fontWeight: FontWeight.bold)),
          Slider(value: _radius, min: 30, max: 1000, divisions: 97, label: '${_radius.round()}', onChanged: (v) => setState(() => _radius = v)),
          const SizedBox(height: 8),
          FilledButton(onPressed: _busy ? null : _save, child: _busy ? const CircularProgressIndicator() : Text(_p == null ? 'إنشاء المشروع' : 'حفظ')),
          if (_p != null) ...[
            const Divider(height: 40),
            const Text('الفريق', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            for (final m in _members)
              ListTile(
                leading: Icon(m['role'] == 'engineer' ? Icons.engineering : Icons.badge),
                title: Text(m['full_name'] ?? ''), subtitle: Text('${m['email']}'),
                trailing: m['user_id'] == _sb.auth.currentUser!.id ? null
                    : IconButton(icon: const Icon(Icons.person_remove, color: Colors.red), onPressed: () => _removeMember(m['user_id'])),
              ),
            const SizedBox(height: 8),
            Row(children: [
              Expanded(child: TextField(controller: _email, keyboardType: TextInputType.emailAddress, decoration: const InputDecoration(labelText: 'بريد مشرف لإضافته'))),
              const SizedBox(width: 8),
              IconButton.filled(onPressed: _addMember, icon: const Icon(Icons.person_add)),
            ]),
          ],
          const SizedBox(height: 40),
        ]),
      );
}
