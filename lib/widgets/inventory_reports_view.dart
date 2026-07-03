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
  String _period = 'Monthly'; // Weekly, Monthly, Yearly
  String _typeFilter = 'All';
  static const _pageSize = 25;
  int _displayPage = 1;

  static const _periodOptions = ['Weekly', 'Monthly', 'Yearly'];
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

  /// Compute start and end UTC dates from the selected period,
  /// using Philippine time (UTC+8) for the period boundaries.
  DateTimeRange _computeDateRange() {
    final utcNow = DateTime.now().toUtc();

    // Philippine time = UTC + 8h — use this to find the correct PHT date components
    final phtNow = utcNow.add(const Duration(hours: 8));

    // Start of the period expressed as a PHT date (year/month/day correct for PH)
    final DateTime phtStart = switch (_period) {
      'Weekly' => DateTime(
        phtNow.year,
        phtNow.month,
        phtNow.day - (phtNow.weekday % 7),
      ),
      'Yearly' => DateTime(phtNow.year, 1, 1),
      _ => DateTime(phtNow.year, phtNow.month, 1),
    };

    // Convert PHT midnight → UTC: use DateTime.utc() to avoid local timezone interference,
    // then subtract 8h since PHT midnight = previous day 16:00 UTC.
    final utcStart = DateTime.utc(
      phtStart.year,
      phtStart.month,
      phtStart.day,
    ).subtract(const Duration(hours: 8));

    return DateTimeRange(start: utcStart, end: utcNow);
  }

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() => _loading = true);
    _displayPage = 1;
    try {
      final supabase = repository.supabase;
      final range = _computeDateRange();
      final start = range.start.toIso8601String();
      final end = range.end
          .add(const Duration(days: 1))
          .toIso8601String(); // inclusive end

      // Fetch only date-filtered data from Supabase.
      // Borrows are fetched unfiltered because a borrow may have been
      // created outside the period but returned/remitted within it.
      final borrowsRaw = await supabase.from('borrows').select();
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
        // Use stored member_name, fall back to member lookup
        final memName =
            b.memberName ??
            ((() {
              final mem = members.cast<Member?>().firstWhere(
                (m) => m?.id == b.memberId,
                orElse: () => null,
              );
              return mem != null
                  ? '${mem.firstName ?? ''} ${mem.lastName ?? ''}'.trim()
                  : 'Member #${b.memberId}';
            })());

        // Only show borrow entries if the borrow was created within the period
        if (b.borrowedAt != null &&
            b.borrowedAt!.isAfter(range.start) &&
            b.borrowedAt!.isBefore(range.end)) {
          movements.add({
            'type': 'Borrow',
            'item': b.itemName,
            'qty': b.quantity,
            'user': memName,
            'date': b.borrowedAt!,
            'isOverdue': b.dueDate.isBefore(now) && outstanding > 0,
            'remaining': outstanding,
          });
        }

        // Return/Remit entries show when the settlement happened within the period
        if (b.quantityReturned > 0 &&
            b.settledAt != null &&
            b.settledAt!.isAfter(range.start) &&
            b.settledAt!.isBefore(range.end)) {
          movements.add({
            'type': 'Return',
            'item': b.itemName,
            'qty': b.quantityReturned,
            'user': memName,
            'date': b.settledAt!,
            'isOverdue': false,
            'remaining': 0,
          });
        }
        if (b.quantityRemitted > 0 &&
            b.settledAt != null &&
            b.settledAt!.isAfter(range.start) &&
            b.settledAt!.isBefore(range.end)) {
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

      for (final s in sales) {
        final userName =
            s.buyerName ??
            ((() {
              final mem = members.cast<Member?>().firstWhere(
                (m) => m?.id == s.buyerId,
                orElse: () => null,
              );
              return mem != null
                  ? '${mem.firstName ?? ''} ${mem.lastName ?? ''}'.trim()
                  : 'Walk-in';
            })());
        movements.add({
          'type': 'Sale',
          'item': s.itemName,
          'qty': s.quantity,
          'user': userName,
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

  String _formatDateTime(DateTime dt) {
    return formatDisplayDate(dt);
  }

  /// Shows a rich reason modal with movement context (type, item, user, date).
  void _showReasonModal(
    BuildContext context, {
    required String reason,
    required String type,
    required String item,
    required String user,
    required DateTime date,
    required bool isDark,
  }) {
    final typeInfo = _typeMeta(type);

    showDialog<void>(
      context: context,
      builder: (ctx) {
        final d = isDark;
        final surface = d ? StockpileColors.darkSurface : Colors.white;
        final textPrimary = d
            ? StockpileColors.darkTextPrimary
            : StockpileColors.darkText;
        final textMuted = d
            ? StockpileColors.darkTextMuted
            : StockpileColors.mutedText;
        final divider = d
            ? StockpileColors.darkDivider
            : StockpileColors.divider;

        return Dialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          backgroundColor: Colors.transparent,
          child: Container(
            constraints: const BoxConstraints(maxWidth: 400),
            decoration: BoxDecoration(
              color: surface,
              borderRadius: BorderRadius.circular(20),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withAlpha(d ? 60 : 20),
                  blurRadius: 24,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // ── Header ──────────────────────────────────────────
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.fromLTRB(20, 20, 16, 16),
                  decoration: BoxDecoration(
                    color: typeInfo.color.withAlpha(15),
                    borderRadius: const BorderRadius.only(
                      topLeft: Radius.circular(20),
                      topRight: Radius.circular(20),
                    ),
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 40,
                        height: 40,
                        decoration: BoxDecoration(
                          color: typeInfo.color.withAlpha(30),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Icon(
                          typeInfo.icon,
                          color: typeInfo.color,
                          size: 22,
                        ),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              typeInfo.label,
                              style: StockpileFonts.satoshi(
                                fontSize: 14,
                                fontWeight: FontWeight.w800,
                                color: typeInfo.color,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              item,
                              style: StockpileFonts.satoshi(
                                fontSize: 16,
                                fontWeight: FontWeight.w700,
                                color: textPrimary,
                              ),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),

                // ── Body ────────────────────────────────────────────
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 20, 20, 4),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Reason label
                      Text(
                        'Reason',
                        style: StockpileFonts.satoshi(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: textMuted,
                          letterSpacing: 0.8,
                        ),
                      ),
                      const SizedBox(height: 8),
                      // Reason content — styled card
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: d
                              ? StockpileColors.darkInputBg
                              : StockpileColors.inputBg,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: divider),
                        ),
                        child: Text(
                          reason,
                          style: StockpileFonts.satoshi(
                            fontSize: 14,
                            fontWeight: FontWeight.w500,
                            color: textPrimary,
                            height: 1.5,
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),

                      // Context row — user + date
                      Row(
                        children: [
                          Icon(
                            Icons.person_outline,
                            size: 16,
                            color: textMuted,
                          ),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              user.isNotEmpty ? user : 'System',
                              style: StockpileFonts.satoshi(
                                fontSize: 13,
                                color: textMuted,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Icon(
                            Icons.access_time_rounded,
                            size: 16,
                            color: textMuted,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            _formatDateTime(date),
                            style: StockpileFonts.satoshi(
                              fontSize: 13,
                              color: textMuted,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),

                // ── Divider + Close ─────────────────────────────────
                Divider(height: 1, color: divider),
                SizedBox(
                  width: double.infinity,
                  child: TextButton(
                    style: TextButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: const RoundedRectangleBorder(
                        borderRadius: BorderRadius.only(
                          bottomLeft: Radius.circular(20),
                          bottomRight: Radius.circular(20),
                        ),
                      ),
                    ),
                    onPressed: () => Navigator.pop(ctx),
                    child: Text(
                      'Close',
                      style: StockpileFonts.satoshi(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: typeInfo.color,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  /// Metadata for each movement type — icon, color, label.
  ({IconData icon, Color color, String label}) _typeMeta(String type) {
    switch (type) {
      case 'New Product':
        return (
          icon: Icons.add_box_rounded,
          color: StockpileColors.primary900,
          label: 'New Product',
        );
      case 'Stock In':
        return (
          icon: Icons.arrow_downward_rounded,
          color: StockpileColors.success,
          label: 'Stock In',
        );
      case 'Stock Out':
        return (
          icon: Icons.arrow_upward_rounded,
          color: StockpileColors.error500,
          label: 'Stock Out',
        );
      case 'Borrow':
        return (
          icon: Icons.swap_horiz_rounded,
          color: StockpileColors.secondary500,
          label: 'Borrow',
        );
      case 'Return':
        return (
          icon: Icons.assignment_return_rounded,
          color: StockpileColors.success,
          label: 'Return',
        );
      case 'Remit':
        return (
          icon: Icons.payments_rounded,
          color: Colors.purple,
          label: 'Remit',
        );
      default:
        return (
          icon: Icons.shopping_cart_rounded,
          color: StockpileColors.primary900,
          label: type,
        );
    }
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
    final start = (_displayPage - 1) * _pageSize;
    final visible = filtered.skip(start).take(_pageSize).toList();
    final totalPages = (filtered.length / _pageSize).ceil();

    return RefreshIndicator(
      onRefresh: _loadData,
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Summary cards
            LayoutBuilder(
              builder: (context, constraints) {
                final isMobile = constraints.maxWidth < 600;
                final cards = [
                  _ReportStatCard(
                    icon: Icons.arrow_downward_rounded,
                    label: 'Stock In',
                    value: '$_stockInTotal',
                    color: StockpileColors.success,
                    isDark: isDark,
                  ),
                  _ReportStatCard(
                    icon: Icons.arrow_upward_rounded,
                    label: 'Stock Out',
                    value: '$_stockOutTotal',
                    color: StockpileColors.error500,
                    isDark: isDark,
                  ),
                  _ReportStatCard(
                    icon: Icons.shopping_cart_rounded,
                    label: 'Sales',
                    value:
                        '${_movements.where((m) => m['type'] == 'Sale').length}',
                    color: StockpileColors.primary900,
                    isDark: isDark,
                  ),
                  _ReportStatCard(
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
                ];

                if (isMobile) {
                  return SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: [
                        for (int i = 0; i < cards.length; i++) ...[
                          if (i > 0) const SizedBox(width: 8),
                          SizedBox(width: 140, child: cards[i]),
                        ],
                      ],
                    ),
                  );
                }
                return Row(
                  children: [
                    for (int i = 0; i < cards.length; i++) ...[
                      if (i > 0) const SizedBox(width: 8),
                      Expanded(child: cards[i]),
                    ],
                  ],
                );
              },
            ),
            const SizedBox(height: 16),

            // ── Filter Bar ─────────────────────────────────
            Row(
              children: [
                // Period selector (Weekly / Monthly / Yearly)
                Expanded(
                  flex: 2,
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
                        value: _period,
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
                        items: _periodOptions.map((p) {
                          final icon = switch (p) {
                            'Weekly' => Icons.date_range_rounded,
                            'Yearly' => Icons.view_list_rounded,
                            _ => Icons.calendar_month_rounded,
                          };
                          return DropdownMenuItem(
                            value: p,
                            child: Row(
                              children: [
                                Icon(
                                  icon,
                                  size: 16,
                                  color: isDark
                                      ? StockpileColors.darkTextMuted
                                      : StockpileColors.mutedText,
                                ),
                                const SizedBox(width: 8),
                                Text(p),
                              ],
                            ),
                          );
                        }).toList(),
                        onChanged: (v) {
                          if (v != null) {
                            setState(() => _period = v);
                            _loadData();
                          }
                        },
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
                              _displayPage = 1;
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
                final typeInfo = _typeMeta(type);
                final typeColor = isOverdue
                    ? StockpileColors.error500
                    : typeInfo.color;
                final typeIcon = typeInfo.icon;
                final userName = (m['user'] as String?) ?? '';
                final remaining = m['remaining'] as int;
                final hasReason = (m['reason'] as String?)?.isNotEmpty == true;

                return StaggeredItem(
                  index: i,
                  child: Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Container(
                      decoration: BoxDecoration(
                        color: isDark
                            ? StockpileColors.darkSurface
                            : StockpileColors.surface,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: isDark
                              ? StockpileColors.darkDivider
                              : StockpileColors.divider,
                        ),
                        // Left accent strip via a border on the start side
                      ),
                      clipBehavior: Clip.antiAlias,
                      child: IntrinsicHeight(
                        child: Row(
                          children: [
                            // ── Left accent bar ────────────────────
                            Container(
                              width: 4,
                              decoration: BoxDecoration(
                                color: typeColor,
                                borderRadius: const BorderRadius.only(
                                  topLeft: Radius.circular(12),
                                  bottomLeft: Radius.circular(12),
                                ),
                              ),
                            ),
                            // ── Card body ──────────────────────────
                            Expanded(
                              child: Padding(
                                padding: const EdgeInsets.all(12),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    // Top row: type chip + quantity + info
                                    Row(
                                      children: [
                                        // Type badge
                                        Container(
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 8,
                                            vertical: 3,
                                          ),
                                          decoration: BoxDecoration(
                                            color: typeColor.withAlpha(20),
                                            borderRadius: BorderRadius.circular(
                                              8,
                                            ),
                                          ),
                                          child: Row(
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              Icon(
                                                typeIcon,
                                                size: 13,
                                                color: typeColor,
                                              ),
                                              const SizedBox(width: 4),
                                              Text(
                                                typeInfo.label,
                                                style: StockpileFonts.satoshi(
                                                  fontSize: 11,
                                                  fontWeight: FontWeight.w700,
                                                  color: typeColor,
                                                ),
                                              ),
                                              // Overdue pill
                                              if (isOverdue) ...[
                                                const SizedBox(width: 6),
                                                Container(
                                                  padding:
                                                      const EdgeInsets.symmetric(
                                                        horizontal: 5,
                                                        vertical: 1,
                                                      ),
                                                  decoration: BoxDecoration(
                                                    color: StockpileColors
                                                        .error500,
                                                    borderRadius:
                                                        BorderRadius.circular(
                                                          4,
                                                        ),
                                                  ),
                                                  child: Text(
                                                    'OVERDUE',
                                                    style: TextStyle(
                                                      color: Colors.white,
                                                      fontSize: 9,
                                                      fontWeight:
                                                          FontWeight.w800,
                                                    ),
                                                  ),
                                                ),
                                              ],
                                            ],
                                          ),
                                        ),
                                        const Spacer(),
                                        // Quantity badge
                                        Container(
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 10,
                                            vertical: 4,
                                          ),
                                          decoration: BoxDecoration(
                                            color: isDark
                                                ? StockpileColors.darkInputBg
                                                : StockpileColors.inputBg,
                                            borderRadius: BorderRadius.circular(
                                              10,
                                            ),
                                          ),
                                          child: Text(
                                            '×${m['qty']}',
                                            style: StockpileFonts.satoshi(
                                              fontSize: 15,
                                              fontWeight: FontWeight.w800,
                                              color: isDark
                                                  ? StockpileColors
                                                        .darkTextPrimary
                                                  : StockpileColors.darkText,
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 8),

                                    // Item name
                                    Text(
                                      m['item'] as String,
                                      style: StockpileFonts.satoshi(
                                        fontSize: 14,
                                        fontWeight: FontWeight.w600,
                                        color: isDark
                                            ? StockpileColors.darkTextPrimary
                                            : StockpileColors.darkText,
                                      ),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                    const SizedBox(height: 6),

                                    // Bottom row: user + date + remaining + reason
                                    Row(
                                      children: [
                                        Icon(
                                          Icons.person_outline,
                                          size: 14,
                                          color: isDark
                                              ? StockpileColors.darkTextMuted
                                              : StockpileColors.mutedText,
                                        ),
                                        const SizedBox(width: 4),
                                        Expanded(
                                          child: Text(
                                            userName.isNotEmpty
                                                ? userName
                                                : 'System',
                                            style: StockpileFonts.satoshi(
                                              fontSize: 12,
                                              color: isDark
                                                  ? StockpileColors
                                                        .darkTextMuted
                                                  : StockpileColors.mutedText,
                                            ),
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        ),
                                        const SizedBox(width: 6),
                                        Icon(
                                          Icons.access_time_rounded,
                                          size: 14,
                                          color: isDark
                                              ? StockpileColors.darkTextMuted
                                              : StockpileColors.mutedText,
                                        ),
                                        const SizedBox(width: 3),
                                        Text(
                                          _formatDateTime(
                                            m['date'] as DateTime,
                                          ),
                                          style: StockpileFonts.satoshi(
                                            fontSize: 11,
                                            color: isDark
                                                ? StockpileColors.darkTextMuted
                                                : StockpileColors.mutedText,
                                          ),
                                        ),
                                        // Remaining count chip
                                        if (remaining > 0) ...[
                                          const SizedBox(width: 8),
                                          Container(
                                            padding: const EdgeInsets.symmetric(
                                              horizontal: 7,
                                              vertical: 2,
                                            ),
                                            decoration: BoxDecoration(
                                              color: Colors.orange.shade100,
                                              borderRadius:
                                                  BorderRadius.circular(6),
                                            ),
                                            child: Text(
                                              '$remaining left',
                                              style: TextStyle(
                                                color: Colors.orange.shade800,
                                                fontSize: 10,
                                                fontWeight: FontWeight.w700,
                                              ),
                                            ),
                                          ),
                                        ],
                                        // Reason info button
                                        if (hasReason) ...[
                                          const SizedBox(width: 6),
                                          GestureDetector(
                                            onTap: () => _showReasonModal(
                                              context,
                                              reason: m['reason'] as String,
                                              type: type,
                                              item: m['item'] as String,
                                              user: userName,
                                              date: m['date'] as DateTime,
                                              isDark: isDark,
                                            ),
                                            child: Tooltip(
                                              message: m['reason'] as String,
                                              child: Container(
                                                width: 26,
                                                height: 26,
                                                decoration: BoxDecoration(
                                                  shape: BoxShape.circle,
                                                  color: typeColor.withAlpha(
                                                    25,
                                                  ),
                                                  border: Border.all(
                                                    color: typeColor.withAlpha(
                                                      60,
                                                    ),
                                                    width: 1,
                                                  ),
                                                ),
                                                child: Icon(
                                                  Icons.info_outline,
                                                  size: 15,
                                                  color: typeColor,
                                                ),
                                              ),
                                            ),
                                          ),
                                        ],
                                      ],
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                );
              }),
              if (totalPages > 1)
                Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      IconButton(
                        icon: const Icon(Icons.chevron_left),
                        onPressed: _displayPage > 1
                            ? () => setState(() => _displayPage--)
                            : null,
                      ),
                      Text(
                        '$_displayPage / $totalPages',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: isDark
                              ? StockpileColors.darkTextBody
                              : StockpileColors.bodyText,
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.chevron_right),
                        onPressed: _displayPage < totalPages
                            ? () => setState(() => _displayPage++)
                            : null,
                      ),
                    ],
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
