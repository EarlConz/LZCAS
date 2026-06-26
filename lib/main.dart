import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart'
    hide AuthState; // Our AuthState is in auth/auth.dart
import 'theme.dart';
import 'data/supabase_config.dart';
import 'db/db.dart';
import 'auth/auth.dart';
import 'router/app_router.dart';
import 'router/route_guard.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // ── Initialize Supabase (mandatory for cloud mode) ─────────────────
  final supabaseEnabled = await initSupabase();
  if (!supabaseEnabled) {
    throw Exception(
      'Supabase is not configured. '
      'Set SUPABASE_URL and SUPABASE_ANON_KEY environment variables '
      'or configure assets/supabase_config.json.',
    );
  }

  final supabase = Supabase.instance.client;

  // ── Initialize cloud repository ────────────────────────────────────
  setRepository(SupabaseRepository(supabase: supabase));

  // ── Initialize AuthState with Supabase ─────────────────────────────
  final authState = AuthState(supabase: supabase);

  // Attempt to restore a previous session from Supabase Auth persistence.
  await authState.tryRestoreSession();

  runApp(
    ChangeNotifierProvider<AuthState>.value(
      value: authState,
      child: const LzcasApp(),
    ),
  );
}

/// Root application widget with Provider-based auth state management,
/// role-based routing, and theme support.
class LzcasApp extends StatefulWidget {
  const LzcasApp({super.key});

  @override
  State<LzcasApp> createState() => _LzcasAppState();
}

class _LzcasAppState extends State<LzcasApp> {
  ThemeMode _mode = ThemeMode.light;

  void toggleThemeMode(bool dark) {
    setState(() {
      _mode = dark ? ThemeMode.dark : ThemeMode.light;
    });
  }

  @override
  Widget build(BuildContext context) {
    // Read auth state to determine the initial route.
    final auth = context.watch<AuthState>();

    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'LZCAS',
      theme: stockpileTheme,
      darkTheme: stockpileDarkTheme,
      themeMode: _mode,
      // Use onGenerateRoute for centralized, role-aware routing.
      onGenerateRoute: appRouter,
      // Initial route depends on authentication status.
      initialRoute: auth.isAuthenticated && auth.userRole != null
          ? AppRoutes.defaultForRole(auth.userRole!)
          : AppRoutes.login,
    );
  }
}
