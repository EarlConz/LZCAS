// lib/router/route_guard.dart
// Route guard that checks authentication and role-based access before
// allowing navigation to any protected page.
// Unauthenticated users → login. Wrong-role deep links → 403 Forbidden page.
// Cashier and inventory users on mobile → redirected to login.

import 'dart:io' show Platform;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:lzcas/auth/auth.dart';

/// Set of all known route paths in the application.
///
/// Route paths follow the convention: /role/page
abstract class AppRoutes {
  AppRoutes._();

  // Auth
  static const String login = '/login';
  static const String forbidden = '/forbidden';

  // Admin
  static const String adminDashboard = '/admin/dashboard';
  static const String adminUsers = '/admin/users';
  static const String adminConfig = '/admin/config';

  // Inventory
  static const String inventoryDashboard = '/inventory/dashboard';
  static const String inventoryItems = '/inventory/items';
  static const String inventoryReports = '/inventory/reports';

  // Cashier
  static const String cashierDashboard = '/cashier/dashboard';
  static const String cashierTransactions = '/cashier/transactions';
  static const String cashierMembers = '/cashier/members';
  static const String cashierDeleteRequest = '/cashier/delete-request';

  // Member (reseller & basic members)
  static const String memberDashboard = '/member/dashboard';

  /// All role-based route prefixes for quick matching.
  static const _rolePrefixes = {
    UserRole.admin: '/admin',
    UserRole.inventory: '/inventory',
    UserRole.cashier: '/cashier',
    UserRole.member: '/member',
    UserRole.reseller: '/member',
  };

  /// Returns the default landing route for a given [role].
  static String defaultForRole(UserRole role) {
    switch (role) {
      case UserRole.admin:
        return adminDashboard;
      case UserRole.inventory:
        return inventoryDashboard;
      case UserRole.cashier:
        return cashierDashboard;
      case UserRole.member:
      case UserRole.reseller:
        return memberDashboard;
    }
  }

  /// Returns the path prefix for a given [role].
  static String prefixForRole(UserRole role) => _rolePrefixes[role]!;
}

/// Route guard — the single point where navigation access is enforced.
class RouteGuard {
  /// Check whether the current [AuthState] permits navigation to [route].
  ///
  /// Returns `null` if access is granted, or a [RouteRedirect] describing
  /// where to send the user instead.
  static RouteRedirect? checkAccess(
    BuildContext context,
    String route,
    AuthState auth,
  ) {
    // Public routes are always accessible.
    if (route == AppRoutes.login || route == AppRoutes.forbidden) {
      return null;
    }

    // Guard 1: Must be authenticated.
    if (auth.status != AuthStatus.authenticated) {
      return RouteRedirect(
        AppRoutes.login,
        reason: 'You must be logged in to access this page.',
      );
    }

    final role = auth.userRole;
    if (role == null) {
      return RouteRedirect(
        AppRoutes.login,
        reason: 'Session error. Please log in again.',
      );
    }

    // Guard 2: Mobile platform — cashier and inventory accounts are
    // desktop-only. Admin, member, and reseller may use phones/tablets.
    final isMobile = !kIsWeb && (Platform.isAndroid || Platform.isIOS);
    if (isMobile && (role == UserRole.cashier || role == UserRole.inventory)) {
      return RouteRedirect(
        AppRoutes.login,
        reason: 'Cashier and inventory accounts must use a desktop.',
      );
    }

    // Guard 3: Role-based route prefix matching.
    final allowedPrefix = AppRoutes.prefixForRole(role);

    // Allow if the route starts with the user's allowed prefix.
    if (route.startsWith(allowedPrefix)) {
      return null;
    }

    // Guard 4: Deep-link to a different role's path → 403 Forbidden page.
    // Check if the route belongs to any known role prefix.
    final isKnownProtectedRoute = AppRoutes._rolePrefixes.values.any(
      (prefix) => route.startsWith(prefix),
    );
    if (isKnownProtectedRoute) {
      return RouteRedirect(
        AppRoutes.forbidden,
        reason:
            'This page requires ${_roleForPrefix(route)?.displayName ?? "a different"} account.',
      );
    }

    // Fallback: redirect to the user's own dashboard.
    return RouteRedirect(
      AppRoutes.defaultForRole(role),
      reason: 'Page not found.',
    );
  }

  /// Infer which role a route belongs to (best-effort).
  static UserRole? _roleForPrefix(String route) {
    for (final entry in AppRoutes._rolePrefixes.entries) {
      if (route.startsWith(entry.value)) return entry.key;
    }
    return null;
  }
}

/// Describes a forced redirect from one route to another.
class RouteRedirect {
  final String destination;
  final String? reason;

  const RouteRedirect(this.destination, {this.reason});
}

// ─── 403 Forbidden Page ────────────────────────────────────────────────────

/// Standalone 403 Forbidden page shown when a user tries to deep-link into
/// a role-restricted area they don't have permission to access.
class ForbiddenPage extends StatelessWidget {
  final String? message;

  const ForbiddenPage({super.key, this.message});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final auth = context.watch<AuthState>();

    return Scaffold(
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.gpp_bad_rounded,
                size: 80,
                color: theme.colorScheme.error,
              ),
              const SizedBox(height: 16),
              Text(
                '403 — Access Denied',
                style: theme.textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                message ?? 'You do not have permission to access this page.',
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 24),
              FilledButton.icon(
                icon: const Icon(Icons.dashboard_rounded),
                label: const Text('Go to My Dashboard'),
                onPressed: () {
                  if (auth.isAuthenticated && auth.userRole != null) {
                    Navigator.of(context).pushNamedAndRemoveUntil(
                      AppRoutes.defaultForRole(auth.userRole!),
                      (_) => false,
                    );
                  } else {
                    Navigator.of(
                      context,
                    ).pushNamedAndRemoveUntil(AppRoutes.login, (_) => false);
                  }
                },
              ),
              if (auth.isAuthenticated) ...[
                const SizedBox(height: 8),
                TextButton(
                  onPressed: () async {
                    await auth.logout();
                    if (!context.mounted) return;
                    Navigator.of(
                      context,
                    ).pushNamedAndRemoveUntil(AppRoutes.login, (_) => false);
                  },
                  child: const Text('Sign in with a different account'),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
