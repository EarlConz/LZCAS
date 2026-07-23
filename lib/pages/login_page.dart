// lib/pages/login_page.dart
// Production login screen using explicit AuthStatus states.
// Credentials are cleared from memory immediately after authentication.
// Users cannot self-register — accounts are pre-created by an Admin.

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:lzcas/auth/auth.dart';
import 'package:lzcas/router/route_guard.dart';
import 'package:lzcas/theme.dart';
import 'package:lzcas/utils/fonts.dart';
import 'package:lzcas/widgets/app_logo.dart';

class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final _formKey = GlobalKey<FormState>();
  final _emailCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();
  bool _obscurePassword = true;

  @override
  void dispose() {
    _emailCtrl.dispose();
    _passwordCtrl.dispose();
    super.dispose();
  }

  Future<void> _handleLogin() async {
    if (!_formKey.currentState!.validate()) return;

    final auth = context.read<AuthState>();

    // Capture credentials before clearing controllers
    final username = _emailCtrl.text.trim();
    final password = _passwordCtrl.text;

    // Clear password from UI immediately for security
    _passwordCtrl.clear();
    _obscurePassword = true;

    final success = await auth.login(username, password);

    // The password String is now eligible for GC — no further references exist.

    if (!mounted) return;

    if (success && auth.userRole != null) {
      // Clear username from UI as well
      _emailCtrl.clear();

      // Navigate to the user's role-specific dashboard, clearing the stack.
      Navigator.of(context).pushNamedAndRemoveUntil(
        AppRoutes.defaultForRole(auth.userRole!),
        (_) => false,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthState>();
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final isAuthenticating = auth.status == AuthStatus.authenticating;

    return Scaffold(
      // Float a Back-to-landing control over the content. Always shown:
      // if there's a page to pop (arrived from landing) we pop — keeping the
      // reverse reveal animation — otherwise (arrived via logout, which clears
      // the stack) we navigate to the landing page directly.
      // extendBodyBehindAppBar keeps the form centered with no layout shift.
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        leadingWidth: 120,
        leading: _AnimatedBackButton(
          isDark: isDark,
          onPressed: () {
            final nav = Navigator.of(context);
            if (nav.canPop()) {
              nav.maybePop();
            } else {
              nav.pushReplacementNamed(AppRoutes.landing);
            }
          },
        ),
      ),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Form(
                key: _formKey,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // ── Logo / Brand ─────────────────────────────────────
                    const AppLogo(size: 72, radius: 20),
                    const SizedBox(height: 16),
                    Text(
                      'GUTVita',
                      style: StockpileFonts.satoshi(
                        fontSize: 28,
                        fontWeight: FontWeight.w800,
                        color: isDark
                            ? StockpileColors.darkTextPrimary
                            : StockpileColors.darkText,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Sign in to your account',
                      style: StockpileFonts.satoshi(
                        fontSize: 15,
                        color: isDark
                            ? StockpileColors.darkTextMuted
                            : StockpileColors.mutedText,
                      ),
                    ),
                    const SizedBox(height: 40),

                    // ── Error Banner (only shown in authError state) ─────
                    if (auth.status == AuthStatus.authError &&
                        auth.error.isNotEmpty)
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(12),
                        margin: const EdgeInsets.only(bottom: 16),
                        decoration: BoxDecoration(
                          color: StockpileColors.dangerBg,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: StockpileColors.danger.withAlpha(80),
                          ),
                        ),
                        child: Row(
                          children: [
                            Icon(
                              Icons.error_outline,
                              size: 20,
                              color: StockpileColors.danger,
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                auth.error,
                                style: const TextStyle(
                                  color: StockpileColors.danger,
                                  fontWeight: FontWeight.w500,
                                  fontSize: 13,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),

                    // ── Username or Email ───────────────────────────────
                    TextFormField(
                      controller: _emailCtrl,
                      enabled: !isAuthenticating,
                      autovalidateMode: AutovalidateMode.onUserInteraction,
                      decoration: InputDecoration(
                        labelText: 'Username or Email',
                        prefixIcon: const Icon(Icons.person_outline_rounded),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      textInputAction: TextInputAction.next,
                      validator: (v) {
                        if (v == null || v.trim().isEmpty) return 'Required';
                        return null;
                      },
                    ),
                    const SizedBox(height: 16),

                    // ── Password ──────────────────────────────────────────
                    TextFormField(
                      controller: _passwordCtrl,
                      enabled: !isAuthenticating,
                      autovalidateMode: AutovalidateMode.onUserInteraction,
                      obscureText: _obscurePassword,
                      decoration: InputDecoration(
                        labelText: 'Password',
                        prefixIcon: const Icon(Icons.lock_outline_rounded),
                        suffixIcon: IconButton(
                          icon: Icon(
                            _obscurePassword
                                ? Icons.visibility_off_rounded
                                : Icons.visibility_rounded,
                          ),
                          onPressed: () => setState(
                            () => _obscurePassword = !_obscurePassword,
                          ),
                        ),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      textInputAction: TextInputAction.done,
                      onFieldSubmitted: (_) => _handleLogin(),
                      validator: (v) =>
                          (v == null || v.isEmpty) ? 'Required' : null,
                    ),
                    const SizedBox(height: 24),

                    // ── Login Button ──────────────────────────────────────
                    SizedBox(
                      width: double.infinity,
                      height: 50,
                      child: FilledButton(
                        onPressed: auth.isLoading ? null : _handleLogin,
                        style: FilledButton.styleFrom(
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        child: auth.isLoading
                            ? const SizedBox(
                                width: 22,
                                height: 22,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2.5,
                                  color: Colors.white,
                                ),
                              )
                            : Text(
                                'Sign In',
                                style: StockpileFonts.satoshi(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                      ),
                    ),

                    const SizedBox(height: 24),
                    Text(
                      'Accounts are provisioned by your administrator.\nSign in with your username or email and password.',
                      textAlign: TextAlign.center,
                      style: StockpileFonts.satoshi(
                        fontSize: 12,
                        color: isDark
                            ? StockpileColors.darkTextMuted
                            : StockpileColors.mutedText,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Back-to-landing control that fades and slides in from the left on build,
/// giving the appearance a small entrance to match the page's reveal.
class _AnimatedBackButton extends StatelessWidget {
  final bool isDark;
  final VoidCallback onPressed;
  const _AnimatedBackButton({required this.isDark, required this.onPressed});

  @override
  Widget build(BuildContext context) {
    final color = isDark
        ? StockpileColors.darkTextPrimary
        : StockpileColors.darkText;
    return TweenAnimationBuilder<double>(
      tween: Tween<double>(begin: 0, end: 1),
      duration: const Duration(milliseconds: 500),
      curve: Curves.easeOutCubic,
      builder: (context, t, child) => Opacity(
        opacity: t,
        child: Transform.translate(
          offset: Offset(-14 * (1 - t), 0),
          child: child,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.only(left: 4),
        child: TextButton.icon(
          onPressed: onPressed,
          icon: const Icon(Icons.arrow_back_rounded, size: 20),
          label: Text(
            'Back',
            style: StockpileFonts.satoshi(fontWeight: FontWeight.w600),
          ),
          style: TextButton.styleFrom(foregroundColor: color),
        ),
      ),
    );
  }
}
