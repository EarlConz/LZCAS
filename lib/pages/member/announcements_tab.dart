// lib/pages/member/announcements_tab.dart
//
// The member's Announcements tab: what is current, and what they have kept.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:lzcas/db/db.dart';
import 'package:lzcas/services/config_service.dart';
import 'package:lzcas/theme.dart';
import 'package:lzcas/utils/birthday_window.dart';
import 'package:lzcas/utils/fonts.dart';
import 'package:lzcas/widgets/announcement_widgets.dart';

/// Loads a member's announcements and splits them into Current and Saved.
///
/// The rule, since it is the thing that could go wrong: **Current** lists
/// everything still in its window, starred or not — the star only shows
/// state. **Saved** lists only items that have EXPIRED and are starred.
/// Nothing appears in both, and starring something current changes nothing
/// visible until the day it would otherwise have disappeared.
class AnnouncementsTab extends StatefulWidget {
  final Member member;

  const AnnouncementsTab({super.key, required this.member});

  @override
  State<AnnouncementsTab> createState() => _AnnouncementsTabState();
}

class _AnnouncementsTabState extends State<AnnouncementsTab> {
  List<Announcement> _all = const [];
  Set<int> _savedBirthdayYears = const {};
  bool _loading = true;
  StreamSubscription<String>? _sub;

  @override
  void initState() {
    super.initState();
    _load();
    _sub = repository.changes.listen((e) {
      if (e == 'announcements_changed' && mounted) _load();
    });
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    final id = widget.member.id;
    if (id == null) {
      if (mounted) setState(() => _loading = false);
      return;
    }
    final announcements = await repository.fetchAnnouncementsFor(id);
    final years = await repository.fetchSavedBirthdayYears(id);
    if (!mounted) return;
    setState(() {
      _all = announcements;
      _savedBirthdayYears = years;
      _loading = false;
    });
  }

  /// Optimistic: the star flips immediately and only rolls back if the write
  /// fails. A round trip before the star moves makes the control feel broken.
  Future<void> _toggleAnnouncement(Announcement a) async {
    final id = widget.member.id;
    if (id == null) return;
    final wanted = !a.saved;

    setState(() {
      _all = [
        for (final x in _all) x.id == a.id ? x.copyWith(saved: wanted) : x,
      ];
    });

    final ok = await repository.setAnnouncementSaved(
      memberId: id,
      announcementId: a.id,
      saved: wanted,
    );
    if (!ok && mounted) {
      setState(() {
        _all = [
          for (final x in _all) x.id == a.id ? x.copyWith(saved: !wanted) : x,
        ];
      });
    }
  }

  Future<void> _unsaveBirthday(int year) async {
    final id = widget.member.id;
    if (id == null) return;

    setState(() => _savedBirthdayYears = {..._savedBirthdayYears}..remove(year));

    final ok = await repository.setBirthdaySaved(
      memberId: id,
      year: year,
      saved: false,
    );
    if (!ok && mounted) {
      setState(() => _savedBirthdayYears = {..._savedBirthdayYears, year});
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final config = context.watch<ConfigService>();

    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }

    final current = _all.where((a) => a.isCurrent()).toList();
    final savedExpired = _all
        .where((a) => a.saved && !a.isCurrent())
        .toList();

    // A saved greeting from a year whose window has closed. The one still
    // inside its window lives on the Overview, so listing it here too would
    // show it twice.
    final live = birthdayGreetingFor(
      widget.member.birthday,
      windowDays: config.birthdayGreetingDays,
    );
    final savedBirthdays =
        (_savedBirthdayYears.toList()..sort((a, b) => b.compareTo(a)))
            .where((y) => y != live?.year)
            .toList();

    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _card(
            isDark: isDark,
            icon: Icons.campaign_rounded,
            iconColor: StockpileColors.primary900,
            title: 'Announcements',
            subtitle: 'News and reminders from the GUTVita office. '
                'Tap the star to keep one.',
            emptyText: 'Nothing new right now.',
            children: [
              for (final a in current)
                AnnouncementTile(
                  announcement: a,
                  isDark: isDark,
                  onToggleSaved: () => _toggleAnnouncement(a),
                ),
            ],
          ),
          if (savedExpired.isNotEmpty || savedBirthdays.isNotEmpty) ...[
            const SizedBox(height: 20),
            _card(
              isDark: isDark,
              icon: Icons.star_rounded,
              iconColor: StockpileColors.primary900,
              title: 'Saved',
              trailing: '${savedExpired.length + savedBirthdays.length}',
              subtitle: 'Kept here after they stopped being current. '
                  'Unstar one to let it go.',
              emptyText: '',
              children: [
                for (final a in savedExpired)
                  AnnouncementTile(
                    announcement: a,
                    asSaved: true,
                    isDark: isDark,
                    onToggleSaved: () => _toggleAnnouncement(a),
                  ),
                for (final year in savedBirthdays)
                  SavedBirthdayTile(
                    greeting: BirthdayGreeting(
                      year: year,
                      // The stored year is all we keep, so the day is
                      // rebuilt from the member's birthday rather than
                      // remembered — same date, same greeting.
                      occurredOn:
                          parseBirthday(widget.member.birthday) ??
                          DateTime(year),
                      daysSince: 0,
                      saved: true,
                    ),
                    firstName: widget.member.firstName?.trim() ?? '',
                    message: config.birthdayGreetingMessage,
                    isDark: isDark,
                    onToggleSaved: () => _unsaveBirthday(year),
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  /// One card with a header and divider-separated rows — the same shape the
  /// Earnings History card uses, so this introduces no new vocabulary.
  Widget _card({
    required bool isDark,
    required IconData icon,
    required Color iconColor,
    required String title,
    required String subtitle,
    required String emptyText,
    required List<Widget> children,
    String? trailing,
  }) {
    final textColor = isDark
        ? StockpileColors.darkTextPrimary
        : StockpileColors.darkText;
    final mutedColor = isDark
        ? StockpileColors.darkTextMuted
        : StockpileColors.mutedText;
    final divider = isDark
        ? StockpileColors.darkDivider
        : StockpileColors.divider;

    return Card(
      elevation: 0,
      color: isDark ? StockpileColors.darkSurface : StockpileColors.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: divider),
      ),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, size: 20, color: iconColor),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    title,
                    style: StockpileFonts.satoshi(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      color: textColor,
                    ),
                  ),
                ),
                if (trailing != null)
                  Text(
                    trailing,
                    style: StockpileFonts.satoshi(
                      fontSize: 13,
                      color: mutedColor,
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              subtitle,
              style: StockpileFonts.satoshi(fontSize: 11, color: mutedColor),
            ),
            const SizedBox(height: 16),
            if (children.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 16),
                child: Text(
                  emptyText,
                  style: StockpileFonts.satoshi(
                    fontSize: 13,
                    color: mutedColor,
                  ),
                ),
              )
            else
              for (var i = 0; i < children.length; i++) ...[
                if (i > 0) ...[
                  const SizedBox(height: 16),
                  Divider(height: 1, color: divider.withAlpha(120)),
                  const SizedBox(height: 16),
                ],
                children[i],
              ],
          ],
        ),
      ),
    );
  }
}
