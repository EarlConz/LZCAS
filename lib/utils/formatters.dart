import 'package:intl/intl.dart';

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
