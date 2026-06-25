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

class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final _formKey = GlobalKey<FormState>();
  final _usernameCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();
  bool _obscurePassword = true;

  @override
  void dispose() {
    _usernameCtrl.dispose();
    _passwordCtrl.dispose();
    super.dispose();
  }

  Future<void> _handleLogin() async {
    if (!_formKey.currentState!.validate()) return;

    final auth = context.read<AuthState>();

    // Capture credentials before clearing controllers
    final username = _usernameCtrl.text.trim();
    final password = _passwordCtrl.text;

    // Clear password from UI immediately for security
    _passwordCtrl.clear();
    _obscurePassword = true;

    final success = await auth.login(username, password);

    // The password String is now eligible for GC — no further references exist.

    if (!mounted) return;

    if (success && auth.userRole != null) {
      // Clear username from UI as well
      _usernameCtrl.clear();

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
                    Container(
                      width: 72,
                      height: 72,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: StockpileColors.primary900,
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(
                        'L',
                        style: StockpileFonts.satoshi(
                          fontSize: 36,
                          fontWeight: FontWeight.w900,
                          color: Colors.white,
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'LZCAS',
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
                            Icon(Icons.error_outline,
                                size: 20, color: StockpileColors.danger),
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

                    // ── Username ──────────────────────────────────────────
                    TextFormField(
                      controller: _usernameCtrl,
                      enabled: !isAuthenticating,
                      decoration: InputDecoration(
                        labelText: 'Username',
                        prefixIcon: const Icon(Icons.person_outline_rounded),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      textInputAction: TextInputAction.next,
                      validator: (v) =>
                          (v == null || v.trim().isEmpty) ? 'Required' : null,
                    ),
                    const SizedBox(height: 16),

                    // ── Password ──────────────────────────────────────────
                    TextFormField(
                      controller: _passwordCtrl,
                      enabled: !isAuthenticating,
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
                              () => _obscurePassword = !_obscurePassword),
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
                      'Accounts are provisioned by your administrator.',
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
