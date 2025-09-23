import 'package:flutter/material.dart';

class CustomIconButton extends StatelessWidget {
  final VoidCallback onPressed;
  final Icon icon;
  final Color? color;

  const CustomIconButton({
    super.key,
    required this.onPressed,
    required this.icon,
    this.color,
  });

  @override
  Widget build(BuildContext context) {
    return IconButton(
      onPressed: onPressed,
      icon: Icon(
        icon.icon,
        color: color ?? icon.color, // Use provided color or original icon color
        size: icon.size, // Use original icon size
      ),
      tooltip: icon.semanticLabel, // Use semantic label as tooltip
    );
  }
}
