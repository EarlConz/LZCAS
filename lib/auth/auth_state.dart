// lib/auth/auth_state.dart
// Cloud-based authentication using Supabase Auth (email/password).

import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../data/models.dart';

// ── Enums ───────────────────────────────────────────────────────────────────

enum AuthStatus { unauthenticated, authenticating, authenticated, authError }

enum UserRole {
  admin('Admin'),
  inventory('Inventory'),
  cashier('Cashier');

  final String displayName;
  const UserRole(this.displayName);

  static UserRole fromString(String raw) {
    switch (raw.trim().toLowerCase()) {
      case 'admin':
        return UserRole.admin;
      case 'inventory':
        return UserRole.inventory;
      case 'cashier':
        return UserRole.cashier;
      default:
        throw ArgumentError('Unknown role: $raw');
    }
  }
}

// ── AuthState ───────────────────────────────────────────────────────────────

class AuthState extends ChangeNotifier {
  final SupabaseClient _sb;

  AuthStatus _status = AuthStatus.unauthenticated;
  UserRole? _userRole;
  String _username = '';
  String _error = '';
  String? _userId;

  StreamSubscription? _authSubscription;

  AuthState({required SupabaseClient supabase}) : _sb = supabase {
    _authSubscription = _sb.auth.onAuthStateChange.listen((event) {
      _onAuthChanged(event.event, event.session);
    });
    _trySyncSession();
  }

  // ── Getters ──────────────────────────────────────────────────────────────

  AuthStatus get status => _status;
  bool get isAuthenticated => _status == AuthStatus.authenticated;
  bool get isLoading => _status == AuthStatus.authenticating;
  UserRole? get userRole => _userRole;
  String get username => _username;
  String get error => _error;
  String? get userId => _userId;
  SupabaseClient get sb => _sb;
  bool get isTempAdmin => false;

  // ── Session Sync ─────────────────────────────────────────────────────────

  void _trySyncSession() {
    final s = _sb.auth.currentSession;
    if (s != null) {
      _userId = s.user.id;
      _username = s.user.email ?? '';
      _loadUserProfile(s.user.id);
    }
  }

  void _onAuthChanged(AuthChangeEvent event, Session? session) {
    switch (event) {
      case AuthChangeEvent.signedIn:
        if (session != null) {
          _userId = session.user.id;
          _username = session.user.email ?? '';
          _loadUserProfile(session.user.id);
        }
        break;
      case AuthChangeEvent.tokenRefreshed:
        if (session != null) _userId = session.user.id;
        break;
      case AuthChangeEvent.signedOut:
        _status = AuthStatus.unauthenticated;
        _userRole = null;
        _username = '';
        _userId = null;
        _error = '';
        notifyListeners();
        break;
      case AuthChangeEvent.userUpdated:
      case AuthChangeEvent.userDeleted:
      case AuthChangeEvent.passwordRecovery:
      case AuthChangeEvent.mfaChallengeVerified:
      case AuthChangeEvent.initialSession:
        break;
    }
  }

  Future<void> _loadUserProfile(String uid) async {
    try {
      final data = await _sb
          .from('profiles')
          .select()
          .eq('id', uid)
          .maybeSingle();
      if (data != null) {
        final profile = UserProfile.fromJson(data);
        _userRole = UserRole.fromString(profile.role);
        _username = profile.username.isNotEmpty ? profile.username : _username;
      } else {
        _userRole = UserRole.cashier;
      }
    } catch (_) {
      _userRole = UserRole.cashier;
    }
    _status = AuthStatus.authenticated;
    notifyListeners();
  }

  // ── Login ────────────────────────────────────────────────────────────────

  Future<bool> login(String email, String password) async {
    _status = AuthStatus.authenticating;
    _error = '';
    notifyListeners();

    // Allow shorthand: "admin" maps to admin@stockpile.local
    var loginEmail = email.trim();
    if (loginEmail == 'admin') {
      loginEmail = 'admin@stockpile.local';
    }

    try {
      final response = await _sb.auth.signInWithPassword(
        email: loginEmail,
        password: password,
      );
      if (response.user != null) {
        _userId = response.user!.id;
        _username = response.user!.email ?? email;
        await _loadUserProfile(response.user!.id);
        return _status == AuthStatus.authenticated;
      }
      _error = 'Login failed.';
      _status = AuthStatus.authError;
      notifyListeners();
      return false;
    } on AuthException catch (e) {
      _error = e.message.isNotEmpty ? e.message : 'Invalid credentials.';
      _status = AuthStatus.authError;
      notifyListeners();
      return false;
    } catch (_) {
      _error = 'Connection error. Check your internet.';
      _status = AuthStatus.authError;
      notifyListeners();
      return false;
    }
  }

  // ── Session Restore ──────────────────────────────────────────────────────

  Future<bool> tryRestoreSession() async {
    try {
      final s = _sb.auth.currentSession;
      if (s == null) return false;
      _userId = s.user.id;
      _username = s.user.email ?? '';
      try {
        final data = await _sb
            .from('profiles')
            .select()
            .eq('id', s.user.id)
            .maybeSingle();
        if (data != null) {
          final profile = UserProfile.fromJson(data);
          _userRole = UserRole.fromString(profile.role);
          _username = profile.username.isNotEmpty
              ? profile.username
              : _username;
        } else {
          _userRole = UserRole.cashier;
        }
      } catch (_) {
        _userRole = UserRole.cashier;
      }
      _status = AuthStatus.authenticated;
      notifyListeners();
      return true;
    } catch (_) {
      return false;
    }
  }

  // ── Logout ───────────────────────────────────────────────────────────────

  Future<void> logout() async {
    try {
      await _sb.auth.signOut();
    } catch (_) {}
    _status = AuthStatus.unauthenticated;
    _userRole = null;
    _username = '';
    _userId = null;
    _error = '';
    notifyListeners();
  }

  Future<void> forceLogout() async {
    _status = AuthStatus.unauthenticated;
    _userRole = null;
    _username = '';
    _userId = null;
    _error = '';
    notifyListeners();
  }

  // ── User Management ──────────────────────────────────────────────────────

  Future<bool> createUser({
    required String email,
    required String password,
    required UserRole role,
  }) async {
    if (_userRole != UserRole.admin) {
      _error = 'Only admins can create users.';
      return false;
    }
    try {
      final result = await _sb.functions.invoke(
        'create-user',
        body: {
          'email': email,
          'password': password,
          'role': role.name,
          'username': email,
        },
      );
      if (result.status == 200) return true;
      _error = 'Failed to create user.';
      return false;
    } catch (e) {
      _error = 'Could not create user: $e';
      return false;
    }
  }

  @override
  void dispose() {
    _authSubscription?.cancel();
    super.dispose();
  }
}
