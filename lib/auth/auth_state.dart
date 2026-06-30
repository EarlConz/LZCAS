// lib/auth/auth_state.dart
// Cloud-based authentication using Supabase Auth (email/password).

import 'dart:async';
import 'dart:io' show Platform;
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

  /// True when running on a mobile OS (Android / iOS), false on desktop or web.
  bool get _isMobilePlatform {
    if (kIsWeb) return false;
    return Platform.isAndroid || Platform.isIOS;
  }

  /// If the current platform is mobile and the loaded role is not admin,
  /// force-sign-out and block access.
  bool get _mobileBlocked => _isMobilePlatform && _userRole != UserRole.admin;

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
        // No profile row — auto-create one via handle_new_user trigger won't
        // fire on re-login. Default to cashier but log so we can diagnose.
        debugPrint(
          '[Stockpile] No profile row for uid=$uid — defaulting to cashier',
        );
        _userRole = UserRole.cashier;
      }
    } catch (e) {
      debugPrint('[Stockpile] Failed to load profile for uid=$uid: $e');
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

    // Resolve username/email input:
    //   "john@abc.com"  → used directly (already an email)
    //   "john"          → profiles.email or fallback to john@lzcas.local
    var loginEmail = email.trim();
    if (!loginEmail.contains('@')) {
      String? profilesEmail;
      try {
        final profile = await _sb
            .from('profiles')
            .select('email')
            .eq('username', loginEmail)
            .maybeSingle();
        profilesEmail = profile?['email'] as String?;
      } catch (_) {}
      loginEmail = (profilesEmail != null && profilesEmail.isNotEmpty)
          ? profilesEmail
          : '$loginEmail@lzcas.local';
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

        // ── Mobile gate: only Admin accounts allowed on phones/tablets ──
        if (_mobileBlocked) {
          await _sb.auth.signOut();
          _error = 'Mobile Access is for Admin Only';
          _status = AuthStatus.authError;
          notifyListeners();
          return false;
        }

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
          debugPrint(
            '[Stockpile] tryRestoreSession: no profile row for uid=${s.user.id}',
          );
          _userRole = UserRole.cashier;
        }
      } catch (e) {
        debugPrint(
          '[Stockpile] tryRestoreSession: profile query failed for uid=${s.user.id}: $e',
        );
        _userRole = UserRole.cashier;
      }
      _status = AuthStatus.authenticated;
      notifyListeners();

      // ── Mobile gate: only Admin accounts allowed on phones/tablets ──
      if (_mobileBlocked) {
        await _sb.auth.signOut();
        return false;
      }

      return true;
    } catch (_) {
      return false;
    }
  }

  // ── Logout ───────────────────────────────────────────────────────────────

  Future<void> logout() async {
    try {
      await _sb.auth.signOut(); // onAuthStateChange handler resets everything
    } catch (_) {
      // Only reset if signOut itself failed (network error)
      _status = AuthStatus.unauthenticated;
      _userRole = null;
      _username = '';
      _userId = null;
      _error = '';
      notifyListeners();
    }
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
    String? username,
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
          'username': username ?? email,
        },
      );
      if (result.status == 200) return true;

      // Extract error message from the Edge Function response body
      if (result.data is Map) {
        _error =
            (result.data as Map)['error']?.toString() ??
            'Failed to create user (status ${result.status}).';
      } else {
        _error = 'Failed to create user (status ${result.status}).';
      }
      return false;
    } catch (e) {
      _error = 'Could not create user: $e';
      return false;
    }
  }

  // ── Fetch Users ──────────────────────────────────────────────────────────

  Future<List<Map<String, dynamic>>> fetchUsers() async {
    if (_userRole != UserRole.admin) return [];
    try {
      final data = await _sb
          .from('profiles')
          .select()
          .order('created_at', ascending: false);
      return List<Map<String, dynamic>>.from(data);
    } catch (_) {
      return [];
    }
  }

  // ── Delete User ──────────────────────────────────────────────────────────

  Future<bool> deleteUser(String userId) async {
    if (_userRole != UserRole.admin) {
      _error = 'Only admins can delete users.';
      return false;
    }
    try {
      final result = await _sb.functions.invoke(
        'delete-user',
        body: {'user_id': userId},
      );
      if (result.status == 200) return true;
      if (result.data is Map) {
        _error =
            (result.data as Map)['error']?.toString() ??
            'Failed to delete user (status ${result.status}).';
      } else {
        _error = 'Failed to delete user (status ${result.status}).';
      }
      return false;
    } catch (e) {
      _error = 'Could not delete user: $e';
      return false;
    }
  }

  @override
  void dispose() {
    _authSubscription?.cancel();
    super.dispose();
  }
}
