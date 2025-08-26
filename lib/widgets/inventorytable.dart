import 'package:flutter/material.dart';

class InventoryTable extends StatelessWidget {
  final String searchTerm;

  InventoryTable({
    super.key,
    required this.searchTerm,
  });

  final List<Map<String, dynamic>> items = [
    {
      "name": "LZCAS COFFEE",
      "category": "Powder",
      "stock": 120,
      "lastUpdated": "Aug 15, 2024, 14:30",
      "status": "Good"
    },
    {
      "name": "LZCAS T Cap",
      "category": "Tablet/Capsules",
      "stock": 40,
      "lastUpdated": "Aug 15, 2024, 14:30",
      "status": "Low Stock"
    },
    {
      "name": "LZCAS Prostate Tab",
      "category": "Tablet/Capsules",
      "stock": 0,
      "lastUpdated": "Aug 15, 2024, 14:30",
      "status": "Out of Stock"
    },
    {
      "name": "LZCAS G OIL",
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

  @override
  Widget build(BuildContext context) {
    // 🔎 Filter items based on search term
    final filteredItems = items.where((item) {
      return item["name"]
          .toString()
          .toLowerCase()
          .contains(searchTerm.toLowerCase());
    }).toList();

    return SizedBox.expand(
      child: SingleChildScrollView(
        scrollDirection: Axis.vertical,
        child: ConstrainedBox(
          constraints: BoxConstraints(
              minWidth: MediaQuery.of(context).size.width),
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
                  const DataCell(Icon(Icons.more_vert)),
                ],
              );
            }),
          ),
        ),
      ),
    );
  }
}