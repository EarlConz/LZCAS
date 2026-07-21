// lib/services/config_service.dart
// Loads app_config from Supabase and exposes typed getters for global settings.
// Registered as a ChangeNotifierProvider in main.dart.

import 'package:flutter/foundation.dart';
import '../db/db.dart';

class ConfigService extends ChangeNotifier {
  Map<String, String> _config = {};

  /// Category name → its own low-stock threshold. Categories without a
  /// value are absent here and fall back to [lowStockThreshold].
  Map<String, int> _categoryThresholds = {};
  bool _loaded = false;

  /// Defaults match AppConfigDefaults in models.dart.

  /// Safety-net threshold for items with no category of their own (e.g.
  /// legacy or CSV-imported rows). Categories carry their own required
  /// threshold, so there is no admin-configurable default anymore.
  static const int fallbackThreshold = 50;

  /// Effective low-stock threshold for a given category, falling back to
  /// [fallbackThreshold] only for uncategorized items.
  int thresholdForCategory(String? category) {
    if (category != null && category.isNotEmpty) {
      final t = _categoryThresholds[category];
      if (t != null) return t;
    }
    return fallbackThreshold;
  }

  String get currencySymbol => (_config['currency_symbol'] ?? '').isNotEmpty
      ? _config['currency_symbol']!
      : '₱';

  bool get notificationsEnabled => _config['notifications_enabled'] != 'false';

  /// Fetches config once on startup.
  Future<void> load() async {
    if (_loaded) return;
    try {
      _config = await repository.fetchAppConfig();
      await _loadCategoryThresholds();
    } catch (_) {
      // Keep defaults
    }
    _loaded = true;
    notifyListeners();
  }

  /// Called after admin saves settings (or category changes) to refresh
  /// in-memory values.
  Future<void> refresh() async {
    try {
      _config = await repository.fetchAppConfig();
      await _loadCategoryThresholds();
    } catch (_) {}
    notifyListeners();
  }

  Future<void> _loadCategoryThresholds() async {
    final cats = await repository.fetchProductCategories();
    _categoryThresholds = {
      for (final c in cats)
        if (c.lowStockThreshold != null) c.name: c.lowStockThreshold!,
    };
  }
}
