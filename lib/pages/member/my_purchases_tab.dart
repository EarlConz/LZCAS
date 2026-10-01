// lib/pages/member/my_purchases_tab.dart
//
// My Purchases: everything this member has bought, at the counter or
// through an online order, in the same look as the Marketplace and Active
// Orders. A few totals at the top, a filter by where it was bought, and the
// purchases themselves grouped by day.
//
// `sales` holds one row per line, so lines bought together are put back
// together here: rows from the same place with the same timestamp are one
// purchase. An online order's lines always share one (the database records
// them in one statement), as do a counter sale's when the POS wrote them
// together.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart' show DateFormat;
import 'package:provider/provider.dart';

import '../../db/db.dart';
import '../../services/config_service.dart';
import '../../utils/fonts.dart';
import '../../utils/formatters.dart' show formatMoney, formatTimeOfDay;
import 'member_order_kit.dart';

enum _Source {
  store('In store', Icons.storefront_outlined),
  online('Online order', Icons.local_shipping_outlined),
  package('Package', Icons.workspace_premium_outlined);

  const _Source(this.label, this.icon);
  final String label;
  final IconData icon;

  static _Source of(Sale s) => s.isPackage
      ? _Source.package
      : s.isOnlineOrder
      ? _Source.online
      : _Source.store;
}

/// Lines bought together.
class _Purchase {
  final _Source source;
  final DateTime? at;
  final List<Sale> lines;
  _Purchase(this.source, this.at, this.lines);

  int get total => lines.fold(0, (s, l) => s + l.price * l.quantity);
  int get items => lines.fold(0, (s, l) => s + l.quantity);
}

class MyPurchasesTab extends StatefulWidget {
  final Member member;
  const MyPurchasesTab({super.key, required this.member});

  @override
  State<MyPurchasesTab> createState() => _MyPurchasesTabState();
}

class _MyPurchasesTabState extends State<MyPurchasesTab> {
  List<Sale> _sales = [];
  bool _loading = true;
  String? _error;
  _Source? _filter; // null = all
  StreamSubscription<String>? _sub;

  @override
  void initState() {
    super.initState();
    _load();
    // A completed online order or a counter sale lands here while open.
    _sub = repository.changes.listen((e) {
      if (e.startsWith('sale_') ||
          e == 'sales_changed' ||
          e == 'orders_changed') {
        _load();
      }
    });
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    final id = widget.member.id;
    if (id == null) return;
    try {
      final sales = await repository.fetchMemberPurchaseHistory(id);
      if (!mounted) return;
      setState(() {
        _sales = sales;
        _loading = false;
        _error = null;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _error = 'Could not load your purchases.';
        _loading = false;
      });
    }
  }

  String _m(num v) =>
      formatMoney(v, symbol: context.read<ConfigService>().currencySymbol);

  List<_Purchase> get _purchases {
    final out = <_Purchase>[];
    for (final s in _sales) {
      final src = _Source.of(s);
      final at = s.timestamp;
      final last = out.isEmpty ? null : out.last;
      final same =
          last != null &&
          last.source == src &&
          last.at != null &&
          at != null &&
          last.at!.difference(at).inSeconds.abs() < 1;
      if (same) {
        last.lines.add(s);
      } else {
        out.add(_Purchase(src, at, [s]));
      }
    }
    return out;
  }

  static String _day(DateTime? t) {
    if (t == null) return 'Date unknown';
    final l = t.toLocal();
    final now = DateTime.now();
    final d = DateTime(l.year, l.month, l.day);
    final today = DateTime(now.year, now.month, now.day);
    final diff = today.difference(d).inDays;
    if (diff == 0) return 'Today';
    if (diff == 1) return 'Yesterday';
    return DateFormat(l.year == now.year ? 'EEE, d MMM' : 'd MMM y').format(l);
  }

  @override
  Widget build(BuildContext context) {
    final c = ShopColors.of(context);
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error != null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(_error!, style: StockpileFonts.satoshi(color: c.muted)),
            const SizedBox(height: 12),
            FilledButton(onPressed: _load, child: const Text('Retry')),
          ],
        ),
      );
    }

    final all = _purchases;
    final shown = _filter == null
        ? all
        : all.where((p) => p.source == _filter).toList();
    final present = {for (final p in all) p.source};

    return ColoredBox(
      color: c.ground,
      child: RefreshIndicator(
        onRefresh: _load,
        child: Align(
          alignment: Alignment.topCenter,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 720),
            child: ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
              children: [
                if (all.isEmpty)
                  _empty(c)
                else ...[
                  _summary(c, all),
                  if (present.length > 1) ...[
                    const SizedBox(height: 14),
                    _chips(c, present),
                  ],
                  ..._days(c, shown),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _empty(ShopColors c) => Padding(
    padding: const EdgeInsets.only(top: 64),
    child: Column(
      children: [
        Icon(Icons.receipt_long_rounded, size: 48, color: c.muted),
        const SizedBox(height: 12),
        Text(
          'No purchases yet',
          style: StockpileFonts.satoshi(
            fontSize: 16,
            fontWeight: FontWeight.w700,
            color: c.text,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          'What you buy in store or order online shows up here.',
          textAlign: TextAlign.center,
          style: StockpileFonts.satoshi(fontSize: 13, color: c.muted),
        ),
      ],
    ),
  );

  Widget _summary(ShopColors c, List<_Purchase> all) {
    final now = DateTime.now();
    final spent = all.fold(0, (s, p) => s + p.total);
    final month = all
        .where(
          (p) =>
              p.at != null &&
              p.at!.toLocal().year == now.year &&
              p.at!.toLocal().month == now.month,
        )
        .fold(0, (s, p) => s + p.total);
    final items = all
        .where((p) => p.source != _Source.package)
        .fold(0, (s, p) => s + p.items);

    Widget tile(String label, String value) => Expanded(
      child: ShopCard(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: StockpileFonts.satoshi(fontSize: 12, color: c.muted),
            ),
            const SizedBox(height: 4),
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text(
                value,
                style: StockpileFonts.satoshi(
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                  color: c.text,
                ),
              ),
            ),
          ],
        ),
      ),
    );

    return Row(
      children: [
        tile('Spent in all', _m(spent)),
        const SizedBox(width: 10),
        tile('This month', _m(month)),
        const SizedBox(width: 10),
        tile('Items bought', '$items'),
      ],
    );
  }

  Widget _chips(ShopColors c, Set<_Source> present) {
    Widget chip(String label, _Source? value) {
      final on = _filter == value;
      return Padding(
        padding: const EdgeInsets.only(right: 8),
        child: Semantics(
          button: true,
          selected: on,
          child: Material(
            color: on ? c.text : c.surface,
            shape: StadiumBorder(side: BorderSide(color: on ? c.text : c.line)),
            child: InkWell(
              customBorder: const StadiumBorder(),
              onTap: () => setState(() => _filter = value),
              child: Container(
                height: 40,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                alignment: Alignment.center,
                child: Text(
                  label,
                  style: StockpileFonts.satoshi(
                    fontSize: 14,
                    fontWeight: on ? FontWeight.w600 : FontWeight.w400,
                    color: on ? c.surface : c.text,
                  ),
                ),
              ),
            ),
          ),
        ),
      );
    }

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          chip('All', null),
          for (final s in _Source.values)
            if (present.contains(s))
              chip(s == _Source.online ? 'Online orders' : s.label, s),
        ],
      ),
    );
  }

  List<Widget> _days(ShopColors c, List<_Purchase> shown) {
    final out = <Widget>[];
    String? day;
    for (final p in shown) {
      final d = _day(p.at);
      if (d != day) {
        day = d;
        out.add(
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 20, 4, 8),
            child: Text(
              d,
              style: StockpileFonts.satoshi(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: c.muted,
              ),
            ),
          ),
        );
      } else {
        out.add(const SizedBox(height: 10));
      }
      out.add(_card(c, p));
    }
    return out;
  }

  Widget _card(ShopColors c, _Purchase p) {
    return ShopCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(p.source.icon, size: 18, color: c.accent),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  p.source.label,
                  style: StockpileFonts.satoshi(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: c.text,
                  ),
                ),
              ),
              if (p.at != null)
                Text(
                  formatTimeOfDay(p.at),
                  style: StockpileFonts.satoshi(fontSize: 12, color: c.muted),
                ),
            ],
          ),
          for (final s in p.lines)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Row(
                children: [
                  ProductTile(s.itemName, size: 36),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          s.itemName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: StockpileFonts.satoshi(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            color: c.text,
                          ),
                        ),
                        Text(
                          s.quantity == 1
                              ? _m(s.price)
                              : '${s.quantity} × ${_m(s.price)}',
                          style: StockpileFonts.satoshi(
                            fontSize: 12,
                            color: c.muted,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Text(
                    _m(s.price * s.quantity),
                    style: StockpileFonts.satoshi(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: c.text,
                    ),
                  ),
                ],
              ),
            ),
          if (p.lines.length > 1) ...[
            const SizedBox(height: 12),
            Divider(height: 1, color: c.line),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: Text(
                    '${p.items} item${p.items == 1 ? '' : 's'}',
                    style: StockpileFonts.satoshi(fontSize: 13, color: c.muted),
                  ),
                ),
                Text(
                  _m(p.total),
                  style: StockpileFonts.satoshi(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: c.text,
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}
