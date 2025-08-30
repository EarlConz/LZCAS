import 'package:flutter/material.dart';

class Sidebar extends StatelessWidget {
  final int selectedIndex;
  final Function(int) onItemSelected;

  const Sidebar({
    super.key,
    required this.selectedIndex,
    required this.onItemSelected,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 220,
      color: Colors.red.shade700,
      child: Column(
        children: <Widget>[
          // Logo Section
          Container(
            child: Column(
              children: [
                const SizedBox(height: 50),
                const Text(
                  "LZCAS",
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 30),
              ],
            ),
          ),
          // Navigation Section
          _buildNavItem(Icons.dashboard, "Dashboard", 0),
          _buildNavItem(Icons.inventory, "Inventory", 1),
          _buildNavItem(Icons.people, "Members", 2),
          _buildNavItem(Icons.card_giftcard, "Loyalty", 3),
        ],
      ),
    );
  }

  Widget _buildNavItem(IconData icon, String label, int index) {
    bool selected = selectedIndex == index;
    return InkWell(
      onTap: () => onItemSelected(index),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 16),
        color: selected ? Colors.white : Colors.transparent,
        child: Row(
          children: [
            Icon(icon, color: selected ? Colors.red : Colors.white),
            const SizedBox(width: 10),
            Text(
              label,
              style: TextStyle(
                color: selected ? Colors.red : Colors.white,
                fontWeight: selected ? FontWeight.bold : FontWeight.normal,
              ),
            ),
          ],
        ),
      ),
    );
  }
}