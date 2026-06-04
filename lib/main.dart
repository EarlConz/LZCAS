import 'package:flutter/material.dart';
import 'pages/homepage.dart';
import 'theme.dart';
import 'data/db_init.dart';
import 'data/supabase_config.dart';
import 'package:lzcas/db/db.dart';

late final DbRepository repository;

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final supabaseEnabled = await initSupabase();
  if (supabaseEnabled) {
    // ignore: avoid_print
    print('Supabase initialized');
  } else {
    // ignore: avoid_print
    print('Supabase not configured; running in local SQLite mode');
  }

  final db = await initDb();
  repository = DbRepository(db);
  // Run a one-off points consistency migration at startup. This is idempotent.
  try {
    await repository.ensurePointsConsistency();
  } catch (e) {
    // ignore: avoid_print
    print('ensurePointsConsistency failed: $e');
  }
  // If you need initial data, use CSV import helpers on the repository
  // e.g. `await repository.importItemsCsv(csvString)` or use your own seed script.

  runApp(const MyApp());
}

class MyApp extends StatefulWidget {
  const MyApp({super.key});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  ThemeMode _mode = ThemeMode.light;

  void toggleThemeMode(bool dark) {
    setState(() {
      _mode = dark ? ThemeMode.dark : ThemeMode.light;
    });
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Admin App',
      theme: appTheme,
      darkTheme: appDarkTheme,
      themeMode: _mode,
      home: HomePage(
        onToggleTheme: toggleThemeMode,
        isDark: _mode == ThemeMode.dark,
      ),
    );
  }
}
