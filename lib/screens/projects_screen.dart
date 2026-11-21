import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/project.dart';
import 'project_edit.dart';

class ProjectsScreen extends StatefulWidget {
  const ProjectsScreen({super.key});
  @override
  State<ProjectsScreen> createState() => _ProjectsScreenState();
}

class _ProjectsScreenState extends State<ProjectsScreen> {
  List<Project> _list = [];
  bool _loading = true;

  @override
  void initState() { super.initState(); _load(); }

  Future<void> _load() async {
    final r = await Supabase.instance.client.from('projects').select().order('created_at', ascending: false);
    if (mounted) setState(() { _list = (r as List).map((e) => Project.fromJson(e)).toList(); _loading = false; });
  }

  Future<void> _open(Project? p) async {
    await Navigator.push(context, MaterialPageRoute(builder: (_) => ProjectEdit(project: p)));
    _load();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('المشاريع')),
        floatingActionButton: FloatingActionButton.extended(
            onPressed: () => _open(null), icon: const Icon(Icons.add_location_alt), label: const Text('مشروع جديد')),
        body: _loading
            ? const Center(child: CircularProgressIndicator())
            : ListView(padding: const EdgeInsets.all(12), children: [
                if (_list.isEmpty) const Padding(padding: EdgeInsets.all(40), child: Center(child: Text('لا توجد مشاريع. أضف مشروعاً جديداً.'))),
                for (final p in _list)
                  Card(child: ListTile(
                    leading: const Icon(Icons.location_on, color: Color(0xFF0D47A1), size: 32),
                    title: Text(p.name, style: const TextStyle(fontWeight: FontWeight.bold)),
                    subtitle: Text('نطاق ${p.radiusM.round()} م • ${p.lat.toStringAsFixed(5)}, ${p.lng.toStringAsFixed(5)}'),
                    trailing: const Icon(Icons.edit),
                    onTap: () => _open(p),
                  )),
                const SizedBox(height: 80),
              ]),
      );
}
