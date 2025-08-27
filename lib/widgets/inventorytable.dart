import 'package:flutter/material.dart';
import '/buttons/inventoryactionbutton.dart';
import '/buttons/inventoryfilterbutton.dart';
import '/widgets/searchinventory.dart';

class InventoryTable extends StatefulWidget {
  const InventoryTable({super.key});

  @override
  State<InventoryTable> createState() => _InventoryTableState();
}

class _InventoryTableState extends State<InventoryTable> {
  String searchTerm = "";
  String? selectedStatus;
  String? selectedCategory;

  List<Map<String, dynamic>> items = [
    {
      "name": "Tomatoes",
      "category": "Powder",
      "stock": 120,
      "lastUpdated": "Aug 15, 2024, 14:30",
      "status": "Good"
    },
    {
      "name": "Chicken Breast",
      "category": "Tablet/Capsules",
      "stock": 40,
      "lastUpdated": "Aug 15, 2024, 14:30",
      "status": "Low Stock"
    },
    {
      "name": "Eggs",
      "category": "Tablet/Capsules",
      "stock": 0,
      "lastUpdated": "Aug 15, 2024, 14:30",
      "status": "Out of Stock"
    },
    {
      "name": "Olive Oil",
      "category": "Oil",
      "stock": 100,
      "lastUpdated": "Aug 15, 2024, 14:30",
      "status": "Good"
    },
  ];

  Color _getStatusColor(String status) {
    switch (status) {
      case "Good":
        return Colors.green;
      case "Low Stock":
        return Colors.orange;
      case "Out of Stock":
        return Colors.red;
      default:
        return Colors.grey;
    }
  }

  // 🔹 Update status automatically when stock changes
  void _refreshStatus(Map<String, dynamic> item) {
    if (item["stock"] <= 0) {
      item["status"] = "Out of Stock";
    } else if (item["stock"] < 50) {
      item["status"] = "Low Stock";
    } else {
      item["status"] = "Good";
    }
  }

  @override
  Widget build(BuildContext context) {
    // 🔹 Apply filters
    final filteredItems = items.where((item) {
      final matchesSearch =
          item["name"].toString().toLowerCase().contains(searchTerm.toLowerCase());
      final matchesStatus =
          selectedStatus == null || item["status"] == selectedStatus;
      final matchesCategory =
          selectedCategory == null || item["category"] == selectedCategory;
      return matchesSearch && matchesStatus && matchesCategory;
    }).toList();

    return Column(
      children: [
        // 🔹 Search + Filter Toolbar
        Padding(
          padding: const EdgeInsets.all(8.0),
          child: Row(
            children: [
              InventorySearchBar(
                onSearchChanged: (value) {
                  setState(() => searchTerm = value);
                },
              ),
              const SizedBox(width: 8),
              InventoryFilterButton(
                selectedStatus: selectedStatus,
                selectedCategory: selectedCategory,
                onStatusChanged: (status) {
                  setState(() => selectedStatus = status);
                },
                onCategoryChanged: (category) {
                  setState(() => selectedCategory = category);
                },
              ),
            ],
          ),
        ),

        // 🔹 Table
        Expanded(
          child: SingleChildScrollView(
            scrollDirection: Axis.vertical,
            child: ConstrainedBox(
              constraints: BoxConstraints(
                minWidth: MediaQuery.of(context).size.width,
              ),
              child: DataTable(
                headingRowColor:
                    MaterialStateProperty.all(Colors.blueGrey[50]),
                columns: const [
                  DataColumn(label: Text("Item Name")),
                  DataColumn(label: Text("Category")),
                  DataColumn(label: Text("Stock")),
                  DataColumn(label: Text("Last Updated")),
                  DataColumn(label: Text("Status")),
                  DataColumn(label: Text("Action")),
                ],
                rows: List.generate(filteredItems.length, (index) {
                  final item = filteredItems[index];
                  final isEven = index % 2 == 0;

                  return DataRow(
                    color: MaterialStateProperty.resolveWith<Color?>(
                      (Set<MaterialState> states) {
                        if (isEven) return Colors.grey[100];
                        return null;
                      },
                    ),
                    cells: [
                      DataCell(Text(item["name"].toString())),
                      DataCell(Text(item["category"].toString())),
                      DataCell(Text(item["stock"].toString())),
                      DataCell(Text(item["lastUpdated"].toString())),
                      DataCell(
                        Text(
                          item["status"].toString(),
                          style: TextStyle(
                            color: _getStatusColor(item["status"].toString()),
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                      DataCell(
                        InventoryActionButton(
                          item: item,
                          onUpdated: () {
                            setState(() {
                              _refreshStatus(item); // ✅ auto update status
                            });
                          },
                        ),
                      ),
                    ],
                  );
                }),
              ),
            ),
          ),
        ),
      ],
    );
  }
}