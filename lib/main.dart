import 'package:flutter/material.dart';
import 'pages/homepage.dart';
import 'theme.dart';
import 'data/db_init.dart';
import 'package:lzcas/db/db.dart';

late final DbRepository repository;

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final db = await initDb();
  repository = DbRepository(db);
  // seed initial data if DB empty
  // await repository.seedItemsFromList(inventoryItemsSeed);
  // await repository.seedMembersFromList(membersdataSeed);

  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Admin App',
      theme: appTheme,
      home: const HomePage(),
    );
  }
}
