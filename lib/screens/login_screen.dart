import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});
  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _email = TextEditingController(), _pass = TextEditingController();
  bool _busy = false;
  String? _err;

  Future<void> _login() async {
    setState(() { _busy = true; _err = null; });
    try {
      await Supabase.instance.client.auth.signInWithPassword(email: _email.text.trim(), password: _pass.text);
    } on AuthException catch (e) {
      setState(() => _err = 'بيانات الدخول غير صحيحة (${e.message})');
    } catch (_) {
      setState(() => _err = 'تعذر الاتصال. تسجيل الدخول الأول يحتاج إنترنت.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        body: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: Column(children: [
                const Icon(Icons.electrical_services, size: 80, color: Color(0xFF0D47A1)),
                const SizedBox(height: 8),
                const Text('متابعة مشرفي الكهرباء', style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
                const SizedBox(height: 32),
                TextField(controller: _email, keyboardType: TextInputType.emailAddress, decoration: const InputDecoration(labelText: 'البريد الإلكتروني')),
                const SizedBox(height: 16),
                TextField(controller: _pass, obscureText: true, decoration: const InputDecoration(labelText: 'كلمة المرور')),
                if (_err != null) Padding(padding: const EdgeInsets.only(top: 12), child: Text(_err!, style: const TextStyle(color: Colors.red))),
                const SizedBox(height: 24),
                FilledButton(onPressed: _busy ? null : _login, child: _busy ? const CircularProgressIndicator() : const Text('دخول')),
              ]),
            ),
          ),
        ),
      );
}
