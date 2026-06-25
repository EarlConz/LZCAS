// lib/auth/auth.dart
// Barrel export for the auth module (Supabase Auth).

export 'auth_state.dart' show AuthState, AuthStatus, UserRole;
export 'role_visibility.dart'
    show
        RoleVisibility,
        RoleAccessException,
        UserRolePermissions,
        assertRoleOrThrow;
