import 'package:flutter/material.dart';
import 'dart:async';
import 'package:intl/intl.dart';
import '../widgets/infocard.dart';
import '../buttons/sellbutton.dart';
import '../buttons/redeembutton.dart';
import '../db/db.dart' show repository, Sale;

class TransactionPage extends StatefulWidget {
  const TransactionPage({super.key});

  @override
  State<TransactionPage> createState() => _TransactionPageState();
}

class _TransactionPageState extends State<TransactionPage> {
  List<Sale> _sales = [];
  bool _loading = false;
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

  Future<void> _loadSales() async {
    if (!mounted) return;
    setState(() => _loading = true);
    try {
      final s = await repository.fetchSales();
      if (!mounted) return;
      setState(() {
        _sales = s.reversed.toList(); // show recent first
        _loading = false;
      });
    } catch (e, st) {
      // Log the error so we can inspect runtime issues (missing tables, etc.)
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
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Scaffold(
      appBar: AppBar(
        actions: [
          IconButton(onPressed: _loadSales, icon: const Icon(Icons.refresh))
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(20.0),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Rewards card
            SizedBox(
              width: 280,
        child: InfoCard(
          title: "REWARDS",
          icon: Icons.card_giftcard_rounded,
        contentColor: colorScheme.secondary,
      backgroundColor: colorScheme.secondary.withAlpha((0.1 * 255).round()),
                contentWidget: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text("1,000 pts :   ₱500",
                        style: theme.textTheme.bodyMedium?.copyWith(height: 1.5)),
                    Text("2,000 pts :   ₱1,000",
                        style: theme.textTheme.bodyMedium?.copyWith(height: 1.5)),
                    Text("5,000 pts :   ₱2,500",
                        style: theme.textTheme.bodyMedium?.copyWith(height: 1.5)),
                    Text("10,000 pts : ₱5,000",
                        style: theme.textTheme.bodyMedium?.copyWith(height: 1.5)),
                    Text("20,000 pts : ₱10,000",
                        style: theme.textTheme.bodyMedium?.copyWith(height: 1.5)),
                  ],
                ),
              ),
            ),

            const SizedBox(width: 20),

            const SellButton(),

            const SizedBox(width: 20),

            const RedeemButton(),

            const SizedBox(width: 20),

            const SizedBox(width: 20),

            // Transactions list
            Expanded(
              child: Card(
                child: Padding(
                  padding: const EdgeInsets.all(12.0),
                  child: _loading
                      ? const Center(child: CircularProgressIndicator())
                      : _sales.isEmpty
                          ? const Center(child: Text('No transactions yet'))
                          : ListView.separated(
                              itemCount: _sales.length,
                              separatorBuilder: (context, index) => const Divider(height: 1),
                              itemBuilder: (context, index) {
                                final sale = _sales[index];
                                return ListTile(
                                  leading: CircleAvatar(
                                    child: Text(sale.quantity.toString()),
                                  ),
                                  title: Text(sale.itemName),
                                  subtitle: Text(
                                      'Price: ₱${sale.price} • ${DateFormat.yMMMd().add_jm().format(sale.timestamp)}'),
                                  trailing: Text('ID:${sale.id}'),
                                );
                              },
                            ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  void dispose() {
    _sub.cancel();
    super.dispose();
  }
}