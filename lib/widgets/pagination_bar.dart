import 'package:flutter/material.dart';
import '../theme.dart';
import '../utils/fonts.dart';

/// A responsive pagination bar with Previous / Page Numbers / Next.
///
/// On narrow screens (< 400px), it collapses to a compact `[<] 3/15 [>]` layout.
class PaginationBar extends StatelessWidget {
  final int currentPage;
  final int totalPages;
  final ValueChanged<int> onPageChanged;
  final bool compact;

  const PaginationBar({
    super.key,
    required this.currentPage,
    required this.totalPages,
    required this.onPageChanged,
    this.compact = false,
  });

  @override
  Widget build(BuildContext context) {
    if (totalPages <= 1) return const SizedBox.shrink();

    final isDark = Theme.of(context).brightness == Brightness.dark;
    final fg = isDark ? StockpileColors.darkTextBody : StockpileColors.bodyText;
    final activeBg = isDark
        ? StockpileColors.primary900.withAlpha(40)
        : StockpileColors.primary900.withAlpha(25);
    final activeFg = isDark
        ? StockpileColors.primary500
        : StockpileColors.primary900;

    const btnSize = Size(38, 38);
    const radius = BorderRadius.all(Radius.circular(8));

    Widget pageBtn(int page, {bool active = false}) {
      return SizedBox(
        width: btnSize.width,
        height: btnSize.height,
        child: Material(
          color: active ? activeBg : Colors.transparent,
          borderRadius: radius,
          child: InkWell(
            borderRadius: radius,
            onTap: () => onPageChanged(page),
            child: Center(
              child: Text(
                '$page',
                style: StockpileFonts.satoshi(
                  fontSize: 13,
                  fontWeight: active ? FontWeight.w700 : FontWeight.w500,
                  color: active ? activeFg : fg,
                ),
              ),
            ),
          ),
        ),
      );
    }

    Widget arrow(IconData icon, {required bool enabled, required int target}) {
      return SizedBox(
        width: btnSize.width,
        height: btnSize.height,
        child: Material(
          color: Colors.transparent,
          borderRadius: radius,
          child: InkWell(
            borderRadius: radius,
            onTap: enabled ? () => onPageChanged(target) : null,
            child: Icon(icon, size: 20, color: enabled ? fg : fg.withAlpha(80)),
          ),
        ),
      );
    }

    // Compact mode: < 1/5 >
    if (compact) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            arrow(
              Icons.chevron_left,
              enabled: currentPage > 1,
              target: currentPage - 1,
            ),
            const SizedBox(width: 12),
            Text(
              '$currentPage / $totalPages',
              style: StockpileFonts.satoshi(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: fg,
              ),
            ),
            const SizedBox(width: 12),
            arrow(
              Icons.chevron_right,
              enabled: currentPage < totalPages,
              target: currentPage + 1,
            ),
          ],
        ),
      );
    }

    // Full mode: [<] 1 2 ... 5 [>]
    final pages = <Widget>[
      arrow(
        Icons.chevron_left,
        enabled: currentPage > 1,
        target: currentPage - 1,
      ),
    ];

    // Build page number list with ellipsis
    const maxVisible = 5;
    if (totalPages <= maxVisible + 2) {
      for (var i = 1; i <= totalPages; i++) {
        pages.add(pageBtn(i, active: i == currentPage));
      }
    } else {
      pages.add(pageBtn(1, active: currentPage == 1));

      if (currentPage > 3) {
        pages.add(
          const SizedBox(
            width: 38,
            height: 38,
            child: Center(child: Text('\u2026')),
          ),
        );
      }

      final start = (currentPage - 1).clamp(2, totalPages - 2);
      final end = (currentPage + 1).clamp(3, totalPages - 1);
      for (var i = start; i <= end; i++) {
        pages.add(pageBtn(i, active: i == currentPage));
      }

      if (currentPage < totalPages - 2) {
        pages.add(
          const SizedBox(
            width: 38,
            height: 38,
            child: Center(child: Text('\u2026')),
          ),
        );
      }

      pages.add(pageBtn(totalPages, active: currentPage == totalPages));
    }

    pages.add(
      arrow(
        Icons.chevron_right,
        enabled: currentPage < totalPages,
        target: currentPage + 1,
      ),
    );

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
      child: Row(mainAxisAlignment: MainAxisAlignment.center, children: pages),
    );
  }
}
