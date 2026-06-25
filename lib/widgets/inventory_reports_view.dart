// lib/widgets/inventory_reports_view.dart
// Shared In/Out/Borrow Reports view — used by both the Inventory role
// and the Admin role (so admin sees the exact same reports page).

import 'package:flutter/material.dart';
import 'package:lzcas/theme.dart';
import 'package:lzcas/utils/fonts.dart';
import 'package:lzcas/db/db.dart';

/// Shared read-only reports view showing stock movement history.
/// Used identically by Inventory Dashboard and Admin Dashboard.
class InventoryReportsView extends StatefulWidget {
  const InventoryReportsView({super.key});

  @override
  State<InventoryReportsView> createState() => _InventoryReportsViewState();
}

class _InventoryReportsViewState extends State<InventoryReportsView> {
  final List<Map<String, dynamic>> _movements = [];
  int _activeBorrowUnits = 0;
  int _overdueBorrowCount = 0;
  int _stockInTotal = 0;
  int _stockOutTotal = 0;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() => _loading = true);
    try {
      final borrows = await repository.fetchBorrows();
      final sales = await repository.fetchSales();
      final members = await repository.fetchMembers();
      final stockMovements = await repository.fetchStockMovements();

      final now = DateTime.now();
      int activeCount = 0;
      int overdueCount = 0;
      int stockIn = 0;
      int stockOut = 0;

      final movements = <Map<String, dynamic>>[];

      // Stock movements
      for (final sm in stockMovements) {
        final isIn = sm.movementType == 'stock_in';
        final isNewProduct = sm.reason == 'new_product';
        if (isIn) {
          stockIn += sm.quantity;
        } else {
          stockOut += sm.quantity;
        }
        movements.add({
          'type': isNewProduct
              ? 'New Product'
              : (isIn ? 'Stock In' : 'Stock Out'),
          'item': sm.itemName,
          'qty': sm.quantity,
          'user': isNewProduct ? '' : (sm.reason ?? ''),
          'date': sm.createdAt ?? now,
          'isOverdue': false,
          'remaining': 0,
        });
      }

      for (final b in borrows) {
        final outstanding = b.outstandingQuantity;
        if (outstanding > 0) {
          activeCount += outstanding;
          if (b.dueDate.isBefore(now)) overdueCount++;
        }

        final mem = members.cast<Member?>().firstWhere(
          (m) => m?.id == b.memberId,
          orElse: () => null,
        );
        final memName = mem != null
            ? '${mem.firstName ?? ''} ${mem.lastName ?? ''}'.trim()
            : 'Member #${b.memberId}';

        movements.add({
          'type': 'Borrow',
          'item': b.itemName,
          'qty': b.quantity,
          'user': memName,
          'date': b.borrowedAt ?? now,
          'isOverdue': b.dueDate.isBefore(now) && outstanding > 0,
          'remaining': outstanding,
        });

        if (b.quantityReturned > 0) {
          movements.add({
            'type': 'Return',
            'item': b.itemName,
            'qty': b.quantityReturned,
            'user': memName,
            'date': b.settledAt ?? now,
            'isOverdue': false,
            'remaining': 0,
          });
        }

        if (b.quantityRemitted > 0) {
          movements.add({
            'type': 'Remit',
            'item': b.itemName,
            'qty': b.quantityRemitted,
            'user': memName,
            'date': b.settledAt ?? now,
            'isOverdue': false,
            'remaining': 0,
          });
        }
      }

      // Add sales as events
      for (final s in sales) {
        final mem = members.cast<Member?>().firstWhere(
          (m) => m?.id == s.buyerId,
          orElse: () => null,
        );
        final memName = mem != null
            ? '${mem.firstName ?? ''} ${mem.lastName ?? ''}'.trim()
            : null;

        movements.add({
          'type': 'Sale',
          'item': s.itemName,
          'qty': s.quantity,
          'user': memName ?? 'Walk-in',
          'date': s.timestamp ?? now,
          'isOverdue': false,
          'remaining': 0,
        });
      }

      // Sort by date descending
      movements.sort((a, b) {
        final aDate = a['date'] as DateTime;
        final bDate = b['date'] as DateTime;
        return bDate.compareTo(aDate);
      });

      if (!mounted) return;
      setState(() {
        _activeBorrowUnits = activeCount;
        _overdueBorrowCount = overdueCount;
        _stockInTotal = stockIn;
        _stockOutTotal = stockOut;
        _movements.clear();
        _movements.addAll(movements.take(50));
        _loading = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  String _formatDate(DateTime dt) {
    return '${dt.year}-${dt.month.toString().padLeft(2, '0')}'
        '-${dt.day.toString().padLeft(2, '0')} '
        '${dt.hour.toString().padLeft(2, '0')}'
        ':${dt.minute.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }

    return RefreshIndicator(
      onRefresh: _loadData,
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Summary cards
            Row(
              children: [
                Expanded(
                  child: _ReportStatCard(
                    icon: Icons.arrow_downward_rounded,
                    label: 'Stock In',
                    value: '$_stockInTotal',
                    color: StockpileColors.success,
                    isDark: isDark,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _ReportStatCard(
                    icon: Icons.arrow_upward_rounded,
                    label: 'Stock Out',
                    value: '$_stockOutTotal',
                    color: StockpileColors.error500,
                    isDark: isDark,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _ReportStatCard(
                    icon: Icons.shopping_cart_rounded,
                    label: 'Sales',
                    value:
                        '${_movements.where((m) => m['type'] == 'Sale').length}',
                    color: StockpileColors.primary900,
                    isDark: isDark,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _ReportStatCard(
                    icon: Icons.swap_horiz_rounded,
                    label: 'Borrowed',
                    value: '$_activeBorrowUnits',
                    color: StockpileColors.secondary500,
                    isDark: isDark,
                    subtitle: _overdueBorrowCount > 0
                        ? '$_overdueBorrowCount overdue'
                        : null,
                    subtitleColor: StockpileColors.error500,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),

            // Read-only movement log
            Text(
              'Movement History',
              style: StockpileFonts.satoshi(
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: isDark
                    ? StockpileColors.darkTextPrimary
                    : StockpileColors.darkText,
              ),
            ),
            const SizedBox(height: 12),

            if (_movements.isEmpty)
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(40),
                decoration: BoxDecoration(
                  color: isDark
                      ? StockpileColors.darkSurface
                      : StockpileColors.surface,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: isDark
                        ? StockpileColors.darkDivider
                        : StockpileColors.divider,
                  ),
                ),
                child: Column(
                  children: [
                    Icon(
                      Icons.inventory_2_outlined,
                      size: 48,
                      color: isDark
                          ? StockpileColors.darkTextMuted
                          : StockpileColors.mutedText,
                    ),
                    const SizedBox(height: 12),
                    Text(
                      'No movements recorded yet.',
                      style: StockpileFonts.satoshi(
                        fontSize: 15,
                        color: isDark
                            ? StockpileColors.darkTextMuted
                            : StockpileColors.mutedText,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Stock adjustments, sales, borrows, returns, and remittances will appear here.',
                      style: StockpileFonts.satoshi(
                        fontSize: 13,
                        color: isDark
                            ? StockpileColors.darkTextMuted
                            : StockpileColors.mutedText,
                      ),
                    ),
                  ],
                ),
              )
            else
              ...List.generate(_movements.length, (i) {
                final m = _movements[i];
                final type = m['type'] as String;
                final isOverdue = m['isOverdue'] as bool? ?? false;

                Color typeColor;
                IconData typeIcon;
                switch (type) {
                  case 'New Product':
                    typeColor = StockpileColors.primary900;
                    typeIcon = Icons.add_box_rounded;
                    break;
                  case 'Stock In':
                    typeColor = StockpileColors.success;
                    typeIcon = Icons.arrow_downward_rounded;
                    break;
                  case 'Stock Out':
                    typeColor = StockpileColors.error500;
                    typeIcon = Icons.arrow_upward_rounded;
                    break;
                  case 'Borrow':
                    typeColor = isOverdue
                        ? StockpileColors.error500
                        : StockpileColors.secondary500;
                    typeIcon = Icons.swap_horiz_rounded;
                    break;
                  case 'Return':
                    typeColor = StockpileColors.success;
                    typeIcon = Icons.assignment_return_rounded;
                    break;
                  case 'Remit':
                    typeColor = Colors.purple;
                    typeIcon = Icons.payments_rounded;
                    break;
                  default:
                    typeColor = StockpileColors.primary900;
                    typeIcon = Icons.shopping_cart_rounded;
                }

                return Card(
                  margin: const EdgeInsets.only(bottom: 6),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                    side: isOverdue
                        ? BorderSide(
                            color: StockpileColors.error500.withAlpha(100),
                          )
                        : BorderSide.none,
                  ),
                  child: ListTile(
                    leading: CircleAvatar(
                      backgroundColor: typeColor.withAlpha(30),
                      child: Icon(typeIcon, color: typeColor, size: 20),
                    ),
                    title: Text(
                      m['item'] as String? ?? '',
                      style: StockpileFonts.satoshi(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: isDark
                            ? StockpileColors.darkTextPrimary
                            : StockpileColors.darkText,
                      ),
                    ),
                    subtitle: Text(
                      '${m['type']} · ${m['qty']} units · '
                      '${_formatDate(m['date'] as DateTime)}',
                      style: StockpileFonts.satoshi(
                        fontSize: 12,
                        color: isDark
                            ? StockpileColors.darkTextMuted
                            : StockpileColors.mutedText,
                      ),
                    ),
                    trailing: Text(
                      m['user'] as String? ?? '',
                      style: StockpileFonts.satoshi(
                        fontSize: 12,
                        color: isDark
                            ? StockpileColors.darkTextBody
                            : StockpileColors.bodyText,
                      ),
                    ),
                  ),
                );
              }),
          ],
        ),
      ),
    );
  }
}

// ─── Shared Stat Card for Reports ───────────────────────────────────────────

class _ReportStatCard extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final Color color;
  final bool isDark;
  final String? subtitle;
  final Color? subtitleColor;

  const _ReportStatCard({
    required this.icon,
    required this.label,
    required this.value,
    required this.color,
    required this.isDark,
    this.subtitle,
    this.subtitleColor,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: isDark ? StockpileColors.darkSurface : StockpileColors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: isDark ? StockpileColors.darkDivider : StockpileColors.divider,
        ),
      ),
      child: Column(
        children: [
          Icon(icon, color: color, size: 24),
          const SizedBox(height: 6),
          Text(
            value,
            style: StockpileFonts.satoshi(
              fontSize: 18,
              fontWeight: FontWeight.w800,
              color: isDark
                  ? StockpileColors.darkTextPrimary
                  : StockpileColors.darkText,
            ),
          ),
          Text(
            label,
            style: StockpileFonts.satoshi(
              fontSize: 11,
              color: isDark
                  ? StockpileColors.darkTextMuted
                  : StockpileColors.mutedText,
            ),
          ),
          if (subtitle != null) ...[
            const SizedBox(height: 2),
            Text(
              subtitle!,
              style: StockpileFonts.satoshi(
                fontSize: 10,
                fontWeight: FontWeight.w700,
                color: subtitleColor ?? StockpileColors.error500,
              ),
            ),
          ],
        ],
      ),
    );
  }
}
