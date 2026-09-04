// lib/utils/app_clock.dart
//
// The app's idea of "now", corrected for a wrong device clock.
//
// Everything that decides whether something is still live — an announcement's
// end date, a birthday window — has to agree with the DATABASE, because that
// is what RLS and every server-side query use. Reading DateTime.now() from
// the device makes that agreement conditional on the device being right.
//
// It often is not. A staging device three weeks fast made every announcement
// with an end date read as already ended: staff saw the row but labelled
// "Ended", while members had it filtered out and never learned it existed.
//
// So: measure the offset between this device and the server once per session
// (see SupabaseRepository.syncServerClock), then ask this class the time.

import 'package:flutter/foundation.dart';

class AppClock {
  AppClock._();

  static Duration _offset = Duration.zero;
  static bool _synced = false;

  /// How far the device clock is from the server's, as last measured.
  static Duration get offset => _offset;

  /// Whether [now] is server-corrected or still the raw device clock.
  static bool get isSynced => _synced;

  /// Record the measured difference. Called by the repository after asking
  /// the database for its time.
  static void setOffset(Duration value) {
    _offset = value;
    _synced = true;

    // A device more than a minute out will have produced visible symptoms
    // before this correction landed, so it is worth saying so in the log.
    if (value.abs() > const Duration(minutes: 1)) {
      debugPrint(
        '[AppClock] device clock is off by ${value.inMinutes} minute(s) — '
        'correcting against the server.',
      );
    }
  }

  /// The current time, corrected toward the server.
  ///
  /// Falls back to the plain device clock when the offset has never been
  /// measured — no worse than the behaviour this replaced, so a failed or
  /// pending sync degrades rather than breaks.
  static DateTime now() => DateTime.now().add(_offset);

  /// Today, at midnight, on the corrected clock. For day-granularity
  /// comparisons like the birthday window.
  static DateTime today() {
    final n = now();
    return DateTime(n.year, n.month, n.day);
  }
}
