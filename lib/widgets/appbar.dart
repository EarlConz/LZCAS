import 'package:flutter/material.dart';

class CustomAppBar extends StatelessWidget implements PreferredSizeWidget {
  final String title;

  const CustomAppBar({
    super.key,
    required this.title,
  });

  @override
  Size get preferredSize => const Size.fromHeight(60.0);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final appBarTheme = theme.appBarTheme;

    return Container(
      height: preferredSize.height,
      decoration: BoxDecoration(
        color: appBarTheme.backgroundColor ?? theme.colorScheme.surface,
        boxShadow: appBarTheme.elevation != null && appBarTheme.elevation! > 0
            ? [
                BoxShadow(
                  color: Colors.black.withOpacity(0.05),
                  blurRadius: appBarTheme.elevation!,
                  offset: const Offset(0, 2),
                ),
              ]
            : null,
      ),
      alignment: Alignment.centerLeft,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Text(
        title,
        style: appBarTheme.titleTextStyle ?? theme.textTheme.headlineSmall,
      ),
    );
  }
}
