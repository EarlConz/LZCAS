import 'package:flutter/material.dart';
import '/widgets/inventorytable.dart';
import '/widgets/searchinventory.dart';

class InventoryPage extends StatefulWidget {
  const InventoryPage({super.key});

  @override
  State<InventoryPage> createState() => _InventoryPageState();
}

class _InventoryPageState extends State<InventoryPage> {
  String searchTerm = "";

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // 🔎 Search bar on top
        SearchBarWidget(
          onChanged: (value) {
            setState(() {
              searchTerm = value;
            });
          },
        ),
        const SizedBox(height: 10),

        // 📋 Inventory Table (connected to searchTerm)
        Expanded(
          child: InventoryTable(
            searchTerm: searchTerm, // ✅ no const
          ),
        ),
      ],
    );
  }
}