// lib/utils/action_guard.dart
//
// Guards mutating actions against accidental double-clicks / double-submits.
//
// A rapid second tap that fires while the first call is still running — or
// within a short cooldown after it finishes — is ignored, so the action can't
// produce duplicate records (double sale, double bonus, double member, double
// withdrawal approval, etc.).
//
// Usage on a button:
// ```dart
// onPressed: () => ActionGuard.run('save_package', () async {
//   ... // the mutating work
// }),
// ```
// Use a key that is unique per logical action. For per-record actions include
// the id, e.g. 'approve_withdrawal_$id', so distinct records aren't blocked.
class ActionGuard {
  ActionGuard._();

  static final Set<String> _inFlight = <String>{};
  static final Map<String, DateTime> _finishedAt = <String, DateTime>{};

  /// Runs [action] unless a call with the same [key] is already in flight or
  /// finished within [cooldown]. Returns the action's result, or null if the
  /// call was skipped as a duplicate.
  static Future<T?> run<T>(
    String key,
    Future<T> Function() action, {
    Duration cooldown = const Duration(milliseconds: 600),
  }) async {
    if (_inFlight.contains(key)) return null;
    final finished = _finishedAt[key];
    if (finished != null && DateTime.now().difference(finished) < cooldown) {
      return null;
    }
    _inFlight.add(key);
    try {
      return await action();
    } finally {
      _inFlight.remove(key);
      _finishedAt[key] = DateTime.now();
    }
  }

  /// True while an action with [key] is currently running — handy for
  /// disabling/spinner UI in a StatefulWidget if desired.
  static bool isRunning(String key) => _inFlight.contains(key);
}
