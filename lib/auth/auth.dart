// lib/auth/auth.dart
// Barrel export for the auth module.

export 'auth_state.dart' show AuthState, AuthStatus, UserRole;
export 'api_client.dart' show ApiClient;
export 'csrf_interceptor.dart' show CsrfInterceptor, OnSessionExpired;
export 'role_visibility.dart'
    show
        RoleVisibility,
        RoleAccessException,
        UserRolePermissions,
        assertRoleOrThrow;
export 'csrf_interceptor.dart' show CsrfInterceptor;
