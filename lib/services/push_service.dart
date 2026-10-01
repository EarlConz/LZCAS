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
//
// The token is registered again every time the app comes to the
// foreground. Registering is an upsert, so it costs one small call, and it
// covers what a once-per-sign-in registration missed: a first attempt that
// failed (no network yet, or a session still being restored after an app
// update), and a token Firebase rotated in the meantime.

import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart' show AppLifecycleListener;

import '../auth/auth.dart';
import '../db/db.dart';

class PushService {
  static const _channel = MethodChannel('gutvita/push');

  AuthState? _auth;

  /// The account this phone is currently registered for, so each sign-in
  /// registers once rather than on every auth notification.
  String? _registeredFor;

  /// Whether the permission prompt has been shown this run: asked once,
  /// not on every return to the app.
  bool _askedPermission = false;

  static bool get _supported => !kIsWeb && Platform.isAndroid;

  /// Follow sign-in and sign-out. Safe to call once at startup.
  void start(AuthState auth) {
    if (!_supported || _auth != null) return;
    _auth = auth;
    auth.beforeLogout = unregister;
    auth.addListener(_onAuthChanged);
    // Lives as long as the app: PushService is started once, at boot.
    AppLifecycleListener(onResume: _onResume);
    _onAuthChanged();
  }

  void _onResume() {
    final auth = _auth;
    if (auth == null || !auth.isAuthenticated || auth.userId == null) return;
    _registeredFor = auth.userId;
    _register();
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
      // The token first: it does not depend on the permission, and a prompt
      // left open must not hold up the registration.
      final token = await _channel.invokeMethod<String>('getToken');
      if (token != null && token.isNotEmpty) {
        await repository.registerPushToken(token);
      }
    } catch (e) {
      // No Firebase, no network, or a database without v58: log only. The
      // next return to the app tries again.
      debugPrint('[PushService] register failed: $e');
      _registeredFor = null;
    }
    if (_askedPermission) return;
    _askedPermission = true;
    try {
      // Declining is fine: the app works, it just stays quiet while closed.
      await _channel.invokeMethod<bool>('requestPermission');
    } catch (e) {
      debugPrint('[PushService] permission request failed: $e');
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
