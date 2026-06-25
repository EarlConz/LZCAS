// lib/auth/api_client.dart
// Centralized Dio-based HTTP client with CSRF protection, auth token injection,
// session-expiry auto-logout, and consistent error handling.

import 'package:dio/dio.dart';
import 'csrf_interceptor.dart';

/// Singleton-style API client that wraps Dio.
///
/// Provides:
/// - Base URL configuration
/// - Auth token header injection (Bearer)
/// - CSRF token injection + 419/403 error interception via [CsrfInterceptor]
/// - Unified error handling
class ApiClient {
  late final Dio _dio;
  late final CsrfInterceptor _csrfInterceptor;

  /// The base URL for all API requests.
  final String baseUrl;

  /// Callback invoked when the CSRF interceptor detects a 419/403 session
  /// expiry. Pass [AuthState.forceLogout] from [main.dart].
  final OnSessionExpired? onSessionExpired;

  ApiClient({
    this.baseUrl = '',
    this.onSessionExpired,
    List<Interceptor> extraInterceptors = const [],
  }) {
    _dio = Dio(
      BaseOptions(
        baseUrl: baseUrl,
        connectTimeout: const Duration(seconds: 10),
        receiveTimeout: const Duration(seconds: 10),
        headers: {
          'Content-Type': 'application/json',
          'Accept': 'application/json',
        },
      ),
    );

    // Create CSRF interceptor with the session-expiry callback.
    _csrfInterceptor = CsrfInterceptor(
      dio: _dio,
      onSessionExpired: onSessionExpired,
    );

    // Interceptor order: CSRF (request + error) → logging → extras.
    _dio.interceptors.addAll([
      _csrfInterceptor,
      LogInterceptor(
        requestBody: true,
        responseBody: true,
        error: true,
        logPrint: (o) => print('[API] $o'),
      ),
      ...extraInterceptors,
    ]);
  }

  /// The underlying Dio instance (for advanced usage).
  Dio get dio => _dio;

  /// The CSRF interceptor instance.
  CsrfInterceptor get csrfInterceptor => _csrfInterceptor;

  // ── Auth Token Management ────────────────────────────────────────────────

  /// Set the Bearer auth token for subsequent requests.
  void setAuthToken(String token) {
    _dio.options.headers['Authorization'] = 'Bearer $token';
  }

  /// Clear the auth token (e.g., on logout).
  void clearAuthToken() {
    _dio.options.headers.remove('Authorization');
  }

  // ── HTTP Methods ─────────────────────────────────────────────────────────

  Future<Response<T>> get<T>(
    String path, {
    Map<String, dynamic>? queryParameters,
    Options? options,
    CancelToken? cancelToken,
  }) {
    return _dio.get<T>(
      path,
      queryParameters: queryParameters,
      options: options,
      cancelToken: cancelToken,
    );
  }

  Future<Response<T>> post<T>(
    String path, {
    dynamic data,
    Map<String, dynamic>? queryParameters,
    Options? options,
    CancelToken? cancelToken,
  }) {
    return _dio.post<T>(
      path,
      data: data,
      queryParameters: queryParameters,
      options: options,
      cancelToken: cancelToken,
    );
  }

  Future<Response<T>> put<T>(
    String path, {
    dynamic data,
    Map<String, dynamic>? queryParameters,
    Options? options,
    CancelToken? cancelToken,
  }) {
    return _dio.put<T>(
      path,
      data: data,
      queryParameters: queryParameters,
      options: options,
      cancelToken: cancelToken,
    );
  }

  Future<Response<T>> patch<T>(
    String path, {
    dynamic data,
    Map<String, dynamic>? queryParameters,
    Options? options,
    CancelToken? cancelToken,
  }) {
    return _dio.patch<T>(
      path,
      data: data,
      queryParameters: queryParameters,
      options: options,
      cancelToken: cancelToken,
    );
  }

  Future<Response<T>> delete<T>(
    String path, {
    dynamic data,
    Map<String, dynamic>? queryParameters,
    Options? options,
    CancelToken? cancelToken,
  }) {
    return _dio.delete<T>(
      path,
      data: data,
      queryParameters: queryParameters,
      options: options,
      cancelToken: cancelToken,
    );
  }
}
