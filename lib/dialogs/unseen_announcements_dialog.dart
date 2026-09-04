// lib/dialogs/unseen_announcements_dialog.dart
//
// The announcements someone has not seen yet, shown once when they open
// their account.
//
// Two rules shape this, both about not becoming an interruption:
//
//   * It is only ever raised from a dashboard's first post-frame callback,
//     never mid-session. An announcement posted while a branch cashier is
//     ringing up a sale waits until their next open.
//   * Closing it marks everything in it as seen — including "Skip all".
//     Offering the same notice twice is what makes people stop reading them.

import 'package:flutter/material.dart';

import 'package:lzcas/db/db.dart';
import 'package:lzcas/theme.dart';
import 'package:lzcas/utils/animations.dart';
import 'package:lzcas/utils/fonts.dart';
import 'package:lzcas/utils/formatters.dart';
import 'package:lzcas/widgets/announcement_widgets.dart';

/// Fetch this account's unseen announcements and, if there are any, show
/// them. Marks the whole set seen once the dialog closes, however it closed.
///
/// Works for any signed-in account — members, resellers and branch cashiers
/// alike. Saved items are keyed on the account as of v40, so the save control
/// no longer depends on having a `members` row.
///
/// Safe to call unconditionally: it does nothing when there is nothing to
/// show, and a failed fetch returns an empty list rather than throwing.
Future<void> showUnseenAnnouncements(BuildContext context) async {
  final items = await repository.fetchUnseenAnnouncements();
  if (items.isEmpty || !context.mounted) return;

  await showAnimatedDialog<void>(
    context,
    barrierDismissible: false,
    builder: (ctx) => _UnseenAnnouncementsDialog(items: items),
  );

  // After the dialog, not inside it: whichever way it closed — a button,
  // the Android back gesture, a route change — the set has been offered.
  await repository.markAnnouncementsSeen([for (final a in items) a.id]);
}

class _UnseenAnnouncementsDialog extends StatefulWidget {
  final List<Announcement> items;

  const _UnseenAnnouncementsDialog({required this.items});

  @override
  State<_UnseenAnnouncementsDialog> createState() =>
      _UnseenAnnouncementsDialogState();
}

class _UnseenAnnouncementsDialogState
    extends State<_UnseenAnnouncementsDialog> {
  int _index = 0;

  /// Ids this viewer has starred, tracked here so the star reflects taps
  /// immediately rather than after a round trip.
  final Set<int> _saved = {};

  bool get _isLast => _index == widget.items.length - 1;
  bool get _isOnly => widget.items.length == 1;
  Announcement get _current => widget.items[_index];

  Future<void> _toggleSaved() async {
    final a = _current;
    final wanted = !_saved.contains(a.id);
    setState(() => wanted ? _saved.add(a.id) : _saved.remove(a.id));

    final ok = await repository.setAnnouncementSaved(
      announcementId: a.id,
      saved: wanted,
    );
    // Roll back a failed write so the star never claims something that did
    // not happen.
    if (!ok && mounted) {
      setState(() => wanted ? _saved.remove(a.id) : _saved.add(a.id));
    }
  }

  void _next() {
    if (_isLast) {
      Navigator.pop(context);
    } else {
      setState(() => _index++);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final isNarrow = MediaQuery.sizeOf(context).width < 500;
    final divider = isDark
        ? StockpileColors.darkDivider
        : StockpileColors.divider;

    final header = _buildHeader(isDark);
    final body = _buildBody(isDark);
    final footer = _buildFooter(isDark, isNarrow);

    if (!isNarrow) {
      return Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        backgroundColor: isDark
            ? StockpileColors.darkSurface
            : StockpileColors.surface,
        child: ConstrainedBox(
          // Height-capped so a long announcement scrolls inside the dialog
          // instead of pushing the actions off the bottom of the screen.
          constraints: const BoxConstraints(maxWidth: 480, maxHeight: 620),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 22, 24, 16),
                child: header,
              ),
              Divider(height: 1, color: divider),
              Flexible(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(24, 20, 24, 22),
                  child: body,
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 0, 24, 22),
                child: footer,
              ),
            ],
          ),
        ),
      );
    }

    return Dialog.fullscreen(
      backgroundColor: isDark
          ? StockpileColors.darkBg
          : StockpileColors.scaffoldBg,
      child: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 18, 20, 16),
              child: header,
            ),
            Divider(height: 1, color: divider),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(20, 22, 20, 24),
                child: body,
              ),
            ),
            Divider(height: 1, color: divider),
            Container(
              color: isDark
                  ? StockpileColors.darkSurface
                  : StockpileColors.surface,
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
              child: footer,
            ),
          ],
        ),
      ),
    );
  }

  // ── Header ────────────────────────────────────────────────────────────

  Widget _buildHeader(bool isDark) {
    final count = widget.items.length;
    final textColor = isDark
        ? StockpileColors.darkTextPrimary
        : StockpileColors.darkText;
    final muted = isDark
        ? StockpileColors.darkTextMuted
        : StockpileColors.mutedText;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Icon(
          Icons.campaign_rounded,
          size: 28,
          color: StockpileColors.primary900,
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                _isOnly ? 'New announcement' : '$count new announcements',
                style: StockpileFonts.satoshi(
                  fontSize: 21,
                  fontWeight: FontWeight.w700,
                  height: 1.25,
                  color: textColor,
                ),
              ),
              const SizedBox(height: 1),
              Text(
                'From the GUTVita office',
                style: StockpileFonts.satoshi(fontSize: 12, color: muted),
              ),
            ],
          ),
        ),
        if (!_isOnly) ...[
          const SizedBox(width: 10),
          Container(
            margin: const EdgeInsets.only(top: 3),
            padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 4),
            decoration: BoxDecoration(
              color: isDark
                  ? StockpileColors.primary900.withAlpha(38)
                  : StockpileColors.primary50,
              borderRadius: BorderRadius.circular(100),
            ),
            child: Text(
              '${_index + 1} of $count',
              style: StockpileFonts.satoshi(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: isDark
                    ? StockpileColors.primary200
                    : const Color(0xFFB24800),
              ),
            ),
          ),
        ],
      ],
    );
  }

  // ── Body ──────────────────────────────────────────────────────────────

  Widget _buildBody(bool isDark) {
    final a = _current;
    final textColor = isDark
        ? StockpileColors.darkTextPrimary
        : StockpileColors.darkText;
    final bodyColor = isDark
        ? StockpileColors.darkTextBody
        : StockpileColors.bodyText;
    final muted = isDark
        ? StockpileColors.darkTextMuted
        : StockpileColors.mutedText;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          a.title,
          style: StockpileFonts.satoshi(
            fontSize: 19,
            fontWeight: FontWeight.w700,
            height: 1.35,
            color: textColor,
          ),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Text(
              formatRelativeDate(a.publishedAt),
              style: StockpileFonts.satoshi(fontSize: 11, color: muted),
            ),
            const SizedBox(width: 8),
            Container(
              width: 3,
              height: 3,
              decoration: BoxDecoration(
                color: muted,
                borderRadius: BorderRadius.circular(100),
              ),
            ),
            const SizedBox(width: 8),
            AnnouncementAudienceChip(audience: a.audience, isDark: isDark),
          ],
        ),
        const SizedBox(height: 14),
        Text(
          a.body,
          style: StockpileFonts.satoshi(
            fontSize: 15,
            height: 1.6,
            color: bodyColor,
          ),
        ),
        const SizedBox(height: 18),
        _buildSaveRow(isDark),
      ],
    );
  }

  /// The same star the Announcements tab uses, but with a label beside it —
  /// on a modal someone is seeing for the first time, a bare star glyph has
  /// no affordance. The whole row is the target.
  Widget _buildSaveRow(bool isDark) {
    final saved = _saved.contains(_current.id);
    final muted = isDark
        ? StockpileColors.darkTextMuted
        : StockpileColors.mutedText;

    return Material(
      color: saved
          ? (isDark
                ? StockpileColors.primary900.withAlpha(30)
                : StockpileColors.primary50)
          : (isDark ? StockpileColors.darkInputBg : StockpileColors.inputBg),
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: _toggleSaved,
        child: Container(
          padding: const EdgeInsets.fromLTRB(4, 4, 14, 4),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: saved ? StockpileColors.primary200 : Colors.transparent,
            ),
          ),
          child: Row(
            children: [
              SizedBox(
                width: 44,
                height: 44,
                child: Icon(
                  saved ? Icons.star_rounded : Icons.star_outline_rounded,
                  size: 22,
                  color: saved ? StockpileColors.primary900 : muted,
                ),
              ),
              Expanded(
                child: Text(
                  saved
                      ? 'Saved — you’ll keep this after it ends'
                      : 'Keep this after it ends',
                  style: StockpileFonts.satoshi(
                    fontSize: 13,
                    height: 1.4,
                    fontWeight: saved ? FontWeight.w600 : FontWeight.w400,
                    color: saved
                        ? (isDark
                              ? StockpileColors.primary200
                              : const Color(0xFFB24800))
                        : (isDark
                              ? StockpileColors.darkTextBody
                              : StockpileColors.bodyText),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ── Footer ────────────────────────────────────────────────────────────

  Widget _buildFooter(bool isDark, bool isNarrow) {
    final muted = isDark
        ? StockpileColors.darkTextMuted
        : StockpileColors.mutedText;

    // A single announcement has nothing to step through and nothing to skip
    // past, so it gets one button and no dots.
    if (_isOnly) {
      final button = FilledButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Got it'),
      );
      return isNarrow
          ? SizedBox(width: double.infinity, child: button)
          : Align(alignment: Alignment.centerRight, child: button);
    }

    final dots = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 0; i < widget.items.length; i++) ...[
          if (i > 0) const SizedBox(width: 6),
          AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            width: i == _index ? 20 : 6,
            height: 6,
            decoration: BoxDecoration(
              color: i == _index
                  ? StockpileColors.primary900
                  : (isDark
                        ? StockpileColors.darkDivider
                        : const Color(0xFFD9D9DF)),
              borderRadius: BorderRadius.circular(100),
            ),
          ),
        ],
      ],
    );

    final skip = TextButton(
      onPressed: () => Navigator.pop(context),
      style: TextButton.styleFrom(foregroundColor: muted),
      child: const Text('Skip all'),
    );

    final next = FilledButton.icon(
      onPressed: _next,
      icon: Icon(
        _isLast ? Icons.check_rounded : Icons.arrow_forward_rounded,
        size: 18,
      ),
      label: Text(_isLast ? 'Done' : 'Next'),
    );

    if (isNarrow) {
      return Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          dots,
          const SizedBox(height: 14),
          SizedBox(width: double.infinity, child: next),
          const SizedBox(height: 4),
          SizedBox(width: double.infinity, child: skip),
        ],
      );
    }

    return Row(
      children: [
        Expanded(child: dots),
        skip,
        const SizedBox(width: 8),
        next,
      ],
    );
  }
}
