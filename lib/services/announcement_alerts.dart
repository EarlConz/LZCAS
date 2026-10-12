// lib/services/announcement_alerts.dart
//
// The count of new announcements shown on each dashboard's Announcements
// tab. Part 7 (AT2): with the app open on another tab, nothing said one had
// arrived. "New" means current, posted by someone else, and not seen yet,
// using the same seen records the sign-in pop-up keeps
// (announcement_reads, v40). Opening the tab clears what the pop-up would
// have shown, and the reverse.
//
// It never interrupts: a count on the tab, nothing more. The pop-up still
// only appears when an account is opened (see unseen_announcements_dialog).

import 'dart:async';

import 'package:flutter/widgets.dart';

import '../db/db.dart';

class AnnouncementAlerts {
  AnnouncementAlerts._();

  /// New announcements for the signed-in account; 0 when there are none.
  final ValueNotifier<int> unseen = ValueNotifier(0);

  StreamSubscription<String>? _sub;
  Timer? _timer;
  AppLifecycleListener? _life;
  bool _viewing = false;

  /// Counts that started before a newer one are dropped, so a slow answer
  /// cannot put back a count that was just cleared.
  int _run = 0;

  /// Called by each dashboard when it opens: counts for this account now,
  /// then on every announcement change, every minute (in case a live
  /// update is missed), and when the app comes back to the front.
  void start() {
    _sub ??= repository.changes.listen((e) {
      if (e == 'announcements_changed' || e == 'cloud_restored') refresh();
    });
    _timer ??= Timer.periodic(const Duration(minutes: 1), (_) => refresh());
    _life ??= AppLifecycleListener(onResume: refresh);
    _viewing = false;
    unseen.value = 0;
    refresh();
  }

  /// Whether the Announcements tab is on screen. While it is, what arrives
  /// counts as seen, and opening it clears the count.
  set viewing(bool on) {
    if (_viewing == on) return;
    _viewing = on;
    if (on) refresh();
  }

  Future<void> refresh() async {
    final run = ++_run;
    final ids = await repository.fetchUnseenAnnouncementIds();
    if (run != _run) return;
    if (_viewing && ids.isNotEmpty) {
      unseen.value = 0;
      await repository.markAnnouncementsSeen(ids);
      return;
    }
    unseen.value = ids.length;
  }
}

final announcementAlerts = AnnouncementAlerts._();
