import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'dart:async';
import '../db/db.dart' show Sale, repository;
import '../widgets/search.dart';
import '../buttons/sellbutton.dart';
import '../buttons/redeembutton.dart';

class TransactionsTable extends StatefulWidget {
  const TransactionsTable({super.key});

  @override
  State<TransactionsTable> createState() => _TransactionsTableState();
}

class _TransactionsTableState extends State<TransactionsTable> {
  List<Sale> _sales = [];
  bool _loading = false;
  String _searchTerm = '';
  late final StreamSubscription<String> _sub;

  @override
  void initState() {
    super.initState();
    _loadSales();
    _sub = repository.changes.listen((e) {
      if (e == 'sale_added' || e == 'item_updated') {
        _loadSales();
      }
    });
  }

  @override
  void dispose() {
    _sub.cancel();
    super.dispose();
  }

  Future<void> _loadSales() async {
    if (!mounted) return;
    setState(() => _loading = true);
    try {
      final s = (await repository.fetchSales())
          .where((sale) => sale.price > 0)
          .toList();
      if (!mounted) return;
      setState(() {
        _sales = s.reversed.toList(); // show recent first
        _loading = false;
      });
    } catch (e, st) {
      // ignore: avoid_print
      print('TransactionPage: failed to load sales: $e\n$st');
      if (!mounted) return;
      setState(() {
        _sales = [];
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final filteredSales = _sales.where((sale) {
      final searchTerm = _searchTerm.toLowerCase();
      return sale.itemName.toLowerCase().contains(searchTerm) ||
          sale.id.toString().contains(searchTerm);
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
                    setState(() {
                      _searchTerm = value;
                    });
                  },
                  hintText: "Search transactions...",
                  borderRadius: 12,
                  contentPadding: const EdgeInsets.symmetric(
                    vertical: 8,
                    horizontal: 16,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              const SellButton(),
              const SizedBox(width: 8),
              const RedeemButton(),
            ],
          ),
        ),
        Expanded(
          child: _loading
              ? const Center(child: CircularProgressIndicator())
              : filteredSales.isEmpty
              ? const Center(child: Text('No transactions yet'))
              : SizedBox(
                  width: double.infinity,
                  child: Theme(
                    data: Theme.of(context).copyWith(
                      cardTheme: CardThemeData(
                        elevation: 0,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                          side: BorderSide(
                            color: Colors.grey.shade300,
                            width: 1,
                          ),
                        ),
                        color: Colors.white,
                      ),
                    ),
                    child: LayoutBuilder(
                      builder: (context, constraints) {
                        final reserved = 140.0;
                        var available = constraints.maxHeight - reserved;
                        if (available < 56) available = 56;
                        var estimated = (available ~/ 56).clamp(1, 10);
                        return SingleChildScrollView(
                          child: PaginatedDataTable(
                            headingRowColor: WidgetStateProperty.all(
                              Colors.blueGrey[50],
                            ),
                            columnSpacing: 40,
                            rowsPerPage: estimated,
                            columns: const [
                              DataColumn(label: Text('Item Name')),
                              DataColumn(label: Text('Quantity')),
                              DataColumn(label: Text('Price')),
                              DataColumn(label: Text('Date')),
                              DataColumn(label: Text('Sale ID')),
                            ],
                            source: _TransactionsDataSource(filteredSales),
                          ),
                        );
                      },
                    ),
                  ),
                ),
        ),
      ],
    );
  }
}

class _TransactionsDataSource extends DataTableSource {
  final List<Sale> _sales;

  _TransactionsDataSource(this._sales);

  @override
  DataRow getRow(int index) {
    if (index >= _sales.length) return const DataRow(cells: []);
    final sale = _sales[index];
    final isEven = index % 2 == 0;

    return DataRow(
      color: WidgetStateProperty.resolveWith<Color?>((Set<WidgetState> states) {
        if (isEven) return Colors.grey[100];
        return null;
      }),
      cells: [
        DataCell(Text(sale.itemName)),
        DataCell(Text(sale.quantity.toString())),
        DataCell(Text('₱${sale.price}')),
        DataCell(Text(DateFormat.yMMMd().add_jm().format(sale.timestamp))),
        DataCell(Text('ID:${sale.id}')),
      ],
    );
  }

  @override
  bool get isRowCountApproximate => false;

  @override
  int get rowCount => _sales.length;

  @override
  int get selectedRowCount => 0;
}
