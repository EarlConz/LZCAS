import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'theme.dart';
import 'data/db_init.dart';
import 'data/supabase_config.dart';
import 'package:lzcas/db/db.dart';
import 'auth/auth.dart';
import 'router/app_router.dart';
import 'router/route_guard.dart';

late final DbRepository repository;

/// Global API client instance. Used by [AuthState] and can be consumed
/// via Provider or directly from API service classes.
late final ApiClient apiClient;

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // ── Initialize Supabase (optional) ──────────────────────────────────
  final supabaseEnabled = await initSupabase();
  if (supabaseEnabled) {
    // ignore: avoid_print
    print('Supabase initialized');
  } else {
    // ignore: avoid_print
    print('Supabase not configured; running in local SQLite mode');
  }

  // ── Initialize local SQLite database ────────────────────────────────
  final db = await initDb();
  repository = DbRepository(db);

  // Run one-off migrations at startup. Both are idempotent.
  try {
    await repository.ensureVerifiedResellerConsistency();
  } catch (e) {
    // ignore: avoid_print
    print('ensureVerifiedResellerConsistency failed: $e');
  }
  try {
    await repository.ensureReferrerIdBackfill();
  } catch (e) {
    // ignore: avoid_print
    print('ensureReferrerIdBackfill failed: $e');
  }

  // ── Initialize API client for backend communication ────────────────
  // Update the baseUrl to your backend server address.
  // In development, this might point to a local server or staging URL.
  apiClient = ApiClient(
    baseUrl: SupabaseConfig.isConfigured
        ? SupabaseConfig.url
        : 'http://localhost:8080',
  );

  // Create the AuthState with the API client and CSRF interceptor.
  final authState = AuthState(
    apiClient: apiClient,
    csrfInterceptor: apiClient.csrfInterceptor,
  );

  // Wire the session-expiry callback so 419/403 errors force-logout.
  // We do this AFTER AuthState is created because the callback captures it.
  apiClient.csrfInterceptor.setOnSessionExpired(() async {
    await authState.forceLogout();
  });

  // Attempt to restore a previous session from secure storage.
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
