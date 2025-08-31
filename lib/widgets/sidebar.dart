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
      decoration: BoxDecoration(
        border: Border.all(color: Colors.green, width: 1.5),
        color: const Color(0xFFE8F5E9), // Light background
      ),
      width: 240,
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
                    color: Colors.black, // Black text for contrast
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
                _buildNavItem(Icons.inventory_2, "Inventory", 1),
                _buildNavItem(Icons.people, "Members", 2),
                _buildNavItem(Icons.card_giftcard, "Loyalty", 3),
              ],
            ),
          ),
          // Bottom section (settings)
          const Divider(color: Colors.green), // Visual separator
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
        width: double.infinity,
        decoration: BoxDecoration(
          color: selected ? Colors.grey.shade200 : Colors.transparent, // Slightly lighter background for selected item
          borderRadius: BorderRadius.only(
            topRight: Radius.circular(30),
            bottomRight: Radius.circular(30),
          ),
          border: selected ? Border.all(color: const Color(0xFF81C784), width: 1.5) : null,
        ),
        child: Row(
          children: [
              Padding(
              padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 16),
              child: Row(
                children: [
                  Icon(icon, color: selected ? const Color(0xFF2E7D32) : Colors.black), // Blue accent color when selected
                  const SizedBox(width: 10),
                  Text(
                    label,
                    style: TextStyle(color: selected ? Colors.greenAccent : Colors.black, // Blue text when selected
                      fontWeight: selected ? FontWeight.bold : FontWeight.normal,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}