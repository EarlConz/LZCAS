// lib/widgets/staff_table.dart
//
// The staff tables (Members, Inventory, Transactions, Announcements) as
// redesigned 2026-10-04 (canvas "Staff Tables Redesign"), in the look of
// the calmer Delivery Orders page:
//
//   a count caption, the search box and the page's main button;
//   filter chips that carry their counts;
//   a white card with a 13 px uppercase header and 62 px rows, where a
//   click on a row opens it and ⋯ holds everything else;
//   rows that load as you scroll ("Showing 25 of 1,284") instead of a
//   page footer with arrows.
//
// On a phone the same rows sit in a card, two lines each with the number
// that matters on the right, and the main action floats bottom-right.

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import 'package:lzcas/theme.dart';
import 'package:lzcas/utils/fonts.dart';

/// Below this width a page shows the phone list instead of the table.
const kStaffTableBreakpoint = 900.0;

/// The page's colours, light or dark.
class StaffTableStyle {
  final bool dark;

  const StaffTableStyle._(this.dark);

  factory StaffTableStyle.of(BuildContext context) =>
      StaffTableStyle._(Theme.of(context).brightness == Brightness.dark);

  Color get surface => dark ? StockpileColors.darkSurface : StockpileColors.surface;
  Color get head => dark ? StockpileColors.darkInputBg : StockpileColors.tableHead;
  Color get line => dark ? StockpileColors.darkDivider : StockpileColors.divider;
  Color get rowLine => dark ? StockpileColors.darkDivider : const Color(0xFFEEEEF2);
  Color get text => dark ? StockpileColors.darkTextPrimary : StockpileColors.darkText;
  Color get body => dark ? StockpileColors.darkTextBody : StockpileColors.bodyText;

  /// Captions. Darker than the theme's muted grey, which fails contrast on
  /// white at these sizes.
  Color get muted => dark ? StockpileColors.darkTextMuted : const Color(0xFF6E6E7A);
  Color get input => dark ? StockpileColors.darkInputBg : StockpileColors.inputBg;
  Color get hover => dark ? Colors.white.withValues(alpha: 0.04) : const Color(0xFFFAFAFD);

  /// The orange of the main buttons and the chosen chip's text.
  static const accent = Color(0xFFB24800);
  Color get chipOnBg => dark ? accent.withValues(alpha: 0.35) : StockpileColors.primary50;
  Color get chipOnText => dark ? Colors.white : accent;
  Color get success => dark ? const Color(0xFF86EFAC) : const Color(0xFF15803D);
}

/// The colour families a pill can take.
enum StaffTone { neutral, orange, blue, green, red }

(Color bg, Color fg) _toneColors(StaffTone tone, bool dark) {
  if (dark) {
    return switch (tone) {
      StaffTone.neutral => (StockpileColors.darkInputBg, StockpileColors.darkTextBody),
      StaffTone.orange => (const Color(0xFFB24800).withValues(alpha: 0.35), const Color(0xFFFFC08A)),
      StaffTone.blue => (const Color(0xFF0029CC).withValues(alpha: 0.35), const Color(0xFFBCC1FF)),
      StaffTone.green => (const Color(0xFF15803D).withValues(alpha: 0.35), const Color(0xFF86EFAC)),
      StaffTone.red => (const Color(0xFFB91C1C).withValues(alpha: 0.35), const Color(0xFFFCA5A5)),
    };
  }
  return switch (tone) {
    StaffTone.neutral => (StockpileColors.inputBg, StockpileColors.darkText),
    StaffTone.orange => (StockpileColors.primary50, const Color(0xFFB24800)),
    StaffTone.blue => (StockpileColors.secondary50, StockpileColors.secondary600),
    StaffTone.green => (StockpileColors.successBg, const Color(0xFF15803D)),
    StaffTone.red => (StockpileColors.dangerBg, const Color(0xFFB91C1C)),
  };
}

/// A status or kind, in a rounded pill.
class StaffPill extends StatelessWidget {
  final String text;
  final StaffTone tone;

  /// The phone's smaller pill, under a number.
  final bool small;

  const StaffPill(this.text, {super.key, this.tone = StaffTone.neutral, this.small = false});

  @override
  Widget build(BuildContext context) {
    final (bg, fg) = _toneColors(tone, StaffTableStyle.of(context).dark);
    // Sized to its text: in a table cell it must not stretch to the
    // column's width.
    return Container(
      height: small ? 22 : 28,
      padding: EdgeInsets.symmetric(horizontal: small ? 8 : 10),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(100)),
      child: Center(
        widthFactor: 1,
        child: Text(
          text,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: StockpileFonts.satoshi(fontSize: small ? 12 : 14, fontWeight: FontWeight.w700, color: fg),
        ),
      ),
    );
  }
}

/// A filter chip with its count: "Low stock · 3". The chosen one is cream
/// with an orange edge. [tone] colours the text of one that is not chosen
/// (orange for Low, red for Out).
class StaffChip extends StatelessWidget {
  final String label;
  final int? count;
  final bool selected;
  final VoidCallback onTap;
  final StaffTone tone;

  const StaffChip({
    super.key,
    required this.label,
    required this.selected,
    required this.onTap,
    this.count,
    this.tone = StaffTone.neutral,
  });

  @override
  Widget build(BuildContext context) {
    final s = StaffTableStyle.of(context);
    final offText = switch (tone) {
      StaffTone.orange => s.dark ? const Color(0xFFFFC08A) : StaffTableStyle.accent,
      StaffTone.red => s.dark ? const Color(0xFFFCA5A5) : const Color(0xFFB91C1C),
      _ => s.body,
    };
    final text = count == null ? label : '$label · ${NumberFormat('#,###').format(count)}';
    return Semantics(
      selected: selected,
      button: true,
      child: Material(
        color: selected ? s.chipOnBg : s.surface,
        shape: StadiumBorder(
          side: selected
              ? const BorderSide(color: StockpileColors.primary900, width: 1.5)
              : BorderSide(color: s.line),
        ),
        child: InkWell(
          customBorder: const StadiumBorder(),
          onTap: selected ? null : onTap,
          child: Container(
            height: 36,
            padding: const EdgeInsets.symmetric(horizontal: 14),
            // Centred with widthFactor 1, not Container.alignment: an
            // aligned Container fills the width it is offered, so in the
            // chip bar's Wrap every chip became a full-width bar (1.6.0, PC).
            child: Center(
              widthFactor: 1,
              child: Text(
                text,
                style: StockpileFonts.satoshi(
                  fontSize: 15,
                  fontWeight: selected || tone != StaffTone.neutral ? FontWeight.w700 : FontWeight.w500,
                  color: selected ? s.chipOnText : offText,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// A row of chips: wrapping on a wide screen, swiping on a phone.
class StaffChipBar extends StatelessWidget {
  final List<Widget> chips;

  /// Shown at the far right on a wide screen ("Click a row to edit").
  final String? hint;
  final bool phone;

  const StaffChipBar({super.key, required this.chips, this.hint, this.phone = false});

  @override
  Widget build(BuildContext context) {
    final spaced = [
      for (var i = 0; i < chips.length; i++) ...[if (i > 0) const SizedBox(width: 8), chips[i]],
    ];
    if (phone) {
      return SingleChildScrollView(scrollDirection: Axis.horizontal, child: Row(children: spaced));
    }
    return Row(
      children: [
        Expanded(child: Wrap(spacing: 8, runSpacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: chips)),
        if (hint != null) ...[
          const SizedBox(width: 12),
          Text(hint!, style: StockpileFonts.satoshi(fontSize: 14, color: StaffTableStyle.of(context).muted)),
        ],
      ],
    );
  }
}

/// A chip that opens a short list (Category, the date range).
class StaffSelectChip<T> extends StatelessWidget {
  final String label;
  final T value;
  final List<(T, String)> options;
  final ValueChanged<T> onChanged;
  final IconData? icon;

  const StaffSelectChip({
    super.key,
    required this.label,
    required this.value,
    required this.options,
    required this.onChanged,
    this.icon,
  });

  @override
  Widget build(BuildContext context) {
    final s = StaffTableStyle.of(context);
    final current = options.where((o) => o.$1 == value).map((o) => o.$2).firstOrNull ?? '';
    return PopupMenuButton<T>(
      tooltip: label,
      initialValue: value,
      onSelected: onChanged,
      position: PopupMenuPosition.under,
      itemBuilder: (_) => [
        for (final (v, text) in options) CheckedPopupMenuItem<T>(value: v, checked: v == value, child: Text(text)),
      ],
      child: Container(
        height: 36,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        decoration: BoxDecoration(
          color: s.surface,
          border: Border.all(color: s.line),
          borderRadius: BorderRadius.circular(100),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon != null) ...[Icon(icon, size: 16, color: s.body), const SizedBox(width: 6)],
            if (label.isNotEmpty) ...[
              Text(label, style: StockpileFonts.satoshi(fontSize: 15, color: s.body)),
              const SizedBox(width: 6),
            ],
            Text(current, style: StockpileFonts.satoshi(fontSize: 15, fontWeight: FontWeight.w700, color: s.text)),
            const SizedBox(width: 2),
            Icon(Icons.expand_more_rounded, size: 18, color: s.body),
          ],
        ),
      ),
    );
  }
}

/// The grey search box.
class StaffSearchField extends StatelessWidget {
  final String hint;
  final ValueChanged<String> onChanged;
  final double height;
  final String? initialValue;

  const StaffSearchField({
    super.key,
    required this.hint,
    required this.onChanged,
    this.height = 44,
    this.initialValue,
  });

  @override
  Widget build(BuildContext context) {
    final s = StaffTableStyle.of(context);
    return Container(
      height: height,
      padding: const EdgeInsets.symmetric(horizontal: 14),
      decoration: BoxDecoration(color: s.input, borderRadius: BorderRadius.circular(12)),
      child: Row(
        children: [
          Icon(Icons.search_rounded, size: 20, color: s.muted),
          const SizedBox(width: 8),
          Expanded(
            child: TextFormField(
              initialValue: initialValue,
              onChanged: onChanged,
              textInputAction: TextInputAction.search,
              style: StockpileFonts.satoshi(fontSize: 16, color: s.text),
              decoration: InputDecoration(
                hintText: hint,
                hintStyle: StockpileFonts.satoshi(fontSize: 16, color: s.muted),
                isCollapsed: true,
                filled: false,
                border: InputBorder.none,
                enabledBorder: InputBorder.none,
                focusedBorder: InputBorder.none,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// The page's main button (orange), or a quieter outlined one.
class StaffButton extends StatelessWidget {
  final String label;
  final IconData icon;
  final VoidCallback? onPressed;
  final bool primary;

  const StaffButton({
    super.key,
    required this.label,
    required this.icon,
    required this.onPressed,
    this.primary = true,
  });

  @override
  Widget build(BuildContext context) {
    final s = StaffTableStyle.of(context);
    final shape = RoundedRectangleBorder(borderRadius: BorderRadius.circular(12));
    final text = Text(label, style: StockpileFonts.satoshi(fontSize: 16, fontWeight: primary ? FontWeight.w700 : FontWeight.w600));
    if (primary) {
      return FilledButton.icon(
        onPressed: onPressed,
        icon: Icon(icon, size: 20),
        label: text,
        style: FilledButton.styleFrom(
          backgroundColor: StaffTableStyle.accent,
          foregroundColor: Colors.white,
          minimumSize: const Size(0, 44),
          padding: const EdgeInsets.symmetric(horizontal: 18),
          shape: shape,
        ),
      );
    }
    return OutlinedButton.icon(
      onPressed: onPressed,
      icon: Icon(icon, size: 20),
      label: text,
      style: OutlinedButton.styleFrom(
        foregroundColor: s.text,
        backgroundColor: s.surface,
        minimumSize: const Size(0, 44),
        padding: const EdgeInsets.symmetric(horizontal: 16),
        side: BorderSide(color: s.line),
        shape: shape,
      ),
    );
  }
}

/// The phone's floating main action, with its label (a circle would cut it).
class StaffFab extends StatelessWidget {
  final String label;
  final IconData icon;
  final VoidCallback onPressed;

  const StaffFab({super.key, required this.label, required this.icon, required this.onPressed});

  @override
  Widget build(BuildContext context) {
    return FloatingActionButton.extended(
      heroTag: null,
      onPressed: onPressed,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      backgroundColor: StaffTableStyle.accent,
      foregroundColor: Colors.white,
      icon: Icon(icon),
      label: Text(label, style: const TextStyle(fontWeight: FontWeight.w700)),
    );
  }
}

/// One entry in a row's ⋯ menu.
class StaffMenuItem {
  final String label;
  final IconData icon;
  final VoidCallback onTap;
  final bool danger;

  /// Off, with [reason] under the label: "nothing happens" and "you may
  /// not do this" look the same otherwise.
  final bool enabled;
  final String? reason;

  const StaffMenuItem(
    this.label,
    this.icon,
    this.onTap, {
    this.danger = false,
    this.enabled = true,
    this.reason,
  });
}

/// A row's ⋯ button.
class StaffMoreButton extends StatelessWidget {
  final List<StaffMenuItem> items;
  final String tooltip;

  /// The phone's narrower button (36 wide, still 48 tall to tap).
  final bool compact;

  const StaffMoreButton({super.key, required this.items, this.tooltip = 'More', this.compact = false});

  @override
  Widget build(BuildContext context) {
    final s = StaffTableStyle.of(context);
    if (items.isEmpty) return SizedBox(width: compact ? 36 : 40);
    final icon = Icon(Icons.more_horiz_rounded, color: s.body);
    return PopupMenuButton<int>(
      tooltip: tooltip,
      icon: compact ? null : icon,
      onSelected: (i) => items[i].onTap(),
      itemBuilder: (_) => [
        for (var i = 0; i < items.length; i++)
          PopupMenuItem<int>(
            value: i,
            enabled: items[i].enabled,
            child: Row(
              children: [
                Icon(
                  items[i].icon,
                  size: 18,
                  color: !items[i].enabled
                      ? s.muted
                      : (items[i].danger ? const Color(0xFFB91C1C) : s.body),
                ),
                const SizedBox(width: 10),
                Flexible(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        items[i].label,
                        style: TextStyle(
                          color: !items[i].enabled
                              ? s.muted
                              : (items[i].danger ? const Color(0xFFB91C1C) : null),
                        ),
                      ),
                      if (!items[i].enabled && items[i].reason != null)
                        Text(items[i].reason!, style: TextStyle(fontSize: 12, color: s.muted)),
                    ],
                  ),
                ),
              ],
            ),
          ),
      ],
      child: compact ? SizedBox(width: 36, height: 48, child: icon) : null,
    );
  }
}

/// One column of a [StaffTable]: a share of the width ([flex]) or a fixed
/// [width].
class StaffColumn {
  final String label;
  final int flex;
  final double? width;
  final bool alignEnd;

  /// Makes the header a button that sorts by this column.
  final VoidCallback? onSort;

  /// The arrow: null when the table is not sorted by this column.
  final bool? sortAscending;

  const StaffColumn(
    this.label, {
    this.flex = 10,
    this.width,
    this.alignEnd = false,
    this.onSort,
    this.sortAscending,
  });
}

/// The wide-screen table: header, rows loaded as you scroll, a footer line.
class StaffTable extends StatelessWidget {
  final List<StaffColumn> columns;
  final int itemCount;

  /// One widget per column for row [index].
  final List<Widget> Function(BuildContext context, int index) cells;
  final void Function(int index)? onRowTap;
  final ScrollController? controller;
  final double rowHeight;

  /// More rows are on their way: a spinner under the last one.
  final bool loadingMore;

  /// Called when the spinner comes into view, so a list too short to
  /// scroll still loads its next rows.
  final VoidCallback? onLoadMore;
  final bool loading;
  final String? error;
  final VoidCallback? onRetry;
  final String emptyText;
  final String? footer;

  /// All rows at their full height, for a table inside a page that scrolls
  /// as a whole (Announcements). Not for long lists.
  final bool shrinkWrap;

  /// Lighter rows (ended announcements).
  final bool Function(int index)? dimmed;

  const StaffTable({
    super.key,
    required this.columns,
    required this.itemCount,
    required this.cells,
    this.onRowTap,
    this.controller,
    this.rowHeight = 62,
    this.loadingMore = false,
    this.onLoadMore,
    this.loading = false,
    this.error,
    this.onRetry,
    this.emptyText = 'Nothing here yet.',
    this.footer,
    this.shrinkWrap = false,
    this.dimmed,
  });

  static const _gap = 16.0;
  static const _pad = 20.0;

  Widget _cell(StaffColumn c, Widget child) {
    final aligned = c.alignEnd ? Align(alignment: Alignment.centerRight, child: child) : child;
    if (c.width != null) return SizedBox(width: c.width, child: aligned);
    return Expanded(flex: c.flex, child: aligned);
  }

  List<Widget> _spaced(List<Widget> cells) => [
    for (var i = 0; i < cells.length; i++) ...[if (i > 0) const SizedBox(width: _gap), cells[i]],
  ];

  Widget _header(StaffTableStyle s) {
    Widget label(StaffColumn c) {
      final style = StockpileFonts.satoshi(
        fontSize: 13,
        fontWeight: FontWeight.w700,
        letterSpacing: 0.5,
        color: c.sortAscending != null ? s.text : s.body,
      );
      final text = Text(c.label.toUpperCase(), maxLines: 1, overflow: TextOverflow.ellipsis, style: style);
      if (c.onSort == null) return text;
      return InkWell(
        onTap: c.onSort,
        borderRadius: BorderRadius.circular(6),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Flexible(child: text),
              if (c.sortAscending != null) ...[
                const SizedBox(width: 6),
                Icon(
                  c.sortAscending! ? Icons.arrow_upward_rounded : Icons.arrow_downward_rounded,
                  size: 15,
                  color: s.text,
                ),
              ],
            ],
          ),
        ),
      );
    }

    return Container(
      height: 46,
      padding: const EdgeInsets.symmetric(horizontal: _pad),
      decoration: BoxDecoration(color: s.head, border: Border(bottom: BorderSide(color: s.line))),
      child: Row(children: _spaced([for (final c in columns) _cell(c, label(c))])),
    );
  }

  Widget _message(StaffTableStyle s, String text, {VoidCallback? retry}) => Center(
    child: Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(text, textAlign: TextAlign.center, style: StockpileFonts.satoshi(fontSize: 16, color: s.muted)),
          if (retry != null) ...[
            const SizedBox(height: 12),
            OutlinedButton(onPressed: retry, child: const Text('Try again')),
          ],
        ],
      ),
    ),
  );

  @override
  Widget build(BuildContext context) {
    final s = StaffTableStyle.of(context);

    Widget rowAt(BuildContext context, int i) {
      final row = Container(
        height: rowHeight,
        padding: const EdgeInsets.symmetric(horizontal: _pad),
        decoration: BoxDecoration(
          color: (dimmed?.call(i) ?? false) ? s.hover : null,
          border: Border(bottom: BorderSide(color: s.rowLine)),
        ),
        child: Row(children: _spaced([for (var c = 0; c < columns.length; c++) _cell(columns[c], cells(context, i)[c])])),
      );
      return Material(
        color: s.surface,
        child: onRowTap == null ? row : InkWell(onTap: () => onRowTap!(i), hoverColor: s.hover, child: row),
      );
    }

    final Widget body;
    if (loading) {
      body = const Center(child: CircularProgressIndicator());
    } else if (error != null && itemCount == 0) {
      body = _message(s, 'Could not load this list.', retry: onRetry);
    } else if (itemCount == 0) {
      body = _message(s, emptyText);
    } else if (shrinkWrap) {
      body = Column(children: [for (var i = 0; i < itemCount; i++) rowAt(context, i)]);
    } else {
      body = ListView.builder(
        controller: controller,
        itemCount: itemCount + (loadingMore ? 1 : 0),
        itemExtent: rowHeight,
        itemBuilder: (context, i) {
          if (i >= itemCount) {
            if (onLoadMore != null) {
              WidgetsBinding.instance.addPostFrameCallback((_) => onLoadMore!());
            }
            return const Center(child: SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.5)));
          }
          return rowAt(context, i);
        },
      );
    }

    return Container(
      decoration: BoxDecoration(
        color: s.surface,
        border: Border.all(color: s.line),
        borderRadius: BorderRadius.circular(16),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        mainAxisSize: shrinkWrap ? MainAxisSize.min : MainAxisSize.max,
        children: [
          _header(s),
          if (shrinkWrap) body else Expanded(child: body),
          if (footer != null && footer!.isNotEmpty)
            Container(
              height: 44,
              padding: const EdgeInsets.symmetric(horizontal: _pad),
              alignment: Alignment.centerLeft,
              decoration: BoxDecoration(border: Border(top: BorderSide(color: s.line))),
              child: Text(footer!, style: StockpileFonts.satoshi(fontSize: 14, color: s.muted)),
            ),
        ],
      ),
    );
  }
}

/// The wide-screen line above the chips: what the list holds, then the
/// search box and the buttons. (The page's name is already in the top bar.)
class StaffTableTop extends StatelessWidget {
  final String caption;
  final Widget? search;
  final double searchWidth;
  final List<Widget> actions;

  const StaffTableTop({
    super.key,
    required this.caption,
    this.search,
    this.searchWidth = 340,
    this.actions = const [],
  });

  @override
  Widget build(BuildContext context) {
    final s = StaffTableStyle.of(context);
    return Row(
      children: [
        Expanded(
          child: Text(
            caption,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: StockpileFonts.satoshi(fontSize: 16, fontWeight: FontWeight.w600, color: s.body),
          ),
        ),
        if (search != null) ...[
          const SizedBox(width: 14),
          SizedBox(width: searchWidth, child: search),
        ],
        for (final a in actions) ...[const SizedBox(width: 10), a],
      ],
    );
  }
}

/// The phone's rows, in one white card.
class StaffPhoneCard extends StatelessWidget {
  final List<Widget> rows;

  const StaffPhoneCard({super.key, required this.rows});

  @override
  Widget build(BuildContext context) {
    final s = StaffTableStyle.of(context);
    return Material(
      color: s.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14), side: BorderSide(color: s.line)),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          for (var i = 0; i < rows.length; i++) ...[
            if (i > 0) Divider(height: 1, thickness: 1, color: s.rowLine),
            rows[i],
          ],
        ],
      ),
    );
  }
}

/// One phone row: a tile, two or three lines, the value on the right,
/// then ⋯ when there is a [menu].
class StaffPhoneRow extends StatelessWidget {
  final Widget leading;
  final String title;
  final List<String> lines;

  /// At most [_trailingWidth] wide, so a long pill shortens instead of
  /// pushing the row off a small phone.
  final Widget? trailing;
  final List<StaffMenuItem>? menu;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final bool dimmed;

  const StaffPhoneRow({
    super.key,
    required this.leading,
    required this.title,
    this.lines = const [],
    this.trailing,
    this.menu,
    this.onTap,
    this.onLongPress,
    this.dimmed = false,
  });

  static const _trailingWidth = 120.0;

  @override
  Widget build(BuildContext context) {
    final s = StaffTableStyle.of(context);
    return InkWell(
      onTap: onTap,
      onLongPress: onLongPress,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 68),
        child: Padding(
          padding: EdgeInsets.fromLTRB(12, 10, menu == null ? 12 : 2, 10),
          child: Row(
            children: [
              leading,
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: StockpileFonts.satoshi(fontSize: 16, fontWeight: FontWeight.w700, color: dimmed ? s.muted : s.text),
                    ),
                    for (final l in lines) ...[
                      const SizedBox(height: 2),
                      Text(l, maxLines: 1, overflow: TextOverflow.ellipsis, style: StockpileFonts.satoshi(fontSize: 14, color: s.muted)),
                    ],
                  ],
                ),
              ),
              if (trailing != null) ...[
                const SizedBox(width: 10),
                ConstrainedBox(constraints: const BoxConstraints(maxWidth: _trailingWidth), child: trailing!),
              ],
              if (menu != null) StaffMoreButton(items: menu!, tooltip: 'More for $title', compact: true),
            ],
          ),
        ),
      ),
    );
  }
}

/// The phone's number on the right, with a pill under it.
class StaffPhoneValue extends StatelessWidget {
  final String value;
  final Widget? pill;

  const StaffPhoneValue(this.value, {super.key, this.pill});

  @override
  Widget build(BuildContext context) {
    final s = StaffTableStyle.of(context);
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        // A big total shrinks to fit rather than run off the row.
        FittedBox(
          fit: BoxFit.scaleDown,
          child: Text(
            value,
            maxLines: 1,
            style: StockpileFonts.satoshi(fontSize: 17, fontWeight: FontWeight.w800, color: s.text)
                .copyWith(fontFeatures: const [FontFeature.tabularFigures()]),
          ),
        ),
        if (pill != null) ...[const SizedBox(height: 4), pill!],
      ],
    );
  }
}

/// The phone's top: count, search, chips, on white.
class StaffPhoneTop extends StatelessWidget {
  final String? caption;
  final Widget? captionTrailing;
  final Widget search;
  final List<Widget> chips;

  const StaffPhoneTop({
    super.key,
    required this.search,
    this.caption,
    this.captionTrailing,
    this.chips = const [],
  });

  @override
  Widget build(BuildContext context) {
    final s = StaffTableStyle.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (caption != null || captionTrailing != null) ...[
          Row(
            children: [
              Expanded(
                child: Text(
                  caption ?? '',
                  style: StockpileFonts.satoshi(fontSize: 14, fontWeight: FontWeight.w600, color: s.muted),
                ),
              ),
              if (captionTrailing != null) captionTrailing!,
            ],
          ),
          const SizedBox(height: 10),
        ],
        search,
        if (chips.isNotEmpty) ...[
          const SizedBox(height: 12),
          StaffChipBar(chips: chips, phone: true),
        ],
      ],
    );
  }
}

/// "TODAY · 37 SALES" over a group of phone rows.
class StaffGroupLabel extends StatelessWidget {
  final String label;
  final String? trailing;

  const StaffGroupLabel(this.label, {super.key, this.trailing});

  @override
  Widget build(BuildContext context) {
    final s = StaffTableStyle.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 14, 4, 6),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label.toUpperCase(),
              style: StockpileFonts.satoshi(fontSize: 13, fontWeight: FontWeight.w800, letterSpacing: 0.8, color: s.muted),
            ),
          ),
          if (trailing != null)
            Text(trailing!, style: StockpileFonts.satoshi(fontSize: 15, fontWeight: FontWeight.w800, color: s.text)),
        ],
      ),
    );
  }
}

/// "Showing 25 of 1,284 · more load as you scroll", or "Showing all 48".
String staffShowing(int shown, int total, {String noun = ''}) {
  final f = NumberFormat('#,###');
  final what = noun.isEmpty ? '' : ' $noun';
  if (shown >= total) return total == 0 ? '' : 'Showing all ${f.format(total)}$what';
  return 'Showing ${f.format(shown)} of ${f.format(total)}$what · more load as you scroll';
}

/// 1284 → "1,284".
String staffCount(int n) => NumberFormat('#,###').format(n);

/// When a row last changed: "Just now", "12 min ago", "Today 9:41 AM",
/// "Yesterday", "3 days ago", then "1 Oct".
String staffWhen(DateTime? t) {
  if (t == null) return '';
  final local = t.toLocal();
  final now = DateTime.now();
  final diff = now.difference(local);
  if (diff.inMinutes < 1 && !diff.isNegative) return 'Just now';
  if (diff.inMinutes < 60 && !diff.isNegative) return '${diff.inMinutes} min ago';
  final days = DateTime(now.year, now.month, now.day)
      .difference(DateTime(local.year, local.month, local.day))
      .inDays;
  if (days == 0) return 'Today ${DateFormat('h:mm a').format(local)}';
  if (days == 1) return 'Yesterday';
  if (days > 1 && days < 7) return '$days days ago';
  return DateFormat(local.year == now.year ? 'd MMM' : 'd MMM yyyy').format(local);
}
