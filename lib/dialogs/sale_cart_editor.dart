// A dialog to edit a group of sales (cart) together. This operates on all Sale rows
// that share the same timestamp second as the selected sale (pragmatic grouping).
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:lzcas/db/db.dart' show Sale, repository, inventoryItemsFromRows, membersFromRows, Member;
// no drift imports needed here

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
  // group by exact timestamp equality (we now set transaction timestamp when creating sales)
  final ts = widget.seedSale.timestamp;
  final grouped = all.where((s) => s.timestamp.toUtc() == ts.toUtc()).toList();
    setState(() {
      lines = grouped;
      _selectedBuyerId = grouped.isNotEmpty ? grouped.first.buyerId : null;
      loading = false;
    });
  }

  void _addLine() {
    setState(() {
      lines.add(Sale(
        id: 0,
        itemId: 0,
        itemName: '',
        quantity: 1,
        points: 0,
        price: 0,
        timestamp: DateTime.now(),
      ));
    });
  }

  /// Returns null on success, or an error message to display to the user.
  Future<String?> _saveAll() async {
    // Determine original and new total points for this cart (grouped by timestamp)
    final all = await repository.fetchSales();
    final originals = all.where((s) => s.timestamp.toUtc() == widget.seedSale.timestamp.toUtc()).toList();
    final originalPoints = originals.fold<int>(0, (acc, s) => acc + (s.points));
    final newPoints = lines.fold<int>(0, (acc, l) => acc + (l.points));
    final delta = newPoints - originalPoints; // positive => award, negative => deduct

    // If deducting points from the referrer, make sure the referrer has enough
    if (delta < 0 && _selectedBuyerId != null) {
      final buyer = await repository.getMemberById(_selectedBuyerId!);
      if (buyer != null) {
        Member? refMember;
        if (buyer.referrerId != null) refMember = await repository.getMemberById(buyer.referrerId!);
        if (refMember == null) {
          final refRaw = (buyer.referrer ?? '').toString();
          if (refRaw.isNotEmpty) {
            final refId = int.tryParse(refRaw);
            if (refId != null) refMember = await repository.getMemberById(refId);
            if (refMember == null) {
              final mems = await repository.fetchMembers();
              try {
                refMember = mems.firstWhere((r) {
                  final name = '${r.firstName ?? ''} ${r.lastName ?? ''}'.trim();
                  return name.toLowerCase() == refRaw.toLowerCase();
                });
              } catch (_) {
                refMember = null;
              }
            }
          }
        }

        if (refMember != null) {
          final needed = -delta;
          if (refMember.points < needed) {
            return '${refMember.firstName} ${refMember.lastName} has only ${refMember.points} points but you are trying to deduct $needed points.';
          }
        }
      }
    }

    // Use repository transaction helper to atomically replace the group, adjust stock, and update referrer points
    final newLines = lines.map((l) => l).toList();
    final err = await repository.editSaleGroup(timestamp: widget.seedSale.timestamp, buyerId: _selectedBuyerId, newLines: newLines);
    if (err != null) return err;
    return null;
  }

  @override
  Widget build(BuildContext context) {
    if (loading) return const Center(child: CircularProgressIndicator());
    return AlertDialog(
      title: Text('Edit Sale (Cart) — ${widget.seedSale.timestamp.toLocal().toIso8601String()}'),
      content: SizedBox(
        width: 700,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Buyer picker
            Padding(
              padding: const EdgeInsets.only(bottom: 8.0),
              child: DropdownButtonFormField<int>(
                decoration: const InputDecoration(labelText: 'Buyer'),
                initialValue: _selectedBuyerId,
                items: _members.map((m) => DropdownMenuItem(value: m['id'] as int?, child: Text('${m['firstName'] ?? ''} ${m['lastName'] ?? ''}'.trim()))).toList(),
                onChanged: (v) => setState(() => _selectedBuyerId = v),
              ),
            ),
            Flexible(
              child: ListView.builder(
                shrinkWrap: true,
                itemCount: lines.length,
                itemBuilder: (ctx, idx) {
                  final line = lines[idx];
                  return Card(
                    margin: const EdgeInsets.symmetric(vertical: 6),
                    child: Padding(
                      padding: const EdgeInsets.all(8.0),
                      child: Row(
                        children: [
                          Expanded(
                            child: DropdownButtonFormField<String>(
                              initialValue: line.itemName.isEmpty ? null : line.itemName,
                              decoration: const InputDecoration(labelText: 'Item'),
                              items: _items.map((i) => DropdownMenuItem(value: i['name'].toString(), child: Text(i['name'].toString()))).toList(),
                              onChanged: (v) {
                                if (v == null) return;
                                final selected = _items.firstWhere((it) => it['name'] == v, orElse: () => <String, Object>{});
                                final perUnit = (selected['points'] as int?) ?? 0;
                                final id = (selected['id'] as int?) ?? 0;
                                final qty = lines[idx].quantity > 0 ? lines[idx].quantity : 1;
                                final totalPts = perUnit * qty;
                                setState(() => lines[idx] = lines[idx].copyWith(itemName: v, itemId: id, points: totalPts));
                              },
                            ),
                          ),
                          const SizedBox(width: 8),
                          SizedBox(
                            width: 120,
                            child: TextFormField(
                              initialValue: line.quantity.toString(),
                              keyboardType: TextInputType.number,
                              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                              decoration: const InputDecoration(labelText: 'Qty'),
                              onChanged: (v) {
                                final newQ = int.tryParse(v) ?? 1;
                                // find per-unit points from items list by itemId
                                int perUnit = 0;
                                try {
                                  final match = _items.firstWhere((it) => (it['id'] as int?) == lines[idx].itemId, orElse: () => <String, Object>{});
                                  perUnit = (match['points'] as int?) ?? 0;
                                } catch (_) {
                                  perUnit = 0;
                                }
                                final totalPts = perUnit * newQ;
                                setState(() => lines[idx] = lines[idx].copyWith(quantity: newQ, points: totalPts));
                              },
                            ),
                          ),
                          const SizedBox(width: 8),
                          SizedBox(width: 140, child: TextFormField(initialValue: line.price.toString(), keyboardType: TextInputType.number, inputFormatters: [FilteringTextInputFormatter.digitsOnly], decoration: const InputDecoration(labelText: 'Price'), onChanged: (v) => setState(() => lines[idx] = lines[idx].copyWith(price: int.tryParse(v) ?? 0)))),
                          IconButton(icon: const Icon(Icons.delete, color: Colors.red), onPressed: () => setState(() => lines.removeAt(idx))),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                ElevatedButton.icon(onPressed: _addLine, icon: const Icon(Icons.add), label: const Text('Add line')),
                const Spacer(),
                Text('Total: ₱${lines.fold<int>(0, (a, b) => a + b.price * b.quantity)}', style: const TextStyle(fontWeight: FontWeight.bold)),
              ],
            )
          ],
        ),
      ),
      actions: [
  TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          ElevatedButton(onPressed: () {
            final nav = Navigator.of(context);
            _saveAll().then((err) {
              if (!mounted) return;
              if (err != null) {
                showDialog<void>(
                  context: nav.context,
                  builder: (ctx) => AlertDialog(
                    title: const Text('Error'),
                    content: Text(err),
                    actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('OK'))],
                  ),
                );
                return;
              }
              nav.pop(true);
            });
          }, child: const Text('Save')),
      ],
    );
  }
}
