// lib/dialogs/announcement_detail_dialog.dart
//
// One announcement in full, opened by tapping it in a list.
//
// The list tiles clamp their body to three lines so a long notice does not
// turn the list into a wall of text; this is where the rest of it lives.
// Deliberately the same shape as the unseen-on-open popup — someone who
// dismissed a notice in the morning and taps it again in the afternoon
// should be looking at the same thing.

import 'package:flutter/material.dart';

import 'package:lzcas/db/db.dart';
import 'package:lzcas/theme.dart';
import 'package:lzcas/utils/animations.dart';
import 'package:lzcas/utils/fonts.dart';
import 'package:lzcas/utils/formatters.dart';
import 'package:lzcas/widgets/announcement_widgets.dart';

/// Show [announcement] in full.
///
/// Works for any signed-in account: saved items are keyed on the account as
/// of v40, so branch cashiers get the save control too.
///
/// Returns true when the saved state changed, so the caller can refresh a
/// list whose stars would otherwise be stale.
Future<bool> showAnnouncementDetail(
  BuildContext context, {
  required Announcement announcement,
}) async {
  final changed = await showAnimatedDialog<bool>(
    context,
    builder: (ctx) => _AnnouncementDetailDialog(announcement: announcement),
  );
  return changed ?? false;
}

class _AnnouncementDetailDialog extends StatefulWidget {
  final Announcement announcement;

  const _AnnouncementDetailDialog({required this.announcement});

  @override
  State<_AnnouncementDetailDialog> createState() =>
      _AnnouncementDetailDialogState();
}

class _AnnouncementDetailDialogState extends State<_AnnouncementDetailDialog> {
  late bool _saved = widget.announcement.saved;
  bool _changed = false;

  Future<void> _toggleSaved() async {
    final wanted = !_saved;
    setState(() => _saved = wanted);

    final ok = await repository.setAnnouncementSaved(
      announcementId: widget.announcement.id,
      saved: wanted,
    );
    if (!mounted) return;
    if (ok) {
      _changed = true;
    } else {
      setState(() => _saved = !wanted);
    }
  }

  @override
  Widget build(BuildContext context) {
    final a = widget.announcement;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final isNarrow = MediaQuery.sizeOf(context).width < 500;
    final divider = isDark
        ? StockpileColors.darkDivider
        : StockpileColors.divider;
    final textColor = isDark
        ? StockpileColors.darkTextPrimary
        : StockpileColors.darkText;
    final bodyColor = isDark
        ? StockpileColors.darkTextBody
        : StockpileColors.bodyText;
    final muted = isDark
        ? StockpileColors.darkTextMuted
        : StockpileColors.mutedText;

    final header = Row(
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
                a.title,
                style: StockpileFonts.satoshi(
                  fontSize: 19,
                  fontWeight: FontWeight.w700,
                  height: 1.3,
                  color: textColor,
                ),
              ),
              const SizedBox(height: 6),
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
                  AnnouncementAudienceChip(
                    audience: a.audience,
                    isDark: isDark,
                  ),
                  // An announcement reached from the Saved list has already
                  // ended; saying so here stops it reading as current.
                  if (!a.isCurrent()) ...[
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: isDark
                            ? StockpileColors.darkInputBg
                            : StockpileColors.inputBg,
                        borderRadius: BorderRadius.circular(100),
                      ),
                      child: Text(
                        'Ended',
                        style: StockpileFonts.satoshi(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: muted,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ],
          ),
        ),
      ],
    );

    final body = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
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

    final close = FilledButton(
      onPressed: () => Navigator.pop(context, _changed),
      child: const Text('Close'),
    );

    if (!isNarrow) {
      return Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        backgroundColor: isDark
            ? StockpileColors.darkSurface
            : StockpileColors.surface,
        child: ConstrainedBox(
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
                child: Align(alignment: Alignment.centerRight, child: close),
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
              child: SizedBox(width: double.infinity, child: close),
            ),
          ],
        ),
      ),
    );
  }

  /// The same labelled star the unseen-on-open popup uses.
  Widget _buildSaveRow(bool isDark) {
    final muted = isDark
        ? StockpileColors.darkTextMuted
        : StockpileColors.mutedText;

    return Material(
      color: _saved
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
              color: _saved ? StockpileColors.primary200 : Colors.transparent,
            ),
          ),
          child: Row(
            children: [
              SizedBox(
                width: 44,
                height: 44,
                child: Icon(
                  _saved ? Icons.star_rounded : Icons.star_outline_rounded,
                  size: 22,
                  color: _saved ? StockpileColors.primary900 : muted,
                ),
              ),
              Expanded(
                child: Text(
                  _saved
                      ? 'Saved — you’ll keep this after it ends'
                      : 'Keep this after it ends',
                  style: StockpileFonts.satoshi(
                    fontSize: 13,
                    height: 1.4,
                    fontWeight: _saved ? FontWeight.w600 : FontWeight.w400,
                    color: _saved
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
}
