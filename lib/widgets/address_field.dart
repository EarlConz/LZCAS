// lib/widgets/address_field.dart
//
// An address text field that suggests real places as you type (Part 3, T3:
// "make sure address has autocomplete"). Suggestions come from the same
// OpenStreetMap search the map pickers use, limited to the Philippines.
// Anything can still be typed: a suggestion only fills the field.

import 'dart:async';

import 'package:flutter/material.dart';

import 'package:lzcas/services/nominatim_geocoding_service.dart';

class AddressField extends StatefulWidget {
  final TextEditingController controller;
  final String hintText;
  final ValueChanged<String>? onChanged;

  const AddressField({
    super.key,
    required this.controller,
    this.hintText = 'Optional',
    this.onChanged,
  });

  @override
  State<AddressField> createState() => _AddressFieldState();
}

class _AddressFieldState extends State<AddressField> {
  final _focus = FocusNode();

  /// Bumped on every keystroke: only the newest search may show its
  /// results, and an older one finishing late must not replace them.
  int _ticket = 0;
  Iterable<String> _last = const [];

  /// The suggestion just picked: searching for it again would only offer
  /// it back.
  String? _picked;

  @override
  void dispose() {
    _focus.dispose();
    super.dispose();
  }

  /// "Rizal Street, Poblacion, Cebu City, Cebu, Central Visayas, 6000,
  /// Philippines" without the country every result shares.
  static String _tidy(String s) =>
      s.replaceAll(RegExp(r',\s*Philippines$'), '').trim();

  Future<Iterable<String>> _suggest(TextEditingValue value) async {
    final q = value.text.trim();
    final ticket = ++_ticket;
    if (q.length < 4 || q == _picked) return _last = const [];
    // The search service allows about one request a second: wait for a
    // pause in typing rather than searching every letter.
    await Future<void>.delayed(const Duration(milliseconds: 600));
    if (ticket != _ticket) return _last;
    final results = await NominatimGeocodingService.search(q, limit: 5);
    if (ticket != _ticket) return _last;
    return _last = results.map((r) => _tidy(r.displayName)).toSet();
  }

  @override
  Widget build(BuildContext context) {
    final screenW = MediaQuery.sizeOf(context).width;
    return RawAutocomplete<String>(
      textEditingController: widget.controller,
      focusNode: _focus,
      optionsBuilder: _suggest,
      onSelected: (s) {
        _picked = s;
        widget.onChanged?.call(s);
      },
      fieldViewBuilder: (context, controller, focusNode, onSubmit) => TextFormField(
        controller: controller,
        focusNode: focusNode,
        decoration: InputDecoration(
          hintText: widget.hintText,
          suffixIcon: const Icon(Icons.place_outlined),
        ),
        textInputAction: TextInputAction.next,
        onChanged: widget.onChanged,
      ),
      optionsViewBuilder: (context, onSelected, options) => Align(
        alignment: Alignment.topLeft,
        child: Material(
          elevation: 4,
          borderRadius: BorderRadius.circular(12),
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxHeight: 260,
              maxWidth: (screenW - 32).clamp(240.0, 480.0),
            ),
            child: ListView.builder(
              padding: EdgeInsets.zero,
              shrinkWrap: true,
              itemCount: options.length,
              itemBuilder: (context, i) {
                final s = options.elementAt(i);
                return ListTile(
                  dense: true,
                  minTileHeight: 48,
                  leading: const Icon(Icons.place_outlined, size: 20),
                  title: Text(s, maxLines: 2, overflow: TextOverflow.ellipsis),
                  onTap: () => onSelected(s),
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}
