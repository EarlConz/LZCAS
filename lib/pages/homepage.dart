import 'package:flutter/material.dart';
import 'dashboardpage.dart';
import 'inventorypage.dart';
import 'settingspage.dart';
import 'supplierspage.dart';
import 'orderspage.dart';
import 'analyticspage.dart';
import 'helpsupportpage.dart';
import '../widgets/stockpile_sidebar.dart';
import '../widgets/stockpile_topbar.dart';

class HomePage extends StatefulWidget {
  final void Function(bool)? onToggleTheme;
  final bool isDark;

  const HomePage({super.key, this.onToggleTheme, this.isDark = false});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  int _selectedIndex = 0;

  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();

  static const _titles = [
    'Dashboard',
    'Inventory',
    'Members',
    'Transactions',
    'Reports',
    'Settings',
    'Help & Support',
  ];

  List<Widget> _buildPages() => [
    const DashboardPage(),
    const InventoryPage(),
    const SuppliersPage(),
    const OrdersPage(),
    const AnalyticsPage(),
    SettingsPage(onToggle: widget.onToggleTheme, initialDark: widget.isDark),
    const HelpSupportPage(),
  ];

  void _onItemTapped(int index) {
    setState(() {
      _selectedIndex = index;
    });
  }

  void _toggleSidebar() {
    if (_scaffoldKey.currentState!.isDrawerOpen) {
      _scaffoldKey.currentState!.closeDrawer();
    } else {
      _scaffoldKey.currentState!.openDrawer();
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDesktop = MediaQuery.sizeOf(context).width >= 900;
    final pages = _buildPages();

    final sidebar = StockpileSidebar(
      selectedIndex: _selectedIndex,
      onItemSelected: (i) {
        if (!isDesktop) Navigator.pop(context); // close drawer on mobile
        _onItemTapped(i);
      },
    );

    return Scaffold(
      key: _scaffoldKey,
      drawer: isDesktop ? null : sidebar,
      body: Row(
        children: [
          // Desktop sidebar
          if (isDesktop) SizedBox(width: 260, child: sidebar),
          if (isDesktop) const VerticalDivider(width: 1),

          // Main content area
          Expanded(
            child: Column(
              children: [
                StockpileTopBar(
                  pageTitle: _titles[_selectedIndex],
                  showMenu: !isDesktop,
                  onMenuTap: _toggleSidebar,
                ),
                Expanded(child: pages[_selectedIndex]),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
