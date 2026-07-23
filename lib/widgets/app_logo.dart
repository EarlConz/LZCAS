// lib/widgets/app_logo.dart
// The GUTVita brand mark, shown wherever the app needs its logo (login screen,
// sidebars, etc.). Renders assets/images/logo.jpg rounded, with a graceful
// fallback if the asset is ever missing.

import 'package:flutter/material.dart';

class AppLogo extends StatelessWidget {
  final double size;
  final double radius;

  const AppLogo({super.key, this.size = 40, this.radius = 10});

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: Image.asset(
        'assets/images/logo.jpg',
        width: size,
        height: size,
        fit: BoxFit.cover,
        filterQuality: FilterQuality.high,
        errorBuilder: (_, _, _) => Container(
          width: size,
          height: size,
          color: const Color(0xFF1B5E20),
          alignment: Alignment.center,
          child: Text(
            'G',
            style: TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w900,
              fontSize: size * 0.5,
            ),
          ),
        ),
      ),
    );
  }
}
