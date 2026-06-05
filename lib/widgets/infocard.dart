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
    
    final double screenWidth = MediaQuery.of(context).size.width;
    final bool isCompact = screenWidth < 600;

    final effectiveBackgroundColor = backgroundColor ??
        (theme.brightness == Brightness.dark
            ? theme.cardColor
            : contentColor.withAlpha((0.1 * 255).round()));

    return Card(
      shape: cardTheme.shape,
      elevation: (cardTheme.elevation ?? 4) + 2,
      shadowColor: cardTheme.shadowColor ?? Colors.black.withAlpha((0.15 * 255).round()),
      margin: cardTheme.margin ?? const EdgeInsets.all(8),
      color: effectiveBackgroundColor,
      clipBehavior: Clip.antiAlias,
      child: Container(
        decoration: BoxDecoration(
          border: theme.brightness == Brightness.light
              ? Border.all(color: Colors.grey.shade200, width: 1)
              : null,
        ),
        child: Padding(
          padding: EdgeInsets.all(isCompact ? 14.0 : 20.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(icon, color: contentColor, size: isCompact ? 18 : 22),
                  SizedBox(width: isCompact ? 8 : 12),
                  Expanded(
                    child: Text(
                      title,
                      style: theme.textTheme.headlineSmall?.copyWith(
                        color: contentColor,
                        fontSize: isCompact ? 15 : 18, 
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ],
              ),
              SizedBox(height: isCompact ? 8 : 12),
              if (contentWidget != null)
                contentWidget!
              else if (value != null) ...[
                Text(
                  value!,
                  style: theme.textTheme.headlineLarge?.copyWith(
                    color: theme.colorScheme.onSurface,
                    fontSize: isCompact ? 24 : 32, 
                    fontWeight: FontWeight.w800,
                  ),
                ),
                if (description != null && description!.isNotEmpty) ...[
                  SizedBox(height: isCompact ? 4 : 8),
                  Text(
                    description!,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: contentColor.withAlpha((0.9 * 255).round()),
                      fontSize: isCompact ? 12 : 14,
                    ),
                  ),
                ],
              ],
            ],
          ),
        ),
      ),
    );
  }
}