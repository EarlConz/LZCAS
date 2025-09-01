import 'package:flutter/material.dart';
import 'dashboardpage.dart';
import 'inventorypage.dart';
import 'memberspage.dart';
import 'loyaltypage.dart';
import '/widgets/sidebar.dart';
import '/widgets/appbar.dart'; // New import

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
      child: LoyaltyPage(),
    ),
  ];

  final List<String> _titles = [
    "Dashboard",
    "Inventory",
    "Members",
    "Loyalty Points",
  ];

  void _onItemTapped(int index) {
    setState(() {
      _selectedIndex = index;
    });
  }

  @override
  Widget build(BuildContext context) {
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
               CustomAppBar(title: _titles[_selectedIndex]),
                Expanded(child: _pages[_selectedIndex]),
              ],
            ),
          ),
        ],
      ),
    );
  }
}