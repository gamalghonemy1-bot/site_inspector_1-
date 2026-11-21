import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'core/env.dart';
import 'core/sync_service.dart';
import 'screens/login_screen.dart';
import 'screens/supervisor_home.dart';
import 'screens/engineer_home.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Supabase.initialize(url: Env.url, anonKey: Env.anonKey);
  runApp(const App());
}

class App extends StatelessWidget {
  const App({super.key});
  @override
  Widget build(BuildContext context) {
    // ألوان عالية التباين + خط كبير للاستخدام تحت الشمس
    final scheme = ColorScheme.fromSeed(seedColor: const Color(0xFF0D47A1), brightness: Brightness.light);
    return MaterialApp(
      title: 'متابعة المشرفين',
      debugShowCheckedModeBanner: false,
      locale: const Locale('ar'),
      supportedLocales: const [Locale('ar')],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: scheme,
        scaffoldBackgroundColor: Colors.white,
        textTheme: Typography.blackMountainView.apply(fontSizeFactor: 1.15, bodyColor: Colors.black, displayColor: Colors.black),
        appBarTheme: const AppBarTheme(backgroundColor: Color(0xFF0D47A1), foregroundColor: Colors.white),
        filledButtonTheme: FilledButtonThemeData(
            style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(56), textStyle: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold))),
        outlinedButtonTheme: OutlinedButtonThemeData(
            style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(52), side: const BorderSide(width: 2))),
        inputDecorationTheme: const InputDecorationTheme(border: OutlineInputBorder(borderSide: BorderSide(width: 2))),
      ),
      builder: (c, child) => Directionality(textDirection: TextDirection.rtl, child: child!),
      home: const AuthGate(),
    );
  }
}

class AuthGate extends StatelessWidget {
  const AuthGate({super.key});
  @override
  Widget build(BuildContext context) {
    final sb = Supabase.instance.client;
    return StreamBuilder<AuthState>(
      stream: sb.auth.onAuthStateChange,
      builder: (context, _) {
        final user = sb.auth.currentUser;
        if (user == null) return const LoginScreen();
        return FutureBuilder<Map<String, dynamic>?>(
          future: sb.from('profiles').select().eq('id', user.id).maybeSingle(),
          builder: (c, snap) {
            if (snap.connectionState != ConnectionState.done) {
              return const Scaffold(body: Center(child: CircularProgressIndicator()));
            }
            final role = snap.data?['role'];
            SyncService.instance.start();
            if (role == 'engineer') return EngineerHome(name: snap.data!['full_name'] ?? '');
            return SupervisorHome(name: snap.data?['full_name'] ?? '');
          },
        );
      },
    );
  }
}
