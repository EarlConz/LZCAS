// lib/services/config_service.dart
// Loads app_config from Supabase and exposes typed getters for global settings.
// Registered as a ChangeNotifierProvider in main.dart.

import 'package:flutter/foundation.dart';
import '../db/db.dart';

class ConfigService extends ChangeNotifier {
  Map<String, String> _config = {};
  bool _loaded = false;

  /// Defaults match AppConfigDefaults in models.dart.

  int get lowStockThreshold =>
      int.tryParse(_config['low_stock_threshold'] ?? '') ?? 50;

  int get borrowDurationDays =>
      int.tryParse(_config['borrow_duration_days'] ?? '') ?? 10;

  int get overdueThresholdDays =>
      int.tryParse(_config['overdue_threshold_days'] ?? '') ?? 10;

  String get currencySymbol => (_config['currency_symbol'] ?? '').isNotEmpty
      ? _config['currency_symbol']!
      : '₱';

  bool get notificationsEnabled => _config['notifications_enabled'] != 'false';

  /// Fetches config once on startup.
  Future<void> load() async {
    if (_loaded) return;
    try {
      _config = await repository.fetchAppConfig();
    } catch (_) {
      // Keep defaults
    }
    _loaded = true;
    notifyListeners();
  }

  /// Called after admin saves settings to refresh in-memory values.
  Future<void> refresh() async {
    try {
      _config = await repository.fetchAppConfig();
    } catch (_) {}
    notifyListeners();
  }
}
