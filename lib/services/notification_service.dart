// lib/services/notification_service.dart
// In-app notification service for admins.
// Listens to repository change events and Supabase Realtime to track
// pending requests, low stock, overdue borrows, and new members in real time.

import 'dart:async';
import 'package:flutter/foundation.dart';
import '../data/supabase_repository.dart';
import '../data/models.dart';
import '../db/db.dart';
import 'config_service.dart';

class NotificationService extends ChangeNotifier {
  StreamSubscription<String>? _changeSub;
  ConfigService? _config;

  int _pendingCount = 0;
  int _lowStockCount = 0;
  int _overdueCount = 0;
  DateTime? _lastSeenAt;
  bool _initialized = false;

  int get pendingCount =>
      _config?.notificationsEnabled == false ? 0 : _pendingCount;
  int get lowStockCount =>
      _config?.notificationsEnabled == false ? 0 : _lowStockCount;
  int get overdueCount =>
      _config?.notificationsEnabled == false ? 0 : _overdueCount;
  int get totalCount => _config?.notificationsEnabled == false
      ? 0
      : _pendingCount + _lowStockCount + _overdueCount;
  bool get hasNotifications => totalCount > 0;

  /// Timestamp of last "mark all seen" — used by UI to dim read items.
  DateTime? get lastSeenAt => _lastSeenAt;

  /// Initialize the service — fetch current counts and start listening.
  Future<void> init({ConfigService? config}) async {
    if (_initialized) return;
    _initialized = true;
    _config = config;

    // Re-compute all counts when settings change
    _config?.addListener(_onConfigChanged);

    await Future.wait([
      _refreshPending(),
      _refreshLowStock(),
      _refreshOverdue(),
    ]);

    _changeSub = repository.changes.listen((event) {
      if (_config?.notificationsEnabled == false) return;
      switch (event) {
        case 'pending_request_added':
        case 'pending_request_approved':
        case 'pending_request_rejected':
        case 'pending_requests_changed':
          _refreshPending();
          break;
        case 'items_changed':
        case 'stock_movement_added':
          _refreshLowStock();
          break;
        case 'borrow_added':
        case 'borrow_updated':
        case 'borrows_changed':
          _refreshOverdue();
          break;
        case 'cloud_restored':
          _refreshPending();
          _refreshLowStock();
          _refreshOverdue();
          break;
      }
    });
  }

  void _onConfigChanged() {
    Future.wait([_refreshPending(), _refreshLowStock(), _refreshOverdue()]);
  }

  Future<void> _refreshPending() async {
    try {
      final count = await repository.fetchPendingCount();
      if (_pendingCount != count) {
        _pendingCount = count;
        notifyListeners();
      }
    } catch (_) {}
  }

  Future<void> _refreshLowStock() async {
    try {
      final items = await repository.fetchItems();
      final threshold = _config?.lowStockThreshold ?? 50;
      final count = items
          .where((i) => i.stock < threshold && i.stock > 0)
          .length;
      if (_lowStockCount != count) {
        _lowStockCount = count;
        notifyListeners();
      }
    } catch (_) {}
  }

  Future<void> _refreshOverdue() async {
    try {
      final borrows = await repository.fetchOverdueBorrows();
      if (_overdueCount != borrows.length) {
        _overdueCount = borrows.length;
        notifyListeners();
      }
    } catch (_) {}
  }

  /// Mark all notifications as seen (called when user opens the panel or views all).
  void markAllSeen() {
    _lastSeenAt = DateTime.now();
    _pendingCount = 0;
    notifyListeners();
  }

  /// Reset the pending badge count (called when admin views requests).
  @Deprecated('Use markAllSeen() instead')
  void markPendingSeen() => markAllSeen();

  @override
  void dispose() {
    _changeSub?.cancel();
    super.dispose();
  }
}
