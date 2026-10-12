// lib/services/ui_prefs.dart
//
// Small screen preferences remembered on this device: which parts of a
// page someone folded away. A JSON file in the app's support folder, read
// once and written on each change.
//
// Never the place for anything that matters if it is lost: a missing or
// unreadable file just means every part starts in its default state.

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

class UiPrefs extends ChangeNotifier {
  UiPrefs._();
  static final UiPrefs instance = UiPrefs._();

  final Map<String, Object?> _values = {};
  Future<void>? _loading;
  Future<void> _writing = Future.value();

  Future<File> _file() async {
    final dir = await getApplicationSupportDirectory();
    return File('${dir.path}${Platform.pathSeparator}ui_prefs.json');
  }

  /// Read the file once; later calls return the same future. Listeners are
  /// told when it lands, so a screen built before it can redraw.
  Future<void> load() => _loading ??= _read();

  Future<void> _read() async {
    if (kIsWeb) return;
    try {
      final f = await _file();
      if (!await f.exists()) return;
      final data = jsonDecode(await f.readAsString());
      if (data is Map<String, dynamic>) {
        // Anything set before the file arrived wins: it is newer.
        for (final e in data.entries) {
          _values.putIfAbsent(e.key, () => e.value);
        }
        notifyListeners();
      }
    } catch (e) {
      debugPrint('[UiPrefs] could not read: $e');
    }
  }

  bool flag(String key, {required bool fallback}) {
    final v = _values[key];
    return v is bool ? v : fallback;
  }

  void setFlag(String key, bool value) {
    if (_values[key] == value) return;
    _values[key] = value;
    notifyListeners();
    _save();
  }

  /// Writes one after another, so an older snapshot never lands last.
  void _save() {
    if (kIsWeb) return;
    final snapshot = jsonEncode(_values);
    _writing = _writing.then((_) async {
      try {
        final f = await _file();
        await f.parent.create(recursive: true);
        await f.writeAsString(snapshot, flush: true);
      } catch (e) {
        debugPrint('[UiPrefs] could not save: $e');
      }
    });
  }
}

/// The Delivery Orders page's folds (calmer screen design, 2026-10-02).
/// Defaults are the calm state: summary as chips, steps as one line, map,
/// payment note and items folded; the order list open.
class DeliveryFolds {
  DeliveryFolds._();

  static const summary = 'delivery.summaryOpen';
  static const list = 'delivery.listOpen';
  static const steps = 'delivery.stepsOpen';
  static const map = 'delivery.mapOpen';
  static const payment = 'delivery.paymentOpen';
  static const items = 'delivery.itemsOpen';

  static bool isOpen(String key) =>
      UiPrefs.instance.flag(key, fallback: key == list);

  static void toggle(String key) =>
      UiPrefs.instance.setFlag(key, !isOpen(key));
}
