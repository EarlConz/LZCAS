import 'package:flutter/material.dart';

import '../config/build_flavor.dart';

/// Marks non-production builds with a corner ribbon so a staging install is
/// never mistaken for the real thing during a client demo.
///
/// On a production build this is a pure pass-through — it adds no widget to
/// the tree and costs nothing.
class StagingBadge extends StatelessWidget {
  const StagingBadge({super.key, required this.child});

  final Widget? child;

  @override
  Widget build(BuildContext context) {
    final content = child ?? const SizedBox.shrink();
    final label = BuildConfig.badgeLabel;
    if (label == null) return content;

    return Directionality(
      textDirection: Directionality.maybeOf(context) ?? TextDirection.ltr,
      child: Stack(
        children: [
          content,
          // Top-right, ignores pointers so it never blocks the UI beneath.
          Positioned(
            top: 0,
            right: 0,
            child: IgnorePointer(
              child: SafeArea(
                child: Material(
                  color: Colors.transparent,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 3,
                    ),
                    decoration: BoxDecoration(
                      color: BuildConfig.badgeColor,
                      borderRadius: const BorderRadius.only(
                        bottomLeft: Radius.circular(8),
                      ),
                    ),
                    child: Text(
                      label,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 10,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 1.2,
                      ),
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
