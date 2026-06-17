import 'package:flutter/material.dart';
import 'dashboardpage.dart';
import 'inventorypage.dart';
import 'memberspage.dart';
import 'transactionpage.dart';
import 'settingspage.dart';
import '../widgets/sidebar.dart';
import '../theme.dart';

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
    if (_scaffoldKey.currentState!.isDrawerOpen) {
      _scaffoldKey.currentState!.closeDrawer();
    } else {
      _scaffoldKey.currentState!.openDrawer();
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final appBarTheme = theme.appBarTheme;
    final colorScheme = theme.colorScheme;
    final isDesktop = MediaQuery.sizeOf(context).width >= 900;
    final pages = _buildPages();

    return Scaffold(
      key: _scaffoldKey,
      backgroundColor: theme.scaffoldBackgroundColor,
      drawer: isDesktop
          ? null
          : Sidebar(
              selectedIndex: _selectedIndex,
              onItemSelected: _onItemTapped,
            ),

      body: Row(
        children: [
          if (isDesktop)
            SafeArea(
              right: false,
              child: Container(
                color: colorScheme.surface,
                child: NavigationRail(
                  selectedIndex: _selectedIndex,
                  onDestinationSelected: _onItemTapped,
                  minWidth: 88,
                  groupAlignment: -0.84,
                  labelType: NavigationRailLabelType.all,
                  backgroundColor: colorScheme.surface,
                  indicatorColor: colorScheme.primary.withAlpha(
                    (0.12 * 255).round(),
                  ),
                  selectedIconTheme: IconThemeData(color: colorScheme.primary),
                  unselectedIconTheme: IconThemeData(
                    color: colorScheme.onSurfaceVariant,
                  ),
                  selectedLabelTextStyle: theme.textTheme.labelMedium?.copyWith(
                    color: colorScheme.primary,
                    fontWeight: FontWeight.w800,
                  ),
                  unselectedLabelTextStyle: theme.textTheme.labelMedium
                      ?.copyWith(color: colorScheme.onSurfaceVariant),
                  leading: Padding(
                    padding: const EdgeInsets.fromLTRB(12, 18, 12, 28),
                    child: Column(
                      children: [
                        Container(
                          width: 42,
                          height: 42,
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            color: colorScheme.primary,
                            borderRadius: BorderRadius.circular(appRadius),
                          ),
                          child: Text(
                            'L',
                            style: theme.textTheme.titleLarge?.copyWith(
                              color: colorScheme.onPrimary,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'LZCAS',
                          style: theme.textTheme.labelMedium?.copyWith(
                            color: colorScheme.primary,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ],
                    ),
                  ),
                  destinations: const [
                    NavigationRailDestination(
                      icon: Icon(Icons.dashboard_rounded),
                      label: Text('Dashboard'),
                    ),
                    NavigationRailDestination(
                      icon: Icon(Icons.inventory_2_rounded),
                      label: Text('Inventory'),
                    ),
                    NavigationRailDestination(
                      icon: Icon(Icons.people_alt_rounded),
                      label: Text('Members'),
                    ),
                    NavigationRailDestination(
                      icon: Icon(Icons.receipt_long_rounded),
                      label: Text('Transactions'),
                    ),
                    NavigationRailDestination(
                      icon: Icon(Icons.settings_rounded),
                      label: Text('Settings'),
                    ),
                  ],
                ),
              ),
            ),
          if (isDesktop) const VerticalDivider(width: 1),
          Expanded(
            child: Column(
              children: [
                SafeArea(
                  top: true,
                  child: Container(
                    decoration: BoxDecoration(
                        color: appBarTheme.backgroundColor ?? colorScheme.surface,
                      border: Border(
                        bottom: BorderSide(color: theme.dividerColor),
                      ),
                    ),
                    padding: EdgeInsets.fromLTRB(
                      isDesktop ? 24.0 : 16.0,
                      14.0,
                      24.0,
                      14.0,
                    ),
                    alignment: Alignment.centerLeft,
                    child: Row(
                      children: [
                        if (!isDesktop) ...[
                          IconButton(
                            icon: const Icon(Icons.menu_rounded),
                            tooltip: "Toggle Sidebar",
                            onPressed: _toggleSidebar,
                          ),
                          const SizedBox(width: 12),
                        ],
                        Expanded(
                          child: Text(
                            _titles[_selectedIndex],
                            overflow: TextOverflow.ellipsis,
                            style:
                                appBarTheme.titleTextStyle ??
                                theme.textTheme.headlineMedium?.copyWith(
                                  color: colorScheme.onSurface,
                                  fontWeight: FontWeight.w600,
                                ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                Expanded(
                  child: Container(
                    color: theme.scaffoldBackgroundColor,
                    child: pages[_selectedIndex],
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
