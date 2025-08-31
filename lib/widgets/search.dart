import 'package:flutter/material.dart';

class SearchBarWidget extends StatelessWidget {
  final ValueChanged<String> onChanged;
  final String hintText;
  final double borderRadius;
  final EdgeInsetsGeometry? contentPadding;

  const SearchBarWidget({
    super.key,
    required this.onChanged,
    required this.hintText,
    this.borderRadius = 12.0,
    this.contentPadding,
  });

  @override
  Widget build(BuildContext context) {
    return TextField(
      decoration: InputDecoration(
        hintText: hintText,
        prefixIcon: const Icon(Icons.search),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(borderRadius),
        ),
        contentPadding: contentPadding,
      ),
      onChanged: onChanged,
    );
  }
}
