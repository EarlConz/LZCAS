// lib/pages/landing_page.dart
// Public brand landing page shown to unauthenticated visitors before login.
//
// Layout: the FULL banner is shown centered (nothing cropped, bottom info
// always visible). Any space around it — which appears on screens wider or
// taller than the banner — is filled with a blurred, zoomed copy of the same
// image, so there are never white bars on the sides. Two clickable targets
// route to login: the banner's drawn "Shop Now" button (aligned hotspot) and a
// top-right Login button. A gentle fade-in plays on load.

import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../router/route_guard.dart';
import '../utils/fonts.dart';
import 'login_page.dart';

class LandingPage extends StatefulWidget {
  const LandingPage({super.key});

  @override
  State<LandingPage> createState() => _LandingPageState();
}

class _LandingPageState extends State<LandingPage>
    with SingleTickerProviderStateMixin {
  // ── Banner artwork per platform (wide desktop vs portrait mobile) ──
  static const String _wideAsset = 'assets/images/landing_pc.jpg';
  static const String _mobileAsset = 'assets/images/landing_mobile.jpeg';

  // Intrinsic pixel size of each banner (to preserve aspect ratio).
  static const double _pcW = 2049, _pcH = 1152;
  static const double _mobW = 1620, _mobH = 2880;

  // ── Vertical framing knob ──────────────────────────────────────────────
  // Where the crop falls when the banner overflows the screen vertically:
  //   -1.0 = pin TOP (show logo, crop bottom) · 0.0 = centered ·
  //    1.0 = pin BOTTOM (show info, crop top logo).
  static const double _pcVerticalAlign = 0.55;
  static const double _mobVerticalAlign = -0.70;

  // Fractional rectangle of each banner's drawn "Shop Now" button
  // (left, top, width, height as fractions 0..1). To align: flip _debugHotspot
  // to true, hot-reload, and nudge until the red box sits on the button.
  //   left → move right (bigger) · top → move down (bigger) · width/height → size
  static const Rect _pcHotspot = Rect.fromLTWH(0.120, 0.620, 0.180, 0.060);
  static const Rect _mobHotspot = Rect.fromLTWH(0.130, 0.465, 0.280, 0.042);

  // Set to true to see the active hotspot as a red box while aligning it.
  static const bool _debugHotspot = false;

  late final AnimationController _intro;
  late final Animation<double> _bannerFade;
  late final Animation<double> _ctaFade;
  late final Animation<Offset> _ctaSlide;

  @override
  void initState() {
    super.initState();
    _intro = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..forward();

    _bannerFade = CurvedAnimation(
      parent: _intro,
      curve: const Interval(0.0, 0.65, curve: Curves.easeOut),
    );
    _ctaFade = CurvedAnimation(
      parent: _intro,
      curve: const Interval(0.4, 1.0, curve: Curves.easeOut),
    );
    _ctaSlide = Tween<Offset>(begin: const Offset(0, 0.5), end: Offset.zero)
        .animate(
          CurvedAnimation(
            parent: _intro,
            curve: const Interval(0.4, 1.0, curve: Curves.easeOutCubic),
          ),
        );
  }

  @override
  void dispose() {
    _intro.dispose();
    super.dispose();
  }

  /// Navigate to login with a circular-reveal transition centered on [from]
  /// (the button the user pressed), so the login page blooms out of it.
  void _goToLogin({Alignment from = Alignment.center}) {
    Navigator.of(context).push(_circularRevealRoute(from));
  }

  @override
  Widget build(BuildContext context) {
    final isWide = MediaQuery.sizeOf(context).width >= 700;
    final asset = isWide ? _wideAsset : _mobileAsset;
    final imgW = isWide ? _pcW : _mobW;
    final imgH = isWide ? _pcH : _mobH;
    final vAlign = isWide ? _pcVerticalAlign : _mobVerticalAlign;
    final hotspot = isWide ? _pcHotspot : _mobHotspot;
    // The circular reveal blooms from the Shop Now button's center.
    final revealFrom = Alignment(
      (hotspot.left + hotspot.width / 2) * 2 - 1,
      (hotspot.top + hotspot.height / 2) * 2 - 1,
    );

    return Scaffold(
      backgroundColor: const Color(0xFFEFF4E6),
      body: Stack(
        fit: StackFit.expand,
        children: [
          // ── Full-bleed banner (cover): fills the screen edge-to-edge with
          // no gaps. Any vertical overflow is cropped from the TOP so the
          // bottom info stays visible (bottomCenter alignment). ──
          LayoutBuilder(
            builder: (context, constraints) {
              final sw = constraints.maxWidth;
              final sh = constraints.maxHeight;
              // Replicate BoxFit.cover's geometry so the "Shop Now" hotspot can
              // be mapped onto the cropped, screen-filling image.
              final scale = math.max(sw / imgW, sh / imgH);
              final dw = imgW * scale; // displayed image width
              final dh = imgH * scale; // displayed image height
              final offsetX = (sw - dw) / 2; // horizontally centered
              // Distribute the vertical crop per vAlign (-1 top .. 1 bottom),
              // matching the Image's alignment below.
              final offsetY = (sh - dh) * (vAlign + 1) / 2;
              // Corner rounding for the Shop Now hover highlight, scaled to the
              // drawn button so it matches at any size.
              final hotspotRadius = hotspot.height * dh * 0.45;
              return Stack(
                fit: StackFit.expand,
                children: [
                  Positioned.fill(
                    child: FadeTransition(
                      opacity: _bannerFade,
                      child: Image.asset(
                        asset,
                        fit: BoxFit.cover,
                        alignment: Alignment(0, vAlign),
                        filterQuality: FilterQuality.high,
                        errorBuilder: (_, _, _) => const ColoredBox(
                          color: Color(0xFFEFF4E6),
                          child: Center(child: Text('LZCAS Trading · GUTVita')),
                        ),
                      ),
                    ),
                  ),
                  // Clickable hotspot over the drawn "Shop Now" button.
                  Positioned(
                    left: offsetX + hotspot.left * dw,
                    top: offsetY + hotspot.top * dh,
                    width: hotspot.width * dw,
                    height: hotspot.height * dh,
                    child: Semantics(
                      button: true,
                      label: 'Shop Now — sign in',
                      // Transparent Material hosts the InkWell so its hover
                      // highlight and ripple paint on top of the banner image.
                      child: Material(
                        type: MaterialType.transparency,
                        child: InkWell(
                          onTap: () => _goToLogin(from: revealFrom),
                          borderRadius: BorderRadius.circular(hotspotRadius),
                          hoverColor: Colors.white.withValues(alpha: 0.18),
                          highlightColor: Colors.white.withValues(alpha: 0.10),
                          splashColor: Colors.white.withValues(alpha: 0.22),
                          child: _debugHotspot
                              ? DecoratedBox(
                                  decoration: BoxDecoration(
                                    color: Colors.red.withValues(alpha: 0.35),
                                    border: Border.all(
                                      color: Colors.red,
                                      width: 2,
                                    ),
                                    borderRadius: BorderRadius.circular(
                                      hotspotRadius,
                                    ),
                                  ),
                                  child: const SizedBox.expand(),
                                )
                              : const SizedBox.expand(),
                        ),
                      ),
                    ),
                  ),
                ],
              );
            },
          ),

          // ── Explicit Login button (top-right), animated in ──
          SafeArea(
            child: Align(
              alignment: Alignment.topRight,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: FadeTransition(
                  opacity: _ctaFade,
                  child: SlideTransition(
                    position: _ctaSlide,
                    child: _LoginButton(
                      // Reveal from the top-right, where this button sits.
                      onPressed: () => _goToLogin(from: Alignment.topRight),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// A circular "reveal" transition — the login page grows out of a circle
/// centered on [from] (the button the user pressed) while scaling in slightly
/// for depth. Distinct from the app's default fade so entering the app feels
/// deliberate and on-brand (like a droplet blooming open).
Route<dynamic> _circularRevealRoute(Alignment from) {
  return PageRouteBuilder(
    settings: const RouteSettings(name: AppRoutes.login),
    transitionDuration: const Duration(milliseconds: 650),
    reverseTransitionDuration: const Duration(milliseconds: 420),
    pageBuilder: (_, _, _) => const LoginPage(),
    transitionsBuilder: (context, animation, secondary, child) {
      final curved = CurvedAnimation(
        parent: animation,
        curve: Curves.easeInOutCubic,
      );
      return AnimatedBuilder(
        animation: curved,
        builder: (context, _) => ClipPath(
          clipper: _CircleRevealClipper(fraction: curved.value, center: from),
          child: Transform.scale(
            scale: 1.06 - 0.06 * curved.value,
            child: child,
          ),
        ),
      );
    },
  );
}

class _CircleRevealClipper extends CustomClipper<Path> {
  final double fraction;
  final Alignment center;
  const _CircleRevealClipper({required this.fraction, required this.center});

  @override
  Path getClip(Size size) {
    final c = center.alongSize(size);
    // Radius needed to reach the farthest corner, so the reveal fully covers
    // the screen at fraction 1.0.
    final maxRadius = <Offset>[
      Offset.zero,
      Offset(size.width, 0),
      Offset(0, size.height),
      Offset(size.width, size.height),
    ].map((corner) => (corner - c).distance).reduce(math.max);
    return Path()
      ..addOval(Rect.fromCircle(center: c, radius: maxRadius * fraction));
  }

  @override
  bool shouldReclip(covariant _CircleRevealClipper old) =>
      old.fraction != fraction || old.center != center;
}

class _LoginButton extends StatelessWidget {
  final VoidCallback onPressed;
  const _LoginButton({required this.onPressed});

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.25),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: FilledButton.icon(
        onPressed: onPressed,
        icon: const Icon(Icons.login_rounded, size: 18),
        label: Text(
          'Login',
          style: StockpileFonts.satoshi(fontWeight: FontWeight.w700),
        ),
        style: FilledButton.styleFrom(
          backgroundColor: const Color(0xFF1B5E20), // brand green
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 14),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      ),
    );
  }
}
