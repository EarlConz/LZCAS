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

  // ── Birthday greetings (v36) ────────────────────────────────────────
  // Kept in app_config so the wording and the window can be changed without
  // shipping a new build.

  bool get birthdayGreetingsEnabled =>
      _config['birthday_greetings_enabled'] != 'false';

  /// How long a greeting stays on the member's Overview after the day
  /// itself. Clamped because a value typed into settings drives a date
  /// window: zero would show nothing at all, and a year would never clear.
  int get birthdayGreetingDays {
    final raw = int.tryParse(_config['birthday_greeting_days'] ?? '');
    return (raw ?? 30).clamp(1, 180);
  }

  static const String _defaultBirthdayMessage =
      'Everyone at GUTVita wishes you all the best for the year ahead. '
      'Thank you for being part of the team.';

  /// The greeting's words.
  ///
  /// The built-in wording fills in for a blank message ONLY when there is no
  /// poster (v44). With one, a blank message is a deliberate choice — the
  /// poster says it all — and substituting a default would print text over
  /// an image the client designed to stand alone.
  String get birthdayGreetingMessage {
    final raw = (_config['birthday_greeting_message'] ?? '').trim();
    if (raw.isNotEmpty) return raw;
    return birthdayGreetingHasImage ? '' : _defaultBirthdayMessage;
  }

  /// Storage path of the greeting poster, or '' for a text-only greeting.
  /// One image for everyone, alongside the one message — greetings are
  /// computed per member, but not authored per member.
  String get birthdayGreetingImage =>
      (_config['birthday_greeting_image'] ?? '').trim();

  bool get birthdayGreetingHasImage => birthdayGreetingImage.isNotEmpty;

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
