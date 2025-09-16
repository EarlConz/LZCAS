import 'package:flutter/material.dart';

class InfoCard extends StatelessWidget {
  final String title;
  final IconData icon;
  final Color contentColor;
  final Color? backgroundColor;
  final String? value;
  final String? description;
  final Widget? contentWidget;

  const InfoCard({
    super.key,
    required this.title,
    required this.icon,
    required this.contentColor,
    this.backgroundColor,
    this.value,
    this.description,
    this.contentWidget,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cardTheme = theme.cardTheme;

  final effectiveBackgroundColor = backgroundColor ?? contentColor.withAlpha((0.1 * 255).round());

    return Card(
      shape: cardTheme.shape,
      elevation: cardTheme.elevation,
      shadowColor: cardTheme.shadowColor,
      margin: cardTheme.margin,
      color: effectiveBackgroundColor,
      child: Padding(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(icon, color: contentColor, size: 22),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    title,
                    style: theme.textTheme.headlineSmall?.copyWith(
                      color: contentColor,
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            if (contentWidget != null)
              Expanded(child: contentWidget!)
            else if (value != null) ...[
              Text(
                value!,
                style: theme.textTheme.headlineLarge?.copyWith(
                  color: theme.colorScheme.onSurface,
                  fontWeight: FontWeight.bold,
                ),
              ),
              if (description != null && description!.isNotEmpty) ...[
                const SizedBox(height: 8),
                Text(
                  description!,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: contentColor.withAlpha((0.9 * 255).round()),
                  ),
                ),
              ],
            ],
          ],
        ),
      ),
    );
  }
}