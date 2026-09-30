// lib/services/push_service.dart
// Registers this phone for delivery push notifications (v58).
//
// Android only. The Firebase side lives in MainActivity.kt and is reached
// over the "gutvita/push" method channel; this file asks for permission,
// hands the phone's FCM token to the database after sign-in, and takes it
// back at sign-out. Sending is done by the order-push Edge Function.
//
// A session that simply expires, rather than signing out, leaves the token
// registered: the phone keeps receiving that account's alerts until someone
// signs in on it (register_push_token moves the token to them) or signs out.

import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../auth/auth.dart';
import '../db/db.dart';

class PushService {
  static const _channel = MethodChannel('gutvita/push');

  AuthState? _auth;

  /// The account this phone is currently registered for, so each sign-in
  /// registers once rather than on every auth notification.
  String? _registeredFor;

  static bool get _supported => !kIsWeb && Platform.isAndroid;

  /// Follow sign-in and sign-out. Safe to call once at startup.
  void start(AuthState auth) {
    if (!_supported || _auth != null) return;
    _auth = auth;
    auth.beforeLogout = unregister;
    auth.addListener(_onAuthChanged);
    _onAuthChanged();
  }

  void _onAuthChanged() {
    final auth = _auth;
    if (auth == null) return;
    final uid = auth.userId;
    if (auth.isAuthenticated && uid != null && uid != _registeredFor) {
      _registeredFor = uid;
      _register();
    } else if (!auth.isAuthenticated) {
      _registeredFor = null;
    }
  }

  Future<void> _register() async {
    try {
      // Declining is fine: the app works, it just stays quiet while closed.
      await _channel.invokeMethod<bool>('requestPermission');
      final token = await _channel.invokeMethod<String>('getToken');
      if (token == null || token.isEmpty) return;
      await repository.registerPushToken(token);
    } catch (e) {
      // No Firebase, no network, or a database without v58: log only.
      debugPrint('[PushService] register failed: $e');
      _registeredFor = null;
    }
  }

  /// Called by [AuthState.logout] while the session is still valid, so the
  /// database call is allowed. Never blocks the sign-out on failure.
  Future<void> unregister() async {
    if (!_supported) return;
    try {
      final token = await _channel.invokeMethod<String>('getToken');
      if (token != null && token.isNotEmpty) {
        await repository.unregisterPushToken(token);
      }
      await _channel.invokeMethod<void>('deleteToken');
    } catch (e) {
      debugPrint('[PushService] unregister failed: $e');
    }
    _registeredFor = null;
  }
}
