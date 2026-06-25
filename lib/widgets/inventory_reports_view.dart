// lib/widgets/inventory_reports_view.dart
// Shared In/Out/Borrow Reports view — used by both the Inventory role
// and the Admin role (so admin sees the exact same reports page).

import 'package:flutter/material.dart';
import 'package:lzcas/theme.dart';
import 'package:lzcas/utils/fonts.dart';

/// Shared read-only reports view showing stock movement history.
/// Used identically by Inventory Dashboard and Admin Dashboard.
class InventoryReportsView extends StatefulWidget {
  const InventoryReportsView({super.key});

  @override
  State<InventoryReportsView> createState() => _InventoryReportsViewState();
}

class _InventoryReportsViewState extends State<InventoryReportsView> {
  final List<Map<String, dynamic>> _movements = [];

  @override
  void initState() {
    super.initState();
    _loadMovements();
  }

  Future<void> _loadMovements() async {
    // TODO: Replace with actual data from repository.fetchSales() or a
    // dedicated stock movement log.
    setState(() {
      // Populate with placeholder data for the UI wireframe.
    });
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return SingleChildScrollView(
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
                  value: '—',
                  color: StockpileColors.success,
                  isDark: isDark,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _ReportStatCard(
                  icon: Icons.arrow_upward_rounded,
                  label: 'Stock Out',
                  value: '—',
                  color: StockpileColors.error500,
                  isDark: isDark,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _ReportStatCard(
                  icon: Icons.swap_horiz_rounded,
                  label: 'Borrowed',
                  value: '—',
                  color: StockpileColors.secondary500,
                  isDark: isDark,
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
                    'Stock in, out, and borrow activity will appear here.',
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
              return ListTile(
                leading: CircleAvatar(
                  backgroundColor: StockpileColors.primary100,
                  child: Icon(
                    Icons.swap_vert_rounded,
                    color: StockpileColors.primary700,
                  ),
                ),
                title: Text(m['item'] ?? ''),
                subtitle: Text(
                  '${m['type']} · ${m['qty']} units · ${m['date']}',
                ),
                trailing: Text(m['user'] ?? ''),
              );
            }),
        ],
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

  const _ReportStatCard({
    required this.icon,
    required this.label,
    required this.value,
    required this.color,
    required this.isDark,
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
        ],
      ),
    );
  }
}
