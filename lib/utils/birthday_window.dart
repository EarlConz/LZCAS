// lib/utils/birthday_window.dart
//
// Works out whether a member's birthday greeting should be showing.
//
// Deliberately pure and synchronous: the whole birthday feature runs off
// this one function when the member opens the app, which is why there is no
// scheduler, no cron and nothing sent anywhere.

import 'package:lzcas/data/models.dart';
import 'package:lzcas/utils/app_clock.dart';

/// Whether [birthday] falls inside the [windowDays]-day greeting window
/// ending at [now], and if so which year's greeting it is.
///
/// Returns null when the member has no usable birthday or is outside the
/// window.
///
/// Three cases this has to get right, none of them obvious:
///
///  * **Year wrap.** A 20 December birthday is still inside a 30-day window
///    on 5 January. Comparing month-and-day breaks exactly there, so this
///    builds both this year's and last year's occurrence and takes the most
///    recent one that has already happened.
///  * **29 February.** In a common year that date does not exist. Dart's
///    `DateTime(2027, 2, 29)` silently rolls forward to 1 March, which would
///    hand those members a greeting on the wrong day; this pins the
///    occurrence to 28 February instead, so they get one every year.
///  * **Unparseable text.** `members.birthday` is a text column. The picker
///    writes `yyyy-MM-dd`, but older and imported rows may hold anything.
///    Anything that will not parse returns null rather than guessing.
BirthdayGreeting? birthdayGreetingFor(
  String? birthday, {
  DateTime? now,
  int windowDays = 30,
}) {
  final parsed = parseBirthday(birthday);
  if (parsed == null) return null;

  // Server-corrected, for the same reason Announcement.isCurrent is: a wrong
  // device clock would otherwise shift the whole greeting window.
  final at = _dateOnly(now ?? AppClock.now());

  // The most recent occurrence that is not in the future. Checking last year
  // as well is what carries a December birthday across into January.
  for (final year in [at.year, at.year - 1]) {
    final occurred = _occurrenceIn(year, parsed.month, parsed.day);
    if (occurred.isAfter(at)) continue;

    final daysSince = at.difference(occurred).inDays;
    if (daysSince >= windowDays) return null;

    return BirthdayGreeting(
      year: year,
      occurredOn: occurred,
      daysSince: daysSince,
    );
  }

  return null;
}

/// Parse the stored birthday text. Accepts what the picker writes
/// (`yyyy-MM-dd`) plus anything else `DateTime.parse` understands, which
/// covers the ISO timestamps some imported rows carry.
///
/// Returns null for blank, malformed or nonsense values — those members show
/// up in the admin screen's "no birthday recorded" count rather than
/// silently getting nothing.
DateTime? parseBirthday(String? raw) {
  final text = raw?.trim() ?? '';
  if (text.isEmpty) return null;

  final parsed = DateTime.tryParse(text);
  if (parsed == null) return null;

  // A year of 1 or 0 means something was stored that parses but is not a
  // real date of birth; treat it as missing rather than celebrating it.
  if (parsed.year < 1900) return null;

  return _dateOnly(parsed);
}

/// This year's occurrence of a birthday, with 29 February pinned to the 28th
/// in common years.
///
/// Without the pin, `DateTime(2027, 2, 29)` rolls forward to 1 March — the
/// greeting would arrive a day late and, worse, `daysSince` would go
/// negative on 29 February itself in a leap year.
DateTime _occurrenceIn(int year, int month, int day) {
  if (month == 2 && day == 29 && !_isLeapYear(year)) {
    return DateTime(year, 2, 28);
  }
  return DateTime(year, month, day);
}

bool _isLeapYear(int year) =>
    (year % 4 == 0 && year % 100 != 0) || year % 400 == 0;

/// Strip the time so day arithmetic is not thrown off by clock time or a
/// daylight-saving shift mid-window.
DateTime _dateOnly(DateTime d) => DateTime(d.year, d.month, d.day);
