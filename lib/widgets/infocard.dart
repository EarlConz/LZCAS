import 'package:flutter/material.dart';

import '../theme.dart';

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
    final colorScheme = theme.colorScheme;
    final cardTheme = theme.cardTheme;

    final double screenWidth = MediaQuery.of(context).size.width;
    final bool isCompact = screenWidth < 600;

    final effectiveBackgroundColor = backgroundColor ??
        (theme.brightness == Brightness.dark
            ? colorScheme.surface
            : colorScheme.surface);

    return Card(
      shape: cardTheme.shape,
      elevation: cardTheme.elevation,
      shadowColor:
          cardTheme.shadowColor ?? Colors.black.withAlpha((0.1 * 255).round()),
      margin: cardTheme.margin ?? const EdgeInsets.all(8),
      color: effectiveBackgroundColor,
      clipBehavior: Clip.antiAlias,
      child: Container(
        decoration: BoxDecoration(
          border: Border.all(color: theme.dividerColor, width: 1),
          borderRadius: BorderRadius.circular(appRadius),
        ),
        child: Padding(
          padding: EdgeInsets.all(isCompact ? 14.0 : 16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: isCompact ? 30 : 34,
                    height: isCompact ? 30 : 34,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: contentColor.withAlpha((0.12 * 255).round()),
                      borderRadius: BorderRadius.circular(appRadius),
                    ),
                    child: Icon(
                      icon,
                      color: contentColor,
                      size: isCompact ? 17 : 19,
                    ),
                  ),
                  SizedBox(width: isCompact ? 8 : 10),
                  Expanded(
                    child: Text(
                      title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleMedium?.copyWith(
                        color: colorScheme.onSurface,
                        fontSize: isCompact ? 14 : 15,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                ],
              ),
              SizedBox(height: isCompact ? 8 : 14),
              if (contentWidget != null)
                contentWidget!
              else if (value != null) ...[
                Text(
                  value!,
                  style: theme.textTheme.headlineLarge?.copyWith(
                    color: colorScheme.onSurface,
                    fontSize: isCompact ? 24 : 30,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                if (description != null && description!.isNotEmpty) ...[
                  SizedBox(height: isCompact ? 4 : 8),
                  Text(
                    description!,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: colorScheme.onSurfaceVariant,
                      fontSize: isCompact ? 12 : 13,
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
