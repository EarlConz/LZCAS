// lib/auth/csrf_interceptor.dart
// Dio interceptor that:
//   - Attaches X-CSRF-Token header to all non-idempotent requests.
//   - Catches 419 (Token Mismatch) / 403 (Forbidden) responses and triggers
//     a session-expiry callback to force-logout.

import 'package:dio/dio.dart';

/// Signature for a callback invoked when the CSRF/session is no longer valid.
typedef OnSessionExpired = Future<void> Function();

/// Interceptor that manages and injects CSRF tokens into outgoing requests
/// and monitors for session-expiry errors on incoming responses.
///
/// On construction or after [fetchToken] is called, the interceptor stores a
/// CSRF token. Every subsequent state-changing (non-idempotent) request will
/// include the `X-CSRF-Token` header.
///
/// If the server responds with 419 (Token Mismatch) or 403 (Forbidden /
/// CSRF validation failed), [onSessionExpired] is called so the app can
/// force-logout and redirect to the login screen.
class CsrfInterceptor extends Interceptor {
  final Dio _dio;
  OnSessionExpired? _onSessionExpired;

  String? _csrfToken;

  /// The endpoint used to fetch the CSRF cookie/token.
  final String csrfUrl;

  CsrfInterceptor({
    required Dio dio,
    this.csrfUrl = '/api/csrf-cookie',
    OnSessionExpired? onSessionExpired,
  }) : _dio = dio,
       _onSessionExpired = onSessionExpired;

  /// Set or update the session-expiry callback after construction.
  /// This allows the callback to capture state that doesn't exist yet
  /// at construction time (e.g. AuthState).
  void setOnSessionExpired(OnSessionExpired callback) {
    _onSessionExpired = callback;
  }

  /// Whether a token is currently held.
  bool get hasToken => _csrfToken != null && _csrfToken!.isNotEmpty;

  /// The current CSRF token value (null if not fetched).
  String? get token => _csrfToken;

  // ── Token Lifecycle ──────────────────────────────────────────────────────

  /// Explicitly set a token (e.g., restored from secure storage).
  void setToken(String value) {
    _csrfToken = value;
  }

  /// Fetch a fresh CSRF token from the server.
  ///
  /// Called during login (both pre-auth and post-auth) and before any
  /// state-changing operation if the token may have expired.
  Future<void> fetchToken() async {
    try {
      final response = await _dio.get(csrfUrl);

      // Option A: Token returned in JSON body under 'csrfToken' or 'token'.
      if (response.data is Map<String, dynamic>) {
        final body = response.data as Map<String, dynamic>;
        _csrfToken = (body['csrfToken'] ?? body['token'] ?? '').toString();
      }

      // Option B: Token returned in a response header.
      if ((_csrfToken == null || _csrfToken!.isEmpty) &&
          response.headers.map.containsKey('X-CSRF-Token')) {
        _csrfToken = response.headers.value('X-CSRF-Token');
      }

      // Option C: Extract from set-cookie header.
      if (_csrfToken == null || _csrfToken!.isEmpty) {
        final setCookie = response.headers.value('set-cookie');
        if (setCookie != null) {
          final match = RegExp(r'XSRF-TOKEN=([^;]+)').firstMatch(setCookie);
          if (match != null) {
            _csrfToken = Uri.decodeComponent(match.group(1)!);
          }
        }
      }
    } catch (_) {
      // If the CSRF endpoint is unavailable, continue without a token.
      // The backend will reject subsequent requests with 419/403, which
      // the onError handler below will catch.
      _csrfToken = null;
    }
  }

  /// Clear the stored token (e.g., on logout).
  void clearToken() {
    _csrfToken = null;
  }

  // ── Request Interceptor ──────────────────────────────────────────────────

  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    // Only attach CSRF header to state-changing methods (POST, PUT, etc.).
    final method = options.method.toUpperCase();
    if (_csrfToken != null &&
        _csrfToken!.isNotEmpty &&
        _isStateChanging(method)) {
      options.headers['X-CSRF-Token'] = _csrfToken;
    }

    handler.next(options);
  }

  // ── Response / Error Interceptor ─────────────────────────────────────────

  @override
  void onError(DioException err, ErrorInterceptorHandler handler) {
    final statusCode = err.response?.statusCode;

    // 419 Token Mismatch (Laravel-style) or 403 Forbidden (CSRF failure)
    // are signals that the session has been invalidated server-side.
    if (statusCode == 419 ||
        (statusCode == 403 && _isLikelyCsrfError(err.response?.headers))) {
      _onSessionExpired?.call();
      // Do NOT retry — the session is gone. Propagate the error so the
      // caller still knows the request failed.
    }

    handler.next(err);
  }

  /// Heuristic: if a 403 includes a CSRF-related header or body hint, treat
  /// it as a session expiry rather than a simple permission denial.
  bool _isLikelyCsrfError(Headers? headers) {
    if (headers == null) return false;
    // Some backends signal CSRF failure via a specific header or cookie reset.
    final setCookie = headers.value('set-cookie') ?? '';
    return setCookie.contains('XSRF-TOKEN=deleted') ||
        setCookie.contains('XSRF-TOKEN=;');
  }

  // ── Helpers ──────────────────────────────────────────────────────────────

  /// Returns true for non-idempotent HTTP methods.
  bool _isStateChanging(String method) {
    return method == 'POST' ||
        method == 'PUT' ||
        method == 'DELETE' ||
        method == 'PATCH';
  }
}
