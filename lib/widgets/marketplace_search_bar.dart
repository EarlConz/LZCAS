// lib/widgets/marketplace_search_bar.dart
// Instant search input for the Member Marketplace.
//
// Debounces keystrokes (300 ms) so the parent only rebuilds / re-queries
// once the member pauses, and exposes the standard search affordances:
// a search prefix icon, a clear ("X") suffix button while text is present,
// and a 48dp+ touch target.

import 'dart:async';
import 'package:flutter/material.dart';
import '../theme.dart';

class MarketplaceSearchBar extends StatefulWidget {
  final ValueChanged<String> onSearchChanged;

  /// The parent owns the controller so it can clear the field from the
  /// zero-result empty state as well as from the field's own suffix button.
  final TextEditingController controller;

  /// Optional external focus node so the parent can dismiss the keyboard.
  final FocusNode? focusNode;

  final String hintText;

  const MarketplaceSearchBar({
    super.key,
    required this.onSearchChanged,
    required this.controller,
    this.focusNode,
    this.hintText = 'Search products or categories…',
  });

  @override
  State<MarketplaceSearchBar> createState() => _MarketplaceSearchBarState();
}

class _MarketplaceSearchBarState extends State<MarketplaceSearchBar> {
  Timer? _debounce;

  @override
  void dispose() {
    _debounce?.cancel();
    super.dispose();
  }

  void _onChanged(String raw) {
    _debounce?.cancel();
    // Update the suffix clear button immediately, but only emit the search
    // term after the debounce window closes.
    setState(() {});
    _debounce = Timer(const Duration(milliseconds: 300), () {
      if (mounted) widget.onSearchChanged(raw.trim());
    });
  }

  void _clear() {
    _debounce?.cancel();
    widget.controller.clear();
    widget.onSearchChanged('');
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final fill = isDark ? StockpileColors.darkInputBg : StockpileColors.inputBg;
    final text = isDark
        ? StockpileColors.darkTextPrimary
        : StockpileColors.darkText;
    final muted = isDark
        ? StockpileColors.darkTextMuted
        : StockpileColors.mutedText;

    return SizedBox(
      // 48dp minimum touch target.
      height: 52,
      child: TextField(
        controller: widget.controller,
        focusNode: widget.focusNode,
        onChanged: _onChanged,
        textInputAction: TextInputAction.search,
        style: TextStyle(color: text, fontSize: 15),
        decoration: InputDecoration(
          hintText: widget.hintText,
          hintStyle: TextStyle(color: muted),
          prefixIcon: Icon(Icons.search_rounded, color: muted, size: 22),
          suffixIcon: widget.controller.text.isEmpty
              ? null
              : IconButton(
                  tooltip: 'Clear search',
                  icon: Icon(Icons.close_rounded, color: muted, size: 22),
                  onPressed: _clear,
                ),
          filled: true,
          fillColor: fill,
          contentPadding: const EdgeInsets.symmetric(vertical: 14),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide.none,
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide.none,
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide(
              color: StockpileColors.primary900,
              width: 1.4,
            ),
          ),
        ),
      ),
    );
  }
}
