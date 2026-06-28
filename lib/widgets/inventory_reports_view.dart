// lib/widgets/inventory_reports_view.dart
// Shared In/Out/Borrow Reports view — used by both the Inventory role
// and the Admin role (so admin sees the exact same reports page).

import 'package:flutter/material.dart';
import 'package:lzcas/theme.dart';
import 'package:lzcas/utils/fonts.dart';
import 'package:lzcas/utils/animations.dart';
import 'package:lzcas/utils/formatters.dart';
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

  // ── Filters ──────────────────────────────────────────────
  DateTimeRange _dateRange = DateTimeRange(
    start: DateTime.now().subtract(const Duration(days: 30)),
    end: DateTime.now(),
  );
  String _typeFilter = 'All';
  static const _pageSize = 25;
  int _visibleCount = 25;

  static const _typeOptions = [
    'All',
    'Stock In',
    'Stock Out',
    'New Product',
    'Borrow',
    'Return',
    'Remit',
    'Sale',
  ];

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() => _loading = true);
    _visibleCount = _pageSize;
    try {
      final supabase = repository.supabase;
      final start = _dateRange.start.toIso8601String();
      final end = _dateRange.end
          .add(const Duration(days: 1))
          .toIso8601String(); // inclusive end

      // Fetch only date-filtered data from Supabase
      final borrowsRaw = await supabase
          .from('borrows')
          .select()
          .gte('borrowed_at', start)
          .lt('borrowed_at', end);
      final salesRaw = await supabase
          .from('sales')
          .select()
          .gte('timestamp', start)
          .lt('timestamp', end);
      final membersData = await supabase.from('members').select();
      final profilesData = await supabase
          .from('profiles')
          .select('id, username');
      final stockRaw = await supabase
          .from('stock_movements')
          .select()
          .gte('created_at', start)
          .lt('created_at', end);

      final borrows = (borrowsRaw as List)
          .map((j) => Borrow.fromJson(j as Map<String, dynamic>))
          .toList();
      final sales = (salesRaw as List)
          .map((j) => Sale.fromJson(j as Map<String, dynamic>))
          .toList();
      final members = (membersData as List)
          .map((j) => Member.fromJson(j as Map<String, dynamic>))
          .toList();
      final profiles = Map<String, String>.fromEntries(
        (profilesData as List).map(
          (p) => MapEntry(
            p['id'] as String,
            p['username'] as String? ?? 'Unknown',
          ),
        ),
      );
      final stockMovements = (stockRaw as List)
          .map((j) => StockMovement.fromJson(j as Map<String, dynamic>))
          .toList();

      final now = DateTime.now();
      int activeCount = 0;
      int overdueCount = 0;
      int stockIn = 0;
      int stockOut = 0;

      final movements = <Map<String, dynamic>>[];

      for (final sm in stockMovements) {
        final isIn = sm.movementType == 'stock_in';
        final isNewProduct = sm.reason == 'new_product';
        if (isIn)
          stockIn += sm.quantity;
        else
          stockOut += sm.quantity;

        String userLabel = '';
        String? reasonLabel;
        if (!isNewProduct) {
          reasonLabel = sm.reason;
          // For stock out, show who requested it instead of the reason
          if (!isIn && sm.userId != null) {
            userLabel = profiles[sm.userId] ?? 'Unknown';
          } else {
            userLabel = sm.reason ?? '';
          }
        }

        movements.add({
          'type': isNewProduct
              ? 'New Product'
              : (isIn ? 'Stock In' : 'Stock Out'),
          'item': sm.itemName,
          'qty': sm.quantity,
          'user': userLabel,
          'reason': reasonLabel,
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
        if (b.quantityReturned > 0)
          movements.add({
            'type': 'Return',
            'item': b.itemName,
            'qty': b.quantityReturned,
            'user': memName,
            'date': b.settledAt ?? now,
            'isOverdue': false,
            'remaining': 0,
          });
        if (b.quantityRemitted > 0)
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

      for (final s in sales) {
        final mem = members.cast<Member?>().firstWhere(
          (m) => m?.id == s.buyerId,
          orElse: () => null,
        );
        movements.add({
          'type': 'Sale',
          'item': s.itemName,
          'qty': s.quantity,
          'user': mem != null
              ? '${mem.firstName ?? ''} ${mem.lastName ?? ''}'.trim()
              : 'Walk-in',
          'date': s.timestamp ?? now,
          'isOverdue': false,
          'remaining': 0,
        });
      }

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
        _movements.addAll(movements);
        _loading = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _loadMore() {
    setState(() => _visibleCount += _pageSize);
  }

  Future<void> _pickDateRange() async {
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: DateTime.now().add(const Duration(days: 1)),
      initialDateRange: _dateRange,
    );
    if (picked != null) {
      setState(() => _dateRange = picked);
      _loadData();
    }
  }

  String _formatDate(DateTime dt) {
    return '${dt.year}-${dt.month.toString().padLeft(2, '0')}'
        '-${dt.day.toString().padLeft(2, '0')}';
  }

  String _formatDateTime(DateTime dt) {
    return formatDisplayDate(dt);
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    if (_loading) {
      return const Padding(
        padding: EdgeInsets.all(16),
        child: SkeletonList(count: 4),
      );
    }

    // Apply type filter
    var filtered = _movements;
    if (_typeFilter != 'All') {
      filtered = filtered.where((m) => m['type'] == _typeFilter).toList();
    }
    final visible = filtered.take(_visibleCount).toList();
    final hasMore = _visibleCount < filtered.length;

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
            const SizedBox(height: 16),

            // ── Filter Bar ─────────────────────────────────
            Row(
              children: [
                // Date range button
                Expanded(
                  flex: 2,
                  child: InkWell(
                    onTap: _pickDateRange,
                    borderRadius: BorderRadius.circular(12),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 10,
                      ),
                      decoration: BoxDecoration(
                        color: isDark
                            ? StockpileColors.darkInputBg
                            : StockpileColors.inputBg,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: isDark
                              ? StockpileColors.darkDivider
                              : StockpileColors.divider,
                        ),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            Icons.date_range,
                            size: 18,
                            color: isDark
                                ? StockpileColors.darkTextMuted
                                : StockpileColors.mutedText,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              '${_formatDate(_dateRange.start)} → ${_formatDate(_dateRange.end)}',
                              style: StockpileFonts.satoshi(
                                fontSize: 13,
                                color: isDark
                                    ? StockpileColors.darkTextPrimary
                                    : StockpileColors.darkText,
                              ),
                            ),
                          ),
                          Icon(
                            Icons.arrow_drop_down,
                            color: isDark
                                ? StockpileColors.darkTextMuted
                                : StockpileColors.mutedText,
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                // Type filter dropdown
                Expanded(
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    decoration: BoxDecoration(
                      color: isDark
                          ? StockpileColors.darkInputBg
                          : StockpileColors.inputBg,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: isDark
                            ? StockpileColors.darkDivider
                            : StockpileColors.divider,
                      ),
                    ),
                    child: DropdownButtonHideUnderline(
                      child: DropdownButton<String>(
                        value: _typeFilter,
                        isExpanded: true,
                        icon: Icon(
                          Icons.arrow_drop_down,
                          color: isDark
                              ? StockpileColors.darkTextMuted
                              : StockpileColors.mutedText,
                        ),
                        style: StockpileFonts.satoshi(
                          fontSize: 13,
                          color: isDark
                              ? StockpileColors.darkTextPrimary
                              : StockpileColors.darkText,
                        ),
                        items: _typeOptions.map((t) {
                          return DropdownMenuItem(value: t, child: Text(t));
                        }).toList(),
                        onChanged: (v) {
                          if (v != null) {
                            setState(() {
                              _typeFilter = v;
                              _visibleCount = _pageSize;
                            });
                          }
                        },
                      ),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),

            // ── Movement History ────────────────────────────
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
            const SizedBox(height: 4),
            Text(
              '${filtered.length} entries',
              style: StockpileFonts.satoshi(
                fontSize: 12,
                color: isDark
                    ? StockpileColors.darkTextMuted
                    : StockpileColors.mutedText,
              ),
            ),
            const SizedBox(height: 12),

            if (visible.isEmpty)
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
                      'No movements found.',
                      style: StockpileFonts.satoshi(
                        fontSize: 15,
                        color: isDark
                            ? StockpileColors.darkTextMuted
                            : StockpileColors.mutedText,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Try adjusting the date range or type filter.',
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
            else ...[
              ...List.generate(visible.length, (i) {
                final m = visible[i];
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
                return StaggeredItem(
                  index: i,
                  child: Card(
                    margin: const EdgeInsets.only(bottom: 6),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: ListTile(
                      leading: CircleAvatar(
                        backgroundColor: typeColor.withAlpha(25),
                        child: Icon(typeIcon, color: typeColor, size: 20),
                      ),
                      title: Text(
                        '${m['qty']}× ${m['item']}',
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                      subtitle: Text(
                        (m['user'] as String?)?.isNotEmpty == true
                            ? '${m['type']} · ${m['user']} · ${_formatDateTime(m['date'] as DateTime)}'
                            : '${m['type']} · ${_formatDateTime(m['date'] as DateTime)}',
                        style: const TextStyle(fontSize: 12),
                      ),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (isOverdue)
                            const Padding(
                              padding: EdgeInsets.only(right: 8),
                              child: Text(
                                'OVERDUE',
                                style: TextStyle(
                                  color: StockpileColors.error500,
                                  fontSize: 10,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                          if ((m['remaining'] as int) > 0)
                            Padding(
                              padding: const EdgeInsets.only(right: 8),
                              child: Text(
                                '${m['remaining']} left',
                                style: TextStyle(
                                  color: Colors.orange.shade700,
                                  fontSize: 11,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          if ((m['reason'] as String?)?.isNotEmpty == true)
                            Tooltip(
                              message: m['reason'] as String,
                              child: GestureDetector(
                                onTap: () => showDialog<void>(
                                  context: context,
                                  builder: (ctx) => AlertDialog(
                                    title: const Text('Reason'),
                                    content: Text(m['reason'] as String),
                                    actions: [
                                      TextButton(
                                        onPressed: () => Navigator.pop(ctx),
                                        child: const Text('OK'),
                                      ),
                                    ],
                                  ),
                                ),
                                child: Container(
                                  width: 24,
                                  height: 24,
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    color: StockpileColors.mutedText.withAlpha(
                                      30,
                                    ),
                                  ),
                                  child: const Icon(
                                    Icons.info_outline,
                                    size: 16,
                                  ),
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                );
              }),
              if (hasMore)
                Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: SizedBox(
                    width: double.infinity,
                    child: OutlinedButton(
                      onPressed: _loadMore,
                      child: Text(
                        'Load More (${_visibleCount - _pageSize + 1}–${_visibleCount > filtered.length ? filtered.length : _visibleCount} of ${filtered.length})',
                      ),
                    ),
                  ),
                ),
            ],
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
