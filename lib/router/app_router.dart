// lib/router/app_router.dart
// Centralized route configuration with role-based routing and guards.
// Every protected route is checked against [RouteGuard.checkAccess] before
// the page widget is built.

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:lzcas/pages/landing_page.dart';
import 'package:lzcas/pages/login_page.dart';
import 'package:lzcas/pages/admin/admin_dashboard.dart';
import 'package:lzcas/pages/inventory/inventory_dashboard.dart';
import 'package:lzcas/pages/cashier/cashier_dashboard.dart';
import 'package:lzcas/pages/branch/branch_cashier_dashboard.dart';
import 'package:lzcas/pages/member/member_dashboard.dart';
import 'package:lzcas/pages/member/nearest_cashiers_page.dart';
import 'package:lzcas/router/route_guard.dart';
import 'package:lzcas/auth/auth.dart';

/// Generate a [Route] for the given [RouteSettings], applying role-based
/// access control via [RouteGuard].
///
/// Usage: pass this function to [MaterialApp.onGenerateRoute].
Route<dynamic>? appRouter(RouteSettings settings) {
  // Public routes — no guard needed.
  switch (settings.name) {
    case AppRoutes.landing:
      return _fadeRoute(settings, (_) => const LandingPage());
    case AppRoutes.login:
      return _fadeRoute(settings, (_) => const LoginPage());
    case AppRoutes.forbidden:
      return _fadeRoute(settings, (_) => const ForbiddenPage());
  }

  // Protected routes — wrap with a guard-aware builder.
  // We use a builder that reads AuthState via Provider so the guard logic
  // has access to the current auth state.
  return _buildGuardedRoute(settings, () {
    switch (settings.name) {
      case AppRoutes.adminDashboard:
      case AppRoutes.adminUsers:
      case AppRoutes.adminConfig:
        return const AdminDashboard();

      case AppRoutes.inventoryDashboard:
      case AppRoutes.inventoryItems:
      case AppRoutes.inventoryReports:
        return const InventoryDashboard();

      case AppRoutes.cashierDashboard:
      case AppRoutes.cashierTransactions:
      case AppRoutes.cashierMembers:
      case AppRoutes.cashierDeleteRequest:
        return const CashierDashboard();

      case AppRoutes.branchDashboard:
        return const BranchCashierDashboard();

      case AppRoutes.memberDashboard:
        return const MemberDashboard();

      case AppRoutes.memberNearestCashiers:
        return const NearestCashiersPage();

      default:
        return null; // unknown route
    }
  });
}

PageRouteBuilder _fadeRoute(RouteSettings settings, WidgetBuilder builder) {
  return PageRouteBuilder(
    settings: settings,
    pageBuilder: (context, _, __) => builder(context),
    transitionsBuilder: (context, anim, _, child) => FadeTransition(
      opacity: CurvedAnimation(parent: anim, curve: Curves.easeInOut),
      child: child,
    ),
    transitionDuration: const Duration(milliseconds: 200),
  );
}

/// Build a route that checks [RouteGuard.checkAccess] before rendering.
/// If access is denied the user is redirected to login or forbidden page.
PageRouteBuilder _buildGuardedRoute(
  RouteSettings settings,
  Widget? Function() pageBuilder,
) {
  return _fadeRoute(settings, (context) {
    final auth = context.read<AuthState>();
    final redirect = RouteGuard.checkAccess(context, settings.name ?? '', auth);

    if (redirect != null) {
      // Defer the navigation to avoid building during build phase.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        Navigator.of(
          context,
        ).pushNamedAndRemoveUntil(redirect.destination, (_) => false);
      });
      // Show a loading indicator while the redirect happens.
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    final page = pageBuilder();
    if (page == null) {
      // Unknown route — redirect to login or dashboard.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        final dest = auth.isAuthenticated && auth.userRole != null
            ? AppRoutes.defaultForRole(auth.userRole!)
            : AppRoutes.login;
        Navigator.of(context).pushNamedAndRemoveUntil(dest, (_) => false);
      });
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    return page;
  });
}
