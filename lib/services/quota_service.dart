// lib/services/quota_service.dart
// Reactive quota status — fetches on init and auto-refreshes
// whenever a borrow is updated (triggers remittance).

import 'dart:async';
import 'package:flutter/foundation.dart';
import '../db/db.dart';

class QuotaProvider extends ChangeNotifier {
  StreamSubscription<String>? _changeSub;

  DateTime? _quotaValidUntil;
  DateTime? _lastRemittanceAt;
  bool _loading = true;
  String? _error;

  DateTime? get quotaValidUntil => _quotaValidUntil;
  DateTime? get lastRemittanceAt => _lastRemittanceAt;
  bool get loading => _loading;
  String? get error => _error;

  bool get hasQuota => _quotaValidUntil != null;

  bool get isOverdue {
    if (_quotaValidUntil == null) return false;
    return _quotaValidUntil!.isBefore(DateTime.now());
  }

  /// Whole days left before the deadline. Never negative — overdue is 0.
  int get daysRemaining {
    if (_quotaValidUntil == null || isOverdue) return 0;
    return _quotaValidUntil!.difference(DateTime.now()).inDays;
  }

  /// Hours remaining after subtracting whole days (0–23). Never negative.
  int get remainingHours {
    if (_quotaValidUntil == null || isOverdue) return 0;
    final diff = _quotaValidUntil!.difference(DateTime.now());
    return diff.inHours - (diff.inDays * 24);
  }

  /// Formatted time left: "3 days 5 hrs" or "2 hrs".
  /// Only meaningful while not overdue — see [overdueLabel] for the
  /// magnitude of time past the deadline.
  String get daysHoursLabel => _dayHourLabel(daysRemaining, remainingHours);

  /// Magnitude of time past the deadline: "5 hrs", "2 days 3 hrs".
  /// Empty string when the quota is not overdue.
  String get overdueLabel {
    if (_quotaValidUntil == null || !isOverdue) return '';
    final diff = DateTime.now().difference(_quotaValidUntil!);
    final d = diff.inDays;
    return _dayHourLabel(d, diff.inHours - (d * 24));
  }

  String _dayHourLabel(int d, int h) {
    if (d <= 0 && h <= 0) return 'less than 1 hr';
    final p = <String>[];
    if (d > 0) p.add('$d day${d == 1 ? '' : 's'}');
    if (h > 0) p.add('$h hr${h == 1 ? '' : 's'}');
    return p.join(' ');
  }

  double get quotaFraction {
    if (_quotaValidUntil == null) return 0.0;
    final total = _quotaValidUntil!.difference(_effectiveStart).inSeconds;
    if (total <= 0) return 0.0;
    final elapsed = DateTime.now().difference(_effectiveStart).inSeconds;
    return ((total - elapsed) / total).clamp(0.0, 1.0);
  }

  DateTime get _effectiveStart {
    return _lastRemittanceAt ??
        DateTime.now().subtract(const Duration(days: 7));
  }

  /// Fetch quota for a member, then listen for borrow changes to auto-reload.
  void subscribe(int memberId) {
    _cancelSub();
    _loading = true;
    _error = null;
    notifyListeners();

    // Initial fetch
    _fetch(memberId);

    // Auto-reload whenever a borrow is updated (covers remittance)
    _changeSub = repository.changes.listen((event) {
      if (event == 'borrow_updated' || event == 'borrows_changed') {
        _fetch(memberId);
      }
    });
  }

  Future<void> _fetch(int memberId) async {
    try {
      final member = await repository.getMemberById(memberId);
      _quotaValidUntil = member?.quotaValidUntil;
      _lastRemittanceAt = member?.lastRemittanceAt;
      _error = null;
    } catch (e) {
      debugPrint('[QuotaProvider] fetch error: $e');
      if (_quotaValidUntil == null) {
        _error = 'Failed to load quota status';
      }
    } finally {
      _loading = false;
      notifyListeners();
    }
  }

  void _cancelSub() {
    _changeSub?.cancel();
    _changeSub = null;
  }

  void clear() {
    _cancelSub();
    _quotaValidUntil = null;
    _lastRemittanceAt = null;
    _loading = true;
    _error = null;
    notifyListeners();
  }

  @override
  void dispose() {
    _cancelSub();
    super.dispose();
  }
}
