import 'package:flutter/material.dart';
import 'dashboardpage.dart';
import 'inventorypage.dart';
import 'memberspage.dart';
import 'transactionpage.dart';
import 'settingspage.dart';
import '/widgets/sidebar.dart';

class HomePage extends StatefulWidget {
  final void Function(bool)? onToggleTheme;
  final bool isDark;

  const HomePage({super.key, this.onToggleTheme, this.isDark = false});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  int _selectedIndex = 0;
  bool _isSidebarOpen = false; 

  @override
  void initState() {
    super.initState();
  }

  List<Widget> _buildPages() => [
        const DashboardPage(),
        const InventoryPage(),
        const MembersPage(),
        const TransactionPage(),
        SettingsPage(onToggle: widget.onToggleTheme, initialDark: widget.isDark),
      ];

  final List<String> _titles = [
    "Dashboard",
    "Inventory",
    "Members",
    "Transactions",
    "Settings",
  ];

  void _onItemTapped(int index) {
    setState(() {
      _selectedIndex = index;
    });
  }

  void _toggleSidebar() {
    setState(() {
      _isSidebarOpen = !_isSidebarOpen;
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
          
          // if (_isSidebarOpen)
          //   Sidebar(selectedIndex: _selectedIndex, onItemSelected: _onItemTapped),
          
          AnimatedContainer(
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeInOut,
            width: _isSidebarOpen ? 250 : 0,
            child: AnimatedOpacity(
                duration: const Duration(milliseconds: 200),
                opacity: _isSidebarOpen ? 1.0 : 0.0,
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  physics: const NeverScrollableScrollPhysics(),
                  child: SizedBox(
                    width: 250,
                    child: Sidebar(selectedIndex: _selectedIndex, onItemSelected: _onItemTapped),
                  ),
                )
              ),
          ),

          Expanded(
            child: Column(
              children: [
                SafeArea(
                  top: true,
                  child: Container(
                    decoration: BoxDecoration(
                      color: appBarTheme.backgroundColor ?? colorScheme.surface,
                      boxShadow: (appBarTheme.elevation != null &&
                              appBarTheme.elevation! > 0)
                          ? [
                              BoxShadow(
                                color: appBarTheme.shadowColor ??
                                    Colors.black.withAlpha((0.1 * 255).round()),
                                blurRadius: 20,
                                offset: const Offset(0, 8),
                              ),
                            ]
                          : null,
                    ),
                    padding: const EdgeInsets.fromLTRB(16.0, 20.0, 24.0, 12.0), 
                    alignment: Alignment.centerLeft,
                    child: Row(
                      children: [
                        IconButton(
                          icon: Icon(
                            _isSidebarOpen ? Icons.menu_open_rounded : Icons.menu_rounded,
                            color: colorScheme.onSurface,
                          ),
                          tooltip: _isSidebarOpen ? "Hide Sidebar" : "Show Sidebar",
                          onPressed: _toggleSidebar,
                        ),
                        const SizedBox(width: 12),
                        Text(
                          _titles[_selectedIndex],
                          style: appBarTheme.titleTextStyle ??
                              theme.textTheme.headlineMedium?.copyWith(
                                color: colorScheme.onSurface,
                                fontWeight: FontWeight.w600,
                              ),
                        ),
                      ],
                    ),
                  ),
                ),
                Expanded(
                  child: Container(
                    color: theme.colorScheme.surface,
                    child: _buildPages()[_selectedIndex],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}