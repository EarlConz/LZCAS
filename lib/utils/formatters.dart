import 'package:intl/intl.dart';

/// "Today", "3 days ago", "2 weeks ago", "5 months ago".
///
/// Rounds down deliberately — a notice from 13 days ago reads "1 week ago"
/// rather than "2 weeks ago", so it never sounds older than it is. Past
/// roughly a year it gives up and shows the date, since "14 months ago"
/// tells a reader less than "12 Aug 2025".
String formatRelativeDate(DateTime? dt) {
  if (dt == null) return '';
  final local = dt.toLocal();
  final today = DateTime.now();
  final days = DateTime(today.year, today.month, today.day)
      .difference(DateTime(local.year, local.month, local.day))
      .inDays;

  if (days < 0) return DateFormat('d MMMM').format(local); // scheduled ahead
  if (days == 0) return 'Today';
  if (days == 1) return 'Yesterday';
  if (days < 7) return '$days days ago';
  if (days < 14) return '1 week ago';
  if (days < 31) return '${days ~/ 7} weeks ago';
  if (days < 62) return '1 month ago';
  if (days < 365) return '${days ~/ 30} months ago';
  return DateFormat('d MMM yyyy').format(local);
}

/// "21 August" — the day a thing happened, without the year.
String formatDayAndMonth(DateTime? dt) =>
    dt == null ? '' : DateFormat('d MMMM').format(dt.toLocal());

String formatDisplayDate(DateTime? dt) {
  if (dt == null) return '';
  try {
    // Normalize clearly incorrect dates that come from mixed epoch units.
    // Some import paths may have stored microseconds since epoch in the
    // timestamp column which Drift later interpreted as milliseconds.
    // That yields a DateTime far in the future (year >> 3000). Detect that
    // and correct by scaling down.
    var candidate = dt.toLocal();
    final nowMs = DateTime.now().millisecondsSinceEpoch;
    final candMs = candidate.millisecondsSinceEpoch;
    // If candidate milliseconds is unreasonably large (e.g. > 100x now),
    // assume it actually represents microseconds and divide by 1000.
    if (candMs > nowMs * 100) {
      final corrected = DateTime.fromMillisecondsSinceEpoch(candMs ~/ 1000).toLocal();
      return DateFormat('MM/dd/yyyy hh:mma').format(corrected);
    }
    // If year is absurdly large, also attempt correction.
    if (candidate.year > 3000) {
      final corrected = DateTime.fromMillisecondsSinceEpoch(candMs ~/ 1000).toLocal();
      return DateFormat('MM/dd/yyyy hh:mma').format(corrected);
    }
    return DateFormat('MM/dd/yyyy hh:mma').format(candidate);
  } catch (_) {
    return dt.toString();
  }
}
