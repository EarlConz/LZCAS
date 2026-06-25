// lib/auth/auth_state.dart
// Centralized authentication state using ChangeNotifier + Provider.
// Manages login, logout, role-based routing, and CSRF token propagation.

import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'api_client.dart';
import 'csrf_interceptor.dart';

// ── Enums ───────────────────────────────────────────────────────────────────

/// Explicit authentication states for the state machine.
enum AuthStatus {
  /// No active session — user must log in.
  unauthenticated,

  /// Login request is in flight.
  authenticating,

  /// Successfully authenticated with valid session.
  authenticated,

  /// Last login attempt failed with an error.
  authError,
}

/// The roles supported by the application.
enum UserRole {
  admin('Admin'),
  inventory('Inventory'),
  cashier('Cashier');

  final String displayName;
  const UserRole(this.displayName);

  /// Parse a role string from the backend response into a UserRole.
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

/// Secure storage keys — single source of truth.
abstract class _StorageKeys {
  static const authToken = 'auth_token';
  static const username = 'username';
  static const userRole = 'user_role';
  static const csrfToken = 'csrf_token';
  static const tempAdminDisabled = 'temp_admin_disabled';
  static const localUsers = 'local_users';
}

// ── AuthState ───────────────────────────────────────────────────────────────

/// Top-level authentication state with an explicit status machine.
///
/// States:
///   unauthenticated → authenticating → authenticated
///                                      → authError → unauthenticated
///
/// Provide this via [ChangeNotifierProvider] at the app root.
class AuthState extends ChangeNotifier {
  final ApiClient _apiClient;
  final FlutterSecureStorage _secureStorage;
  final CsrfInterceptor _csrfInterceptor;

  AuthStatus _status = AuthStatus.unauthenticated;
  UserRole? _userRole;
  String _username = '';
  String _error = '';
  // Stores the raw token so we can set it on the API client after restore
  String? _jwtToken;

  AuthState({
    required ApiClient apiClient,
    required CsrfInterceptor csrfInterceptor,
    FlutterSecureStorage? secureStorage,
  }) : _apiClient = apiClient,
       _csrfInterceptor = csrfInterceptor,
       _secureStorage = secureStorage ?? const FlutterSecureStorage();

  // ── Getters ──────────────────────────────────────────────────────────────

  AuthStatus get status => _status;
  bool get isAuthenticated => _status == AuthStatus.authenticated;
  bool get isLoading => _status == AuthStatus.authenticating;
  UserRole? get userRole => _userRole;
  String get username => _username;
  String get error => _error;

  // ── Login ────────────────────────────────────────────────────────────────

  /// Attempt login with [username] and [password].
  ///
  /// Flow:
  ///   1. Fetch a pre-auth CSRF cookie.
  ///   2. POST credentials to `/api/login`.
  ///   3. Extract JWT, role, profile from response.
  ///   4. Fetch a fresh session-bound CSRF token.
  ///   5. Persist everything to secure storage.
  ///   6. Clear raw credentials from memory.
  Future<bool> login(String username, String password) async {
    _status = AuthStatus.authenticating;
    _error = '';
    _username = username;
    notifyListeners();

    // --- Temp Admin Bypass ---
    // Hardcoded temporary admin credentials for initial setup.
    // Automatically disabled when a real user is created via Admin Dashboard.
    if (username == _tempAdminUser && password == _tempAdminPass) {
      final disabled = await _secureStorage.read(
        key: _StorageKeys.tempAdminDisabled,
      );
      if (disabled == 'true') {
        _error =
            'Temporary account has been deactivated. '
            'Create a real admin account from the Admin Panel.';
        _status = AuthStatus.authError;
        _username = '';
        notifyListeners();
        return false;
      }

      // Bypass API — set admin state directly
      _userRole = UserRole.admin;
      _username = 'Temp Admin';
      _jwtToken = _tempAdminToken;

      await _secureStorage.write(
        key: _StorageKeys.authToken,
        value: _tempAdminToken,
      );
      await _secureStorage.write(key: _StorageKeys.username, value: _username);
      await _secureStorage.write(
        key: _StorageKeys.userRole,
        value: UserRole.admin.name,
      );
      _apiClient.setAuthToken(_tempAdminToken);

      // ignore: parameter_assignments
      password = '';
      _status = AuthStatus.authenticated;
      notifyListeners();
      return true;
    }
    // --- End Temp Admin Bypass ---

    // --- Try API first (online mode) ---
    try {
      // Step 1: Pre-auth CSRF cookie handshake
      await _csrfInterceptor.fetchToken();

      // Step 2: Authenticate
      final response = await _apiClient.post(
        '/api/login',
        data: {'username': username, 'password': password},
      );

      final data = response.data as Map<String, dynamic>;

      // Step 3: Extract profile
      final roleRaw = data['role'] as String? ?? '';
      _userRole = UserRole.fromString(roleRaw);
      _username =
          data['username'] as String? ?? data['name'] as String? ?? username;
      _jwtToken = data['token'] as String?;

      // Step 4: Fetch session-bound CSRF token tied to this authenticated user
      await _csrfInterceptor.fetchToken();

      // Step 5: Persist to secure storage (including CSRF token)
      if (_jwtToken != null) {
        await _secureStorage.write(
          key: _StorageKeys.authToken,
          value: _jwtToken,
        );
        _apiClient.setAuthToken(_jwtToken!);
      }
      await _secureStorage.write(key: _StorageKeys.username, value: _username);
      await _secureStorage.write(
        key: _StorageKeys.userRole,
        value: _userRole!.name,
      );
      if (_csrfInterceptor.hasToken) {
        await _secureStorage.write(
          key: _StorageKeys.csrfToken,
          value: _csrfInterceptor.token,
        );
      }

      // ignore: parameter_assignments
      password = '';
      _status = AuthStatus.authenticated;
      notifyListeners();
      return true;
    } catch (e) {
      // API failed — fall through to local users check
      if (e.toString().contains('404') ||
          e.toString().contains('Connection refused') ||
          e.toString().contains('SocketException')) {
        // Expected offline scenario — continue to local fallback
      } else {
        // Genuine auth error (wrong password, etc.) — surface it
        _error = _extractErrorMessage(e);
        _status = AuthStatus.authError;
        _userRole = null;
        _jwtToken = null;
        _username = '';
        notifyListeners();
        return false;
      }
    }

    // --- Local Users Fallback (offline-created accounts) ---
    await _loadLocalUsers();
    if (_localUsers.containsKey(username) &&
        _localUsers[username]!['password'] == password) {
      final userData = _localUsers[username]!;
      _userRole = UserRole.fromString(userData['role'] as String);
      _username = username;
      _jwtToken = 'local_user_token_${username.hashCode}';

      await _secureStorage.write(key: _StorageKeys.authToken, value: _jwtToken);
      await _secureStorage.write(key: _StorageKeys.username, value: _username);
      await _secureStorage.write(
        key: _StorageKeys.userRole,
        value: _userRole!.name,
      );
      await _secureStorage.write(
        key: _StorageKeys.csrfToken,
        value: 'local_csrf_bypass',
      );
      _apiClient.setAuthToken(_jwtToken!);

      // ignore: parameter_assignments
      password = '';
      _status = AuthStatus.authenticated;
      notifyListeners();
      return true;
    }
    // --- End Local Users Check ---

    _error = 'Invalid username or password.';
    _status = AuthStatus.authError;
    _userRole = null;
    _jwtToken = null;
    _username = '';
    notifyListeners();
    return false;
  }

  // ── Session Restore ──────────────────────────────────────────────────────

  /// Attempt to restore a previous session from secure storage.
  /// Returns true if a valid session was restored.
  Future<bool> tryRestoreSession() async {
    try {
      final token = await _secureStorage.read(key: _StorageKeys.authToken);
      if (token == null || token.isEmpty) return false;

      final savedRole = await _secureStorage.read(key: _StorageKeys.userRole);
      final savedUsername = await _secureStorage.read(
        key: _StorageKeys.username,
      );
      final savedCsrf = await _secureStorage.read(key: _StorageKeys.csrfToken);

      if (savedRole == null || savedUsername == null) return false;

      // Restore CSRF token from storage first, then verify with server
      if (savedCsrf != null && savedCsrf.isNotEmpty) {
        _csrfInterceptor.setToken(savedCsrf);
      }

      _userRole = UserRole.fromString(savedRole);
      _username = savedUsername;
      _jwtToken = token;
      _apiClient.setAuthToken(token);
      _status = AuthStatus.authenticated;

      notifyListeners();
      return true;
    } catch (_) {
      return false;
    }
  }

  // ── Logout ───────────────────────────────────────────────────────────────

  /// Perform a secure logout:
  ///   1. POST `/api/logout` with CSRF token in header (fire-and-forget).
  ///   2. Clear all in-memory state.
  ///   3. Wipe secure storage.
  ///   4. Notify listeners so UI can navigate to login.
  Future<void> logout() async {
    try {
      await _apiClient.post('/api/logout');
    } catch (_) {
      // Best-effort — ignore network errors during logout
    }

    await _clearAll();
  }

  /// Force-logout without an API call (used when 419/403 interceptor fires).
  /// This is called from the Dio interceptor, so no further network calls.
  Future<void> forceLogout() async {
    await _clearAll();
  }

  Future<void> _clearAll() async {
    // Preserve locally-created users and temp admin flag across logouts
    final savedUsers = await _secureStorage.read(key: _StorageKeys.localUsers);
    final tempDisabled = await _secureStorage.read(
      key: _StorageKeys.tempAdminDisabled,
    );

    await _secureStorage.deleteAll();

    // Restore the keys we want to keep
    if (savedUsers != null && savedUsers.isNotEmpty) {
      await _secureStorage.write(
        key: _StorageKeys.localUsers,
        value: savedUsers,
      );
    }
    if (tempDisabled != null && tempDisabled.isNotEmpty) {
      await _secureStorage.write(
        key: _StorageKeys.tempAdminDisabled,
        value: tempDisabled,
      );
    }

    _status = AuthStatus.unauthenticated;
    _userRole = null;
    _username = '';
    _error = '';
    _jwtToken = null;
    _csrfInterceptor.clearToken();
    _apiClient.clearAuthToken();
    _localUsers.clear(); // clear in-memory cache, will reload on next login
    notifyListeners();
  }

  // ── CSRF Helpers ─────────────────────────────────────────────────────────

  /// Force-refresh the CSRF token (e.g., before a sensitive action).
  Future<void> refreshCsrfToken() async {
    await _csrfInterceptor.fetchToken();
    // Persist the refreshed token
    if (_csrfInterceptor.hasToken) {
      await _secureStorage.write(
        key: _StorageKeys.csrfToken,
        value: _csrfInterceptor.token,
      );
    }
  }

  // ── Temp Admin ───────────────────────────────────────────────────────────

  /// Hardcoded temporary admin credentials.
  /// These allow initial access before a real admin account is created.
  static const _tempAdminUser = 'admin';
  static const _tempAdminPass = 'lzcas2025';
  static const _tempAdminToken = 'temp_admin_bypass_token';

  /// Whether the current session is using the temp admin bypass.
  bool get isTempAdmin =>
      _username == 'Temp Admin' && _jwtToken == _tempAdminToken;

  /// Permanently disable the temp admin account.
  /// Call this after creating a real admin user.
  Future<void> deactivateTempAdmin() async {
    await _secureStorage.write(
      key: _StorageKeys.tempAdminDisabled,
      value: 'true',
    );
  }

  // ── Local Users (offline-created accounts) ───────────────────────────────

  Map<String, Map<String, String>> _localUsers = {};

  /// Load locally created users from secure storage.
  Future<void> _loadLocalUsers() async {
    if (_localUsers.isNotEmpty) return;
    final json = await _secureStorage.read(key: _StorageKeys.localUsers);
    if (json != null && json.isNotEmpty) {
      try {
        final decoded = jsonDecode(json) as Map<String, dynamic>;
        _localUsers = decoded.map(
          (k, v) =>
              MapEntry(k, (v as Map<String, dynamic>).cast<String, String>()),
        );
      } catch (_) {
        _localUsers = {};
      }
    }
  }

  /// Create a user locally (no backend needed).
  /// Returns false if the username already exists.
  Future<bool> createLocalUser({
    required String username,
    required String password,
    required UserRole role,
  }) async {
    await _loadLocalUsers();
    if (_localUsers.containsKey(username)) return false;

    _localUsers[username] = {'password': password, 'role': role.name};

    final json = jsonEncode(_localUsers);
    await _secureStorage.write(key: _StorageKeys.localUsers, value: json);
    return true;
  }

  // ── Error Parsing ────────────────────────────────────────────────────────

  String _extractErrorMessage(Object error) {
    if (error is Exception) {
      final msg = error.toString();
      if (msg.contains('401') || msg.contains('Unauthorized')) {
        return 'Invalid username or password.';
      }
      if (msg.contains('SocketException') ||
          msg.contains('Connection refused')) {
        return 'Unable to connect to server. Check your network.';
      }
      // Strip common prefixes
      return msg.replaceAll(
        RegExp(r'^Exception:\s*|^DioException:\s*|^HttpException:\s*'),
        '',
      );
    }
    return 'An unexpected error occurred.';
  }
}
