// A dialog to edit a group of sales (cart) together. This operates on all Sale rows
// that share the same timestamp second as the selected sale (pragmatic grouping).
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:lzcas/db/db.dart'
    show Sale, repository, inventoryItemsFromRows, membersFromRows;

class SaleCartEditor extends StatefulWidget {
  final Sale seedSale;
  const SaleCartEditor({super.key, required this.seedSale});

  @override
  State<SaleCartEditor> createState() => _SaleCartEditorState();
}

class _SaleCartEditorState extends State<SaleCartEditor> {
  List<Sale> lines = [];
  bool loading = true;
  List<Map<String, dynamic>> _items = [];
  List<Map<String, dynamic>> _members = [];
  int? _selectedBuyerId;

  @override
  void initState() {
    super.initState();
    _loadGroup();
  }

  Future<void> _loadGroup() async {
    final all = await repository.fetchSales();
    final itemRows = await repository.fetchItems();
    _items = inventoryItemsFromRows(itemRows);
    final memberRows = await repository.fetchMembers();
    _members = membersFromRows(memberRows);
    final ts = widget.seedSale.timestamp;
    final grouped = all
        .where((s) => s.timestamp.toUtc() == ts.toUtc())
        .toList();
    setState(() {
      lines = grouped;
      _selectedBuyerId = grouped.isNotEmpty ? grouped.first.buyerId : null;
      loading = false;
    });
  }

  void _addLine() {
    setState(() {
      lines.add(
        Sale(
          id: 0,
          itemId: 0,
          itemName: '',
          quantity: 1,
          price: 0,
          timestamp: DateTime.now(),
        ),
      );
    });
  }

  Future<String?> _saveAll() async {
    final newLines = lines.map((l) => l).toList();
    final err = await repository.editSaleGroup(
      timestamp: widget.seedSale.timestamp,
      buyerId: _selectedBuyerId,
      newLines: newLines,
    );
    if (err != null) return err;
    return null;
  }

  @override
  Widget build(BuildContext context) {
    if (loading) return const Center(child: CircularProgressIndicator());
    final size = MediaQuery.sizeOf(context);

    final isNarrow = size.width < 520;

    return AlertDialog(
      title: Text('Edit Sale', style: TextStyle(fontSize: isNarrow ? 18 : 20)),
      content: SizedBox(
        width: isNarrow ? double.maxFinite : 700,
        height: isNarrow ? size.height * 0.85 : size.height * 0.72,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.only(bottom: 8.0),
              child: DropdownButtonFormField<int>(
                decoration: const InputDecoration(labelText: 'Buyer'),
                initialValue: _selectedBuyerId,
                items: _members
                    .map(
                      (m) => DropdownMenuItem(
                        value: m['id'] as int?,
                        child: Text(
                          '${m['firstName'] ?? ''} ${m['lastName'] ?? ''}'
                              .trim(),
                        ),
                      ),
                    )
                    .toList(),
                onChanged: (v) => setState(() => _selectedBuyerId = v),
              ),
            ),
            Expanded(
              child: SingleChildScrollView(
                child: Column(
                  children: List.generate(lines.length, (idx) {
                    final line = lines[idx];

                    return Card(
                      margin: const EdgeInsets.symmetric(vertical: 6),
                      child: Padding(
                        padding: const EdgeInsets.all(8.0),
                        child: Column(
                          children: [
                            DropdownButtonFormField<String>(
                              initialValue: line.itemName.isEmpty
                                  ? null
                                  : line.itemName,
                              decoration: const InputDecoration(
                                labelText: 'Item',
                              ),
                              items: _items
                                  .map(
                                    (i) => DropdownMenuItem(
                                      value: i['name'].toString(),
                                      child: Text(i['name'].toString()),
                                    ),
                                  )
                                  .toList(),
                              onChanged: (v) {
                                if (v == null) return;
                                final selected = _items.firstWhere(
                                  (it) => it['name'] == v,
                                  orElse: () => <String, Object>{},
                                );
                                final id = (selected['id'] as int?) ?? 0;
                                setState(
                                  () => lines[idx] = lines[idx].copyWith(
                                    itemName: v,
                                    itemId: id,
                                  ),
                                );
                              },
                            ),
                            const SizedBox(height: 8),
                            Row(
                              children: [
                                Expanded(
                                  child: TextFormField(
                                    initialValue: line.quantity.toString(),
                                    keyboardType: TextInputType.number,
                                    inputFormatters: [
                                      FilteringTextInputFormatter.digitsOnly,
                                    ],
                                    decoration: const InputDecoration(
                                      labelText: 'Qty',
                                    ),
                                    onChanged: (v) {
                                      final newQ = int.tryParse(v) ?? 1;
                                      setState(
                                        () => lines[idx] = lines[idx].copyWith(
                                          quantity: newQ,
                                        ),
                                      );
                                    },
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: TextFormField(
                                    initialValue: line.price.toString(),
                                    keyboardType: TextInputType.number,
                                    inputFormatters: [
                                      FilteringTextInputFormatter.digitsOnly,
                                    ],
                                    decoration: const InputDecoration(
                                      labelText: 'Price',
                                    ),
                                    onChanged: (v) => setState(
                                      () => lines[idx] = lines[idx].copyWith(
                                        price: int.tryParse(v) ?? 0,
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 8),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.end,
                              children: [
                                TextButton.icon(
                                  icon: const Icon(
                                    Icons.delete,
                                    color: Colors.red,
                                  ),
                                  label: const Text('Remove'),
                                  onPressed: () =>
                                      setState(() => lines.removeAt(idx)),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    );
                  }),
                ),
              ),
            ),
            const SizedBox(height: 8),
            if (isNarrow)
              Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  ElevatedButton.icon(
                    onPressed: _addLine,
                    icon: const Icon(Icons.add),
                    label: const Text('Add line'),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Total: ₱${lines.fold<int>(0, (a, b) => a + b.price * b.quantity)}',
                    style: const TextStyle(fontWeight: FontWeight.bold),
                    textAlign: TextAlign.center,
                  ),
                ],
              )
            else
              Row(
                children: [
                  ElevatedButton.icon(
                    onPressed: _addLine,
                    icon: const Icon(Icons.add),
                    label: const Text('Add line'),
                  ),
                  const Spacer(),
                  Text(
                    'Total: ₱${lines.fold<int>(0, (a, b) => a + b.price * b.quantity)}',
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                ],
              ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: const Text('Cancel'),
        ),
        ElevatedButton(
          onPressed: () {
            final nav = Navigator.of(context);
            _saveAll().then((err) {
              if (!mounted) return;
              if (err != null) {
                showDialog<void>(
                  context: nav.context,
                  builder: (ctx) => AlertDialog(
                    title: const Text('Error'),
                    content: Text(err),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.pop(ctx),
                        child: const Text('OK'),
                      ),
                    ],
                  ),
                );
                return;
              }
              nav.pop(true);
            });
          },
          child: const Text('Save'),
        ),
      ],
    );
  }
}
