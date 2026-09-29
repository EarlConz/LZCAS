// lib/widgets/qr_code_view.dart
//
// A QR code for any string. `MemberQr` renders the member's identity token
// and carries all the profile-shaped arguments that go with it; this one
// exists because a cash-on-delivery code is not an identity and should not
// borrow that widget's shape.
//
// Quiet zone included: a QR printed flush to the edge of a dark card is a
// QR that phones fail to read, and the failure looks like a broken feature
// rather than a missing margin.

import 'package:flutter/material.dart';
import 'package:qr/qr.dart';

class QrCodeView extends StatelessWidget {
  final String data;
  final double size;

  /// Module colour. Defaults to near-black rather than the theme's
  /// onSurface: in dark mode that would paint light modules on a light
  /// background, which scanners read as inverted and most refuse.
  final Color? moduleColor;

  /// Background behind the code, including the quiet zone.
  final Color backgroundColor;

  const QrCodeView({
    super.key,
    required this.data,
    this.size = 220,
    this.moduleColor,
    this.backgroundColor = Colors.white,
  });

  @override
  Widget build(BuildContext context) {
    Widget child;
    try {
      // Medium correction: the code is shown on a phone screen that may be
      // scratched, dim or held at an angle, and the payload is short enough
      // that the extra redundancy costs no legibility.
      final qr = QrCode.fromData(
        data: data,
        errorCorrectLevel: QrErrorCorrectLevel.M,
      );
      child = CustomPaint(
        size: Size.square(size),
        painter: _QrPainter(
          image: QrImage(qr),
          color: moduleColor ?? const Color(0xFF111111),
        ),
      );
    } catch (_) {
      // An unencodable payload is a bug, not something to hide behind a
      // blank square — say so, because a silent empty box during a handover
      // leaves the rider and the member staring at each other.
      child = SizedBox(
        width: size,
        height: size,
        child: const Center(
          child: Text(
            'This code could not be displayed.\nAsk the cashier to confirm '
            'the delivery instead.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 12, color: Color(0xFF8E8E9A)),
          ),
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(16), // the quiet zone
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: BorderRadius.circular(12),
      ),
      child: child,
    );
  }
}

class _QrPainter extends CustomPainter {
  final QrImage image;
  final Color color;

  _QrPainter({required this.image, required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = color;
    final count = image.moduleCount;
    final cell = size.width / count;
    for (var x = 0; x < count; x++) {
      for (var y = 0; y < count; y++) {
        if (image.isDark(y, x)) {
          // A hair of overlap: exact cell rects leave seams at some sizes,
          // and a seam across a module is a module a scanner may misread.
          canvas.drawRect(
            Rect.fromLTWH(x * cell, y * cell, cell + 0.5, cell + 0.5),
            paint,
          );
        }
      }
    }
  }

  @override
  bool shouldRepaint(covariant _QrPainter old) =>
      old.image != image || old.color != color;
}
