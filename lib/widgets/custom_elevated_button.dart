import 'package:flutter/material.dart';
import 'package:lzcas/utils/animations.dart';

class CustomElevatedButton extends StatelessWidget {
  final VoidCallback onPressed;
  final Widget? icon;
  final Widget label;
  final Color? backgroundColor;
  final Color? foregroundColor;

  const CustomElevatedButton({
    super.key,
    required this.onPressed,
    this.icon,
    required this.label,
    this.backgroundColor,
    this.foregroundColor,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    return ScaleTap(
      child: ElevatedButton(
        style: ElevatedButton.styleFrom(
          elevation: 0,
          backgroundColor: backgroundColor ?? colorScheme.primary,
          foregroundColor: foregroundColor ?? colorScheme.onPrimary,
          shape: theme.elevatedButtonTheme.style?.shape?.resolve({}),
          padding: theme.elevatedButtonTheme.style?.padding?.resolve({}),
          textStyle: theme.elevatedButtonTheme.style?.textStyle?.resolve({}),
        ),
        onPressed: onPressed,
        child: icon != null
            ? Row(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  ConstrainedBox(
                    constraints: const BoxConstraints(
                      maxWidth: 24,
                      maxHeight: 24,
                    ),
                    child: icon!,
                  ),
                  const SizedBox(width: 8),
                  Flexible(child: label),
                ],
              )
            : Flexible(child: label),
      ),
    );
  }
}
