// lib/widgets/product_tile.dart
//
// A product's picture, or its letter on a tinted tile when it has none.
// Shared by the member's shop and the admin's product screens, so a
// product looks the same everywhere.

import 'package:flutter/material.dart';

import '../db/db.dart';
import '../utils/fonts.dart';

/// The picture (v63) when the product has one; otherwise its first letter.
/// The tint follows the name, so a product keeps its colour across the
/// shop, the order and the purchases. The letter also shows while the
/// picture loads and if it fails to.
class ProductTile extends StatelessWidget {
  final String name;
  final double size;

  /// The stored path from [Item.imagePath]; null shows the letter.
  final String? imagePath;

  /// Fill the available width at this height, for a card's picture, instead
  /// of a [size] square.
  final double? height;

  const ProductTile(
    this.name, {
    super.key,
    this.size = 48,
    this.imagePath,
    this.height,
  });

  static const _light = [
    (Color(0xFFFFF7DF), Color(0xFFB24800)),
    (Color(0xFFE9EBFF), Color(0xFF0029CC)),
    (Color(0xFFDCFCE7), Color(0xFF15803D)),
  ];

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final banner = height != null;
    final side = banner ? height! : size;
    final radius = banner ? 12.0 : size / 4;

    final t = name.trim();
    final letter = t.isEmpty ? '?' : t[0].toUpperCase();
    final (bg, fg) =
        _light[t.codeUnits.fold<int>(0, (a, b) => a + b) % _light.length];
    final tile = Container(
      width: banner ? double.infinity : size,
      height: side,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: dark ? fg.withAlpha(48) : bg,
        borderRadius: BorderRadius.circular(radius),
      ),
      child: Text(
        letter,
        style: StockpileFonts.satoshi(
          fontSize: side * (banner ? 0.32 : 0.38),
          fontWeight: FontWeight.w700,
          color: dark ? Colors.white : fg,
        ),
      ),
    );

    if ((imagePath ?? '').trim().isEmpty) return tile;
    final url = repository.productImageUrl(imagePath);
    if (url == null) return tile;

    // Decoded at the size it is drawn, not the uploaded 800 px.
    final px = (side * MediaQuery.devicePixelRatioOf(context)).round();
    return Semantics(
      image: true,
      label: t,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(radius),
        child: SizedBox(
          width: banner ? double.infinity : size,
          height: side,
          child: Image.network(
            url,
            fit: BoxFit.cover,
            cacheWidth: banner ? null : px,
            cacheHeight: banner ? px : null,
            frameBuilder: (_, child, frame, sync) =>
                frame == null && !sync ? tile : child,
            errorBuilder: (_, _, _) => tile,
          ),
        ),
      ),
    );
  }
}
