// lib/widgets/announcement_widgets.dart
//
// The member-facing pieces of the announcements feature: the compact strip
// that sits on the Overview, the birthday greeting card, and the tile used
// for one announcement in the Announcements tab.

import 'package:flutter/material.dart';

import 'package:lzcas/db/db.dart';
import 'package:lzcas/theme.dart';
import 'package:lzcas/utils/fonts.dart';
import 'package:lzcas/utils/formatters.dart';
import 'package:lzcas/widgets/poster_image.dart';

/// Shared palette so the three widgets below stay in step without each
/// re-deriving the same six colours.
class _Tones {
  final Color surface, border, title, body, muted;
  const _Tones(this.surface, this.border, this.title, this.body, this.muted);

  factory _Tones.of(bool isDark) => isDark
      ? const _Tones(
          StockpileColors.darkSurface,
          StockpileColors.darkDivider,
          StockpileColors.darkTextPrimary,
          StockpileColors.darkTextBody,
          StockpileColors.darkTextMuted,
        )
      : const _Tones(
          StockpileColors.surface,
          StockpileColors.divider,
          StockpileColors.darkText,
          StockpileColors.bodyText,
          StockpileColors.mutedText,
        );
}

/// Who an announcement went to, as a chip.
///
/// Public and shared: the member tile, the detail view and the unseen-on-open
/// popup all show this, and three copies of the same switch is how the two
/// admin list forms started disagreeing about wording.
class AnnouncementAudienceChip extends StatelessWidget {
  final AnnouncementAudience audience;
  final bool isDark;

  const AnnouncementAudienceChip({
    super.key,
    required this.audience,
    required this.isDark,
  });

  @override
  Widget build(BuildContext context) {
    final isBranches = audience == AnnouncementAudience.branches;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: isBranches
            ? StockpileColors.secondary50
            : (isDark ? StockpileColors.darkInputBg : StockpileColors.inputBg),
        borderRadius: BorderRadius.circular(100),
      ),
      child: Text(
        switch (audience) {
          AnnouncementAudience.all => 'Everyone',
          AnnouncementAudience.branches => 'Branches only',
          AnnouncementAudience.members => 'Members only',
        },
        style: StockpileFonts.satoshi(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          color: isBranches
              ? StockpileColors.secondary500
              : StockpileColors.bodyText,
        ),
      ),
    );
  }
}

/// A megaphone, drawn once and reused.
class _MegaphoneIcon extends StatelessWidget {
  final double size;
  final Color color;
  const _MegaphoneIcon({required this.size, required this.color});

  @override
  Widget build(BuildContext context) =>
      Icon(Icons.campaign_rounded, size: size, color: color);
}

/// The star that saves an item. The glyph is 20px but the tap target is 44 —
/// these rows are dense and this is the only control in them.
class SaveStarButton extends StatelessWidget {
  final bool saved;
  final VoidCallback? onPressed;
  final Color idleColor;

  const SaveStarButton({
    super.key,
    required this.saved,
    required this.onPressed,
    required this.idleColor,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 44,
      height: 44,
      child: IconButton(
        padding: EdgeInsets.zero,
        iconSize: 20,
        tooltip: saved ? 'Saved — tap to let it go' : 'Keep this',
        onPressed: onPressed,
        icon: Icon(
          saved ? Icons.star_rounded : Icons.star_outline_rounded,
          color: saved ? StockpileColors.primary900 : idleColor,
        ),
      ),
    );
  }
}

// ─── Overview strip ─────────────────────────────────────────────────────

/// One line on the Overview showing the newest current announcement.
///
/// Deliberately small — about a third of the height of the full card — so
/// the Overview stays about the member's own numbers, while the newest
/// notice is still on the screen everyone lands on. Renders nothing at all
/// when there is nothing current.
///
/// The title is capped at one line, which puts a real constraint on how
/// announcements are written: the first few words have to carry it.
class AnnouncementStrip extends StatelessWidget {
  final List<Announcement> current;
  final VoidCallback onViewAll;
  final bool isDark;

  const AnnouncementStrip({
    super.key,
    required this.current,
    required this.onViewAll,
    required this.isDark,
  });

  @override
  Widget build(BuildContext context) {
    if (current.isEmpty) return const SizedBox.shrink();

    final t = _Tones.of(isDark);
    final newest = current.first;

    return Card(
      elevation: 0,
      color: t.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: t.border),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onViewAll,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
          child: Row(
            children: [
              // The poster stands in for the megaphone when there is one, so
              // the strip previews the notice rather than labelling it.
              if (newest.hasImage)
                PosterImage(
                  path: newest.imagePath,
                  isDark: isDark,
                  width: 36,
                  height: 36,
                  fit: BoxFit.cover,
                  borderRadius: 10,
                )
              else
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: StockpileColors.primary900.withValues(alpha: 0.10),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  alignment: Alignment.center,
                  child: const _MegaphoneIcon(
                    size: 20,
                    color: StockpileColors.primary900,
                  ),
                ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      newest.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: StockpileFonts.satoshi(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        height: 1.35,
                        color: t.title,
                      ),
                    ),
                    Text(
                      formatRelativeDate(newest.publishedAt),
                      style: StockpileFonts.satoshi(
                        fontSize: 11,
                        color: t.muted,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Text(
                current.length > 1
                    ? 'View all (${current.length})'
                    : 'View all',
                style: StockpileFonts.satoshi(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: StockpileColors.primary900,
                ),
              ),
              const Icon(
                Icons.chevron_right_rounded,
                size: 20,
                color: StockpileColors.primary900,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─── Birthday greeting ──────────────────────────────────────────────────

/// The automatic greeting, shown on the Overview for the whole window after
/// a member's birthday.
///
/// Warm rather than loud: the palette's own #FFF7DF / #FFE082 on light, so
/// it does not put a second block of primary orange directly under the
/// hero. Those two are light-mode tints and glare on the dark surface, so
/// dark mode derives its own from the accent.
class BirthdayGreetingCard extends StatelessWidget {
  final BirthdayGreeting greeting;
  final String firstName;

  /// May be empty when a poster carries the whole greeting (v44).
  final String message;

  /// The one global greeting poster, or null for a text-only greeting.
  /// Same image for everyone — greetings are computed per member, but they
  /// are not authored per member.
  final String? imagePath;

  final VoidCallback? onToggleSaved;
  final bool isDark;

  const BirthdayGreetingCard({
    super.key,
    required this.greeting,
    required this.firstName,
    required this.message,
    required this.onToggleSaved,
    required this.isDark,
    this.imagePath,
  });

  bool get _hasPoster => (imagePath ?? '').trim().isNotEmpty;

  @override
  Widget build(BuildContext context) {
    final t = _Tones.of(isDark);
    final fill = isDark
        ? StockpileColors.primary900.withValues(alpha: 0.12)
        : StockpileColors.primary50;
    final border = isDark
        ? StockpileColors.primary900.withValues(alpha: 0.35)
        : StockpileColors.primary200;

    // "Today · 21 August" on the day, "3 weeks ago · 21 August" later. The
    // stamp is what keeps a late greeting from reading as a system that has
    // lost track of the date.
    final stamp =
        '${formatRelativeDate(greeting.occurredOn)} · '
        '${formatDayAndMonth(greeting.occurredOn)}';

    return Card(
      elevation: 0,
      color: fill,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: border),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(22, 20, 14, 20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Container(
                  width: 56,
                  height: 56,
                  decoration: BoxDecoration(
                    color: StockpileColors.primary900.withValues(alpha: 0.14),
                    shape: BoxShape.circle,
                  ),
                  alignment: Alignment.center,
                  child: const Icon(
                    Icons.cake_rounded,
                    size: 28,
                    color: StockpileColors.primary900,
                  ),
                ),
                const SizedBox(width: 18),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        firstName.isEmpty
                            ? 'Happy birthday!'
                            : 'Happy birthday, $firstName!',
                        style: StockpileFonts.satoshi(
                          fontSize: 20,
                          fontWeight: FontWeight.w800,
                          height: 1.25,
                          color: t.title,
                        ),
                      ),
                      // Skipped entirely when a poster carries the greeting —
                      // an empty Text still takes vertical space and would open
                      // a gap under the name.
                      if (message.trim().isNotEmpty) ...[
                        const SizedBox(height: 3),
                        Text(
                          message,
                          style: StockpileFonts.satoshi(
                            fontSize: 14,
                            height: 1.5,
                            color: t.body,
                          ),
                        ),
                      ],
                      const SizedBox(height: 3),
                      Text(
                        stamp,
                        style: StockpileFonts.satoshi(
                          fontSize: 11,
                          color: t.muted,
                        ),
                      ),
                    ],
                  ),
                ),
                SaveStarButton(
                  saved: greeting.saved,
                  onPressed: onToggleSaved,
                  idleColor: t.muted,
                ),
              ],
            ),
            if (_hasPoster) ...[
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                // Trailing padding matches the star button's inset so the
                // poster lines up with the text column above it rather than
                // running under the star.
                child: Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: PosterImage(
                    path: imagePath,
                    isDark: isDark,
                    fit: BoxFit.cover,
                    borderRadius: 12,
                    maxHeight: 320,
                    openOnTap: true,
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

// ─── One announcement, as listed in the tab ─────────────────────────────

class AnnouncementTile extends StatelessWidget {
  final Announcement announcement;

  /// True when this is being listed under "Saved" rather than "Current" —
  /// adds the leading glyph and the Ended chip.
  final bool asSaved;

  final VoidCallback? onToggleSaved;
  final bool isDark;

  /// Opens the full announcement. When null the tile is inert and the body
  /// is NOT clamped — nothing would reveal the rest of it.
  final VoidCallback? onTap;

  const AnnouncementTile({
    super.key,
    required this.announcement,
    required this.onToggleSaved,
    required this.isDark,
    this.asSaved = false,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final row = _buildRow();
    if (onTap == null) return row;

    // Negative-inset padding so the ripple covers the row's full width
    // without shifting it away from the neighbouring dividers.
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: row,
        ),
      ),
    );
  }

  /// Adaptive (v44): a poster with no words gets the full width, because a
  /// 56px thumbnail of the only content is not much of an announcement. One
  /// that also has text keeps the compact row and shows the poster small —
  /// the words are what you scan a list for.
  Widget _buildRow() {
    final t = _Tones.of(isDark);
    return announcement.isImageOnly ? _posterFirst(t) : _textFirst(t);
  }

  Widget _textFirst(_Tones t) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // The poster thumbnail takes the leading slot when there is one,
        // standing in for the megaphone rather than sitting beside it —
        // two glyphs down the left edge reads as two separate things.
        if (announcement.hasImage) ...[
          PosterImage(
            path: announcement.imagePath,
            isDark: isDark,
            width: 56,
            height: 56,
            fit: BoxFit.cover,
            borderRadius: 10,
          ),
          const SizedBox(width: 12),
        ] else if (asSaved) ...[
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              color: isDark
                  ? StockpileColors.darkInputBg
                  : StockpileColors.inputBg,
              borderRadius: BorderRadius.circular(10),
            ),
            alignment: Alignment.center,
            child: _MegaphoneIcon(size: 18, color: t.muted),
          ),
          const SizedBox(width: 12),
        ],
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Flexible(
                    child: Text(
                      announcement.title,
                      style: StockpileFonts.satoshi(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        height: 1.35,
                        color: t.title,
                      ),
                    ),
                  ),
                  if (asSaved) ...[
                    const SizedBox(width: 8),
                    _EndedChip(isDark: isDark),
                  ],
                ],
              ),
              if (announcement.hasBody) ...[
                const SizedBox(height: 5),
                Text(
                  announcement.body,
                  // Clamped only when there is somewhere to read the rest.
                  // A 400-character notice in every row turns the list into a
                  // wall of text nobody scans.
                  maxLines: onTap == null ? null : 3,
                  overflow: onTap == null ? null : TextOverflow.ellipsis,
                  style: StockpileFonts.satoshi(
                    fontSize: 13,
                    height: 1.5,
                    color: t.body,
                  ),
                ),
              ],
              const SizedBox(height: 5),
              _metaRow(t),
            ],
          ),
        ),
        const SizedBox(width: 8),
        SaveStarButton(
          saved: announcement.saved,
          onPressed: onToggleSaved,
          idleColor: t.muted,
        ),
      ],
    );
  }

  /// Poster-only: the image IS the announcement, so it gets the full width
  /// and the title sits above it as a label rather than beside a thumbnail.
  Widget _posterFirst(_Tones t) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Flexible(
              child: Text(
                announcement.title,
                style: StockpileFonts.satoshi(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  height: 1.35,
                  color: t.title,
                ),
              ),
            ),
            if (asSaved) ...[
              const SizedBox(width: 8),
              _EndedChip(isDark: isDark),
            ],
            const Spacer(),
            SaveStarButton(
              saved: announcement.saved,
              onPressed: onToggleSaved,
              idleColor: t.muted,
            ),
          ],
        ),
        const SizedBox(height: 8),
        SizedBox(
          width: double.infinity,
          child: PosterImage(
            path: announcement.imagePath,
            isDark: isDark,
            fit: BoxFit.cover,
            borderRadius: 12,
            // Capped so a tall portrait poster cannot push everything below
            // it off a phone screen. Tapping through shows the whole thing.
            maxHeight: 320,
            // The row's own onTap opens the detail dialog; without that
            // (the inert Overview strip) the poster opens the viewer itself,
            // so a poster is never a dead end.
            openOnTap: onTap == null,
          ),
        ),
        const SizedBox(height: 6),
        _metaRow(t),
      ],
    );
  }

  /// Date, plus the affordance that says the row goes somewhere. The label
  /// follows the content: there is nothing to "read more" of on a poster.
  Widget _metaRow(_Tones t) {
    return Row(
      children: [
        Text(
          formatRelativeDate(announcement.publishedAt),
          style: StockpileFonts.satoshi(fontSize: 11, color: t.muted),
        ),
        if (onTap != null) ...[
          const SizedBox(width: 8),
          Text(
            announcement.isImageOnly ? 'View poster' : 'Read more',
            style: StockpileFonts.satoshi(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: StockpileColors.primary900,
            ),
          ),
        ],
      ],
    );
  }
}

/// Marks a saved item that is no longer current. Without it a saved holiday
/// notice from last December would sit in the list reading as live, which is
/// worse than having lost it.
class _EndedChip extends StatelessWidget {
  final bool isDark;
  const _EndedChip({required this.isDark});

  @override
  Widget build(BuildContext context) {
    final t = _Tones.of(isDark);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: isDark ? StockpileColors.darkInputBg : StockpileColors.inputBg,
        borderRadius: BorderRadius.circular(100),
      ),
      child: Text(
        'Ended',
        style: StockpileFonts.satoshi(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          color: t.muted,
        ),
      ),
    );
  }
}

/// A saved birthday greeting, listed alongside saved announcements. Carries
/// the cake rather than the megaphone: it is a keepsake, not office news.
class SavedBirthdayTile extends StatelessWidget {
  final BirthdayGreeting greeting;
  final String firstName;
  final String message;
  final VoidCallback? onToggleSaved;
  final bool isDark;

  const SavedBirthdayTile({
    super.key,
    required this.greeting,
    required this.firstName,
    required this.message,
    required this.onToggleSaved,
    required this.isDark,
  });

  @override
  Widget build(BuildContext context) {
    final t = _Tones.of(isDark);

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 34,
          height: 34,
          decoration: BoxDecoration(
            color: StockpileColors.primary900.withValues(alpha: 0.10),
            borderRadius: BorderRadius.circular(10),
          ),
          alignment: Alignment.center,
          child: const Icon(
            Icons.cake_rounded,
            size: 18,
            color: StockpileColors.primary900,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                firstName.isEmpty
                    ? 'Happy birthday!'
                    : 'Happy birthday, $firstName!',
                style: StockpileFonts.satoshi(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  height: 1.35,
                  color: t.title,
                ),
              ),
              const SizedBox(height: 5),
              Text(
                message,
                style: StockpileFonts.satoshi(
                  fontSize: 13,
                  height: 1.5,
                  color: t.body,
                ),
              ),
              const SizedBox(height: 5),
              Text(
                formatDayAndMonth(greeting.occurredOn),
                style: StockpileFonts.satoshi(fontSize: 11, color: t.muted),
              ),
            ],
          ),
        ),
        const SizedBox(width: 8),
        SaveStarButton(
          saved: true,
          onPressed: onToggleSaved,
          idleColor: t.muted,
        ),
      ],
    );
  }
}
