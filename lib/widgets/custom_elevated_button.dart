import 'package:flutter/material.dart';

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
    return ElevatedButton(
      style: ElevatedButton.styleFrom(
        backgroundColor: backgroundColor ?? theme.elevatedButtonTheme.style?.backgroundColor?.resolve({WidgetState.selected}),
        foregroundColor: foregroundColor ?? theme.elevatedButtonTheme.style?.foregroundColor?.resolve({WidgetState.selected}),
        shape: theme.elevatedButtonTheme.style?.shape?.resolve({WidgetState.selected}),
        padding: theme.elevatedButtonTheme.style?.padding?.resolve({WidgetState.selected}),
        textStyle: theme.elevatedButtonTheme.style?.textStyle?.resolve({WidgetState.selected}),
      ),
      onPressed: onPressed,
      child: icon != null
          ? Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                icon!,
                const SizedBox(width: 8),
                label,
              ],
            )
          : label,
    );
  }
}
