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
        backgroundColor:
            backgroundColor ??
            theme.elevatedButtonTheme.style?.backgroundColor?.resolve({
              WidgetState.selected,
            }),
        foregroundColor:
            foregroundColor ??
            theme.elevatedButtonTheme.style?.foregroundColor?.resolve({
              WidgetState.selected,
            }),
        shape: theme.elevatedButtonTheme.style?.shape?.resolve({
          WidgetState.selected,
        }),
        padding: theme.elevatedButtonTheme.style?.padding?.resolve({
          WidgetState.selected,
        }),
        textStyle: theme.elevatedButtonTheme.style?.textStyle?.resolve({
          WidgetState.selected,
        }),
      ),
      onPressed: onPressed,
      child: icon != null
          ? Row(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                // constrain icon so it can't force the button wider than available
                ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 24, maxHeight: 24),
                  child: icon!,
                ),
                const SizedBox(width: 8),
                // allow the label to shrink/wrap when space is limited
                Flexible(child: label),
              ],
            )
          : // when no icon, still allow label to be flexible
          Flexible(child: label),
    );
  }
}
