import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

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
      width: 240,
      color: Colors.grey.shade900, // Dark background
      child: Column(
        children: <Widget>[
          // Logo Section (SizedBox for the upper spacing)
          Container(
            child: Column(
              children: [
                const SizedBox(height: 50),
                const Text(
                  "LZCAS",
                  style: TextStyle(
                    color: Colors.white, // White text for contrast
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                SizedBox(height: 40),
              ],
            ),
          ),
          // Navigation Section
          Expanded( // Take up remaining space
            child: ListView( // Use ListView for scrollable items
              padding: EdgeInsets.zero, // Remove default padding
              children: [
                _buildNavItem(Icons.dashboard, "Dashboard", 0),
                _buildNavItem(Icons.inventory, "Inventory", 1),
                _buildNavItem(Icons.people, "Members", 2),
                _buildNavItem(Icons.card_giftcard, "Loyalty", 3),
              ],
            ),
          ),
          // Bottom section (e.g., settings, profile)
          const Divider(color: Colors.grey), // Visual separator
          _buildNavItem(Icons.settings, "Settings", 4),
          SizedBox(height: 20), // Space at the bottom
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
        decoration: BoxDecoration(
          color: selected ? Colors.grey.shade800 : Colors.transparent, // Slightly lighter background for selected item
          borderRadius: BorderRadius.only(
            topRight: Radius.circular(30),
            bottomRight: Radius.circular(30),
          ),
        ),
        child: Row(
          children: [
            Icon(icon, color: selected ? Colors.blueAccent : Colors.white), // Use a more modern accent color
            const SizedBox(width: 10),
            Expanded(
              child: Text(
              label,
                style: TextStyle(color: selected ? Colors.red : Colors.white,
                fontWeight: selected ? FontWeight.bold : FontWeight.normal,
              ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}