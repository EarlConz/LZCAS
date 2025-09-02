import 'package:flutter/material.dart';
import 'dashboardpage.dart';
import 'inventorypage.dart';
import 'memberspage.dart';
import 'transactionpage.dart';
import '/widgets/sidebar.dart';


class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  int _selectedIndex = 0;

  final List<Widget> _pages = const [
     ColoredBox(
      color: Color(0xFFF9FAFB),
      child: DashboardPage(),
    ),
    ColoredBox(
      color: Color(0xFFF9FAFB),
      child: InventoryPage(),
    ),
    ColoredBox(
      color: Color(0xFFF9FAFB),
      child: MembersPage(),
    ),
    ColoredBox(
      color: Color(0xFFF9FAFB),
      child: TransactionPage(),
    ),
  ];

  final List<String> _titles = [
    "Dashboard",
    "Inventory",
    "Members",
    "Transactions",
  ];

  void _onItemTapped(int index) {
    setState(() {
      _selectedIndex = index;
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final appBarTheme = theme.appBarTheme;
    final colorScheme = theme.colorScheme;

    return Scaffold(
      body: Row(
        children: [
          Sidebar(
            selectedIndex: _selectedIndex,
            onItemSelected: _onItemTapped,
          ),
          Expanded(
            child: Column(
              children: [
               SafeArea(
                  top: true,
                  child: Container(
                    decoration: BoxDecoration(
                      color: appBarTheme.backgroundColor ?? colorScheme.surface,
                      boxShadow: (appBarTheme.elevation != null && appBarTheme.elevation! > 0)
                          ? [
                              BoxShadow(
                                color: appBarTheme.shadowColor ?? Colors.black.withOpacity(0.1),
                                blurRadius: 20,
                                offset: const Offset(0, 8),
                              ),
                            ]
                          : null,
                    ),
                    padding: const EdgeInsets.fromLTRB(24.0, 20.0, 24.0, 0.0),
                    alignment: Alignment.centerLeft,
                    child: Text(
                      _titles[_selectedIndex],
                      style: appBarTheme.titleTextStyle ?? theme.textTheme.headlineMedium?.copyWith(
                        color: colorScheme.onSurface,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
                Expanded(child: _pages[_selectedIndex]),
              ],
            ),
          ),
        ],
      ),
    );
  }
}