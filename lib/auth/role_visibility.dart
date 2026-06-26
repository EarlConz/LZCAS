// lib/auth/role_visibility.dart
// Widget-level role-based visibility helpers.
// Provides:
//   - [RoleVisibility]: conditionally shows children based on user role.
//   - [assertRoleOrThrow]: runtime role assertion for defense-in-depth.

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'auth_state.dart';

/// Set of roles required to view the wrapped content.
typedef RolePredicate = bool Function(UserRole role);

/// Wraps children and only renders them if the current user's role satisfies
/// the [allowed] predicate (or [allowedRoles] set).
///
/// If the user does not have access, an optional [fallback] can be shown
/// (defaults to SizedBox.shrink).
class RoleVisibility extends StatelessWidget {
  final Set<UserRole>? allowedRoles;
  final RolePredicate? allowed;
  final Widget child;
  final Widget? fallback;

  const RoleVisibility({
    super.key,
    this.allowedRoles,
    this.allowed,
    required this.child,
    this.fallback,
  });

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthState>();
    final role = auth.userRole;

    if (role == null) return fallback ?? const SizedBox.shrink();

    bool visible = false;

    if (allowedRoles != null) {
      visible = allowedRoles!.contains(role);
    } else if (allowed != null) {
      visible = allowed!(role);
    }

    return visible ? child : (fallback ?? const SizedBox.shrink());
  }
}

/// Assert that the current user has one of [allowedRoles], or one of the
/// admin roles (admins always pass). Throws a [RoleAccessException] if the
/// assertion fails — call this in build methods for defense-in-depth.
void assertRoleOrThrow(BuildContext context, Set<UserRole> allowedRoles) {
  final auth = context.read<AuthState>();
  final role = auth.userRole;
  if (role == null) return; // Still logging out — RouteGuard handles redirect
  // Admin always passes all role assertions.
  if (role == UserRole.admin) return;
  if (!allowedRoles.contains(role)) {
    throw RoleAccessException(
      'Role "${role.displayName}" does not have permission. '
      'Required: ${allowedRoles.map((r) => r.displayName).join(", ")}.',
    );
  }
}

/// Runtime exception thrown when a role assertion fails.
class RoleAccessException implements Exception {
  final String message;
  const RoleAccessException(this.message);

  @override
  String toString() => 'RoleAccessException: $message';
}

/// Utility extensions on [UserRole] for cleaner permission checks.
extension UserRolePermissions on UserRole {
  /// Returns true if this role can manage inventory (add/edit/delete items).
  bool get canManageInventory =>
      this == UserRole.admin || this == UserRole.inventory;

  /// Returns true if this role can process sales (POS terminal).
  bool get canProcessSales =>
      this == UserRole.admin || this == UserRole.cashier;

  /// Returns true if this role can manage users (admin only).
  bool get canManageUsers => this == UserRole.admin;

  /// Returns true if this role can view reports.
  bool get canViewReports =>
      this == UserRole.admin || this == UserRole.inventory;

  /// Returns true if this role can view member details (read-only or full).
  bool get canViewMembers => true; // All roles can view members.

  /// Returns true if this role can request member deletion.
  bool get canRequestMemberDeletion =>
      this == UserRole.admin || this == UserRole.cashier;

  /// Returns true if this role can request stock borrowing.
  bool get canRequestBorrowStock =>
      this == UserRole.admin || this == UserRole.cashier;
}
