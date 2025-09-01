import 'package:flutter/material.dart';
import '/buttons/inventoryfilterbutton.dart';
import '/widgets/search.dart';
import '/dialogs/edit_stock_dialog.dart';

class InventoryTable extends StatefulWidget {
  const InventoryTable({super.key});

  @override
  State<InventoryTable> createState() => _InventoryTableState();
}

class _InventoryTableState extends State<InventoryTable> {
  String searchTerm = "";
  String? selectedStatus;
  String? selectedCategory;

  final List<Map<String, dynamic>> items = [
    {
      "name": "Tomatoesq",
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

  void _refreshStatus(Map<String, dynamic> item) {
    if (item["stock"] <= 0) {
      item["status"] = "Out of Stock";
    } else if (item["stock"] < 50) {
      item["status"] = "Low Stock";
    } else {
      item["status"] = "Good";
    }
  }

  void _onUpdate(Map<String, dynamic> item) {
    setState(() {
      _refreshStatus(item);
    });
  }

  @override
  Widget build(BuildContext context) {
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
        Padding(
          padding: const EdgeInsets.all(8.0),
          child: Row(
            children: [
              Expanded(
                child: SearchBarWidget(
                  onChanged: (value) {
                    setState(() => searchTerm = value);
                  },
                  hintText: "Search items...",
                  borderRadius: 12,
                  contentPadding: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
                ),
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
        Expanded(
          child: SizedBox(
            width: double.infinity,
            child: Theme(
              data: Theme.of(context).copyWith(
                cardTheme: CardThemeData(
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                    side: BorderSide(color: Colors.grey.shade300, width: 1),
                  ),
                  color: Colors.white,
                ),
              ),
              child: PaginatedDataTable(
                headingRowColor: WidgetStateProperty.all(Colors.blueGrey[50]),
                rowsPerPage: 7,
                columns: const [
                  DataColumn(label: Text("Item Name")),
                  DataColumn(label: Text("Category")),
                  DataColumn(label: Text("Stock")),
                  DataColumn(label: Text("Last Updated")),
                  DataColumn(label: Text("Status")),
                  DataColumn(label: Text("Action")),
                ],
                source: _InventoryDataSource(
                  filteredItems,
                  _getStatusColor,
                  _onUpdate,
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _InventoryDataSource extends DataTableSource {
  final List<Map<String, dynamic>> items;
  final Color Function(String) getStatusColor;
  final void Function(Map<String, dynamic>) onUpdate;

  _InventoryDataSource(this.items, this.getStatusColor, this.onUpdate);

  @override
  DataRow getRow(int index) {
    if (index >= items.length) return const DataRow(cells: []);
    final item = items[index];
    final isEven = index % 2 == 0;
    return DataRow(
      color: WidgetStateProperty.resolveWith<Color?>(
        (Set<WidgetState> states) {
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
              color: getStatusColor(item["status"].toString()),
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
        DataCell(
          Builder(
            builder: (cellContext) => PopupMenuButton<String>(
              icon: const Icon(Icons.more_vert),
              onSelected: (value) {
                if (value == 'edit') {
                  showDialog(
                    context: cellContext,
                    builder: (dialogContext) => EditStockDialog(
                      item: item,
                      onUpdated: () => onUpdate(item),
                    ),
                  );
                }
              },
              itemBuilder: (menuContext) => [
                const PopupMenuItem(
                  value: 'edit',
                  child: Text('Edit Stock'),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  @override
  bool get isRowCountApproximate => false;

  @override
  int get rowCount => items.length;

  @override
  int get selectedRowCount => 0;
}
