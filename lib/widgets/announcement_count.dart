// lib/widgets/announcement_count.dart
//
// How the dashboards show new announcements (lib/services/
// announcement_alerts.dart): a count beside "Announcements" in the menu,
// and a dot on the phone's menu button, since the menu itself is hidden
// there.

import 'package:flutter/material.dart';

import '../services/announcement_alerts.dart';
import '../utils/fonts.dart';

/// Shared by every menu's badges, so they all read alike.
const announcementBadgeColor = Color(0xFFCC4900);

/// "3" beside Announcements; nothing when there is nothing new.
class AnnouncementCount extends StatelessWidget {
  const AnnouncementCount({super.key});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<int>(
      valueListenable: announcementAlerts.unseen,
      builder: (context, n, _) {
        if (n <= 0) return const SizedBox.shrink();
        return Semantics(
          label: '$n new announcement${n == 1 ? '' : 's'}',
          child: ExcludeSemantics(
            child: Container(
              constraints: const BoxConstraints(minWidth: 22),
              height: 22,
              padding: const EdgeInsets.symmetric(horizontal: 6),
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: announcementBadgeColor,
                borderRadius: BorderRadius.circular(11),
              ),
              child: Text(
                '$n',
                style: StockpileFonts.satoshi(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: Colors.white,
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

/// The phone's menu button, with a dot when there are new announcements
/// (or when [alsoWhen] is true, for a dashboard's other counts).
class MenuButtonWithAlerts extends StatelessWidget {
  final VoidCallback? onPressed;
  final Color? color;
  final bool alsoWhen;
  final IconData icon;

  const MenuButtonWithAlerts({
    super.key,
    required this.onPressed,
    this.color,
    this.alsoWhen = false,
    this.icon = Icons.menu,
  });

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<int>(
      valueListenable: announcementAlerts.unseen,
      builder: (context, n, _) {
        final dot = alsoWhen || n > 0;
        return IconButton(
          tooltip: dot ? 'Menu: something new' : 'Menu',
          onPressed: onPressed,
          icon: Badge(
            isLabelVisible: dot,
            smallSize: 9,
            backgroundColor: announcementBadgeColor,
            child: Icon(icon, color: color),
          ),
        );
      },
    );
  }
}
