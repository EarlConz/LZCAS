import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart'
    hide AuthState; // Our AuthState is in auth/auth.dart
import 'package:bot_toast/bot_toast.dart';
import 'theme.dart';
import 'config/build_flavor.dart';
import 'widgets/staging_badge.dart';
import 'data/supabase_config.dart';
import 'db/db.dart';
import 'auth/auth.dart';
import 'router/app_router.dart';
import 'router/route_guard.dart';
import 'services/notification_service.dart';
import 'services/config_service.dart';
import 'services/updater_service.dart';

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

  // ── Initialize config service ──────────────────────────────────────
  final configService = ConfigService();
  await configService.load();

  // ── Initialize notification service ─────────────────────────────────
  final notificationService = NotificationService();
  await notificationService.init(config: configService);

  // ── Initialize updater service ──────────────────────────────────────
  final updaterService = UpdaterService();

  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider<AuthState>.value(value: authState),
        ChangeNotifierProvider<NotificationService>.value(
          value: notificationService,
        ),
        ChangeNotifierProvider<ConfigService>.value(value: configService),
        ChangeNotifierProvider<UpdaterService>.value(value: updaterService),
      ],
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
  @override
  Widget build(BuildContext context) {
    // Read auth state to determine the initial route.
    final auth = context.watch<AuthState>();

    final botToastBuilder = BotToastInit();

    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'GUTVita${BuildConfig.titleSuffix}',
      theme: stockpileTheme,
      // Wrap BotToast's builder so a staging build is always visibly marked.
      // On production the ribbon is absent and this is a pass-through.
      builder: (context, child) =>
          botToastBuilder(context, StagingBadge(child: child)),
      // Use onGenerateRoute for centralized, role-aware routing.
      onGenerateRoute: appRouter,
      // Initial route depends on authentication status.
      initialRoute: auth.isAuthenticated && auth.userRole != null
          ? AppRoutes.defaultForRole(auth.userRole!)
          : AppRoutes.landing,
      // Build ONE route for the initial path. Flutter's default splits the
      // path into segments (e.g. '/landing' → '/' + '/landing') and builds
      // each; the '/' segment would hit the guard and redirect to login,
      // clearing the landing page. Generating a single route avoids that.
      onGenerateInitialRoutes: (initialRoute) {
        final route = appRouter(RouteSettings(name: initialRoute));
        return route == null ? const <Route<dynamic>>[] : [route];
      },
      navigatorObservers: [BotToastNavigatorObserver()],
    );
  }
}
