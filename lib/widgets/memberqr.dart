import 'package:flutter/material.dart';
import 'package:qr/qr.dart';
import 'dart:convert'; // Required for jsonEncode

class MemberQr extends StatelessWidget {
  final String lastName;
  final String firstName;
  final String middleName;
  final String contactNo;
  final String birthday;
  final String address;
  final String referrer;
  final double size;

  /// Optional DB qr token. When provided, the QR encodes only this token
  /// (compact, scannable for member lookup). When null, encodes the full
  /// member JSON profile (backward compatible).
  final String? qrToken;

  const MemberQr({
    super.key,
    required this.lastName,
    required this.firstName,
    required this.middleName,
    required this.contactNo,
    required this.birthday,
    required this.address,
    required this.referrer,
    this.size = 160,
    this.qrToken,
  });

  String _payload() {
    // If a DB qr token is provided, encode just the token so the scanner
    // can look up the member directly via the members.qr column.
    if (qrToken != null && qrToken!.isNotEmpty) {
      return qrToken!;
    }
    // Fallback: encode the full member JSON profile
    final qrDataMap = {
      'lastName': lastName,
      'firstName': firstName,
      'middleName': middleName,
      'contactNo': contactNo,
      'birthday': birthday,
      'address': address,
      'referrer': referrer,
    };
    return jsonEncode(qrDataMap);
  }

  @override
  Widget build(BuildContext context) {
    try {
      final qr = QrCode.fromData(
        data: _payload(),
        errorCorrectLevel: QrErrorCorrectLevel.L,
      );
      final qrImage = QrImage(qr);
      return CustomPaint(
        size: Size.square(size),
        painter: _QrPainterFromMatrix(
          qrImage: qrImage,
          color: Theme.of(context).colorScheme.onSurface,
        ),
      );
    } catch (_) {
      final initials =
          '${firstName.isNotEmpty ? firstName[0] : ''}${lastName.isNotEmpty ? lastName[0] : ''}';
      return CircleAvatar(child: Text(initials.toUpperCase()));
    }
  }
}

class MemberQrWithName extends StatelessWidget {
  final String lastName;
  final String firstName;
  final String middleName;
  final String contactNo;
  final String birthday;
  final String address;
  final String referrer;
  final String? qrToken;

  const MemberQrWithName({
    super.key,
    required this.lastName,
    required this.firstName,
    required this.middleName,
    this.contactNo = '',
    this.birthday = '',
    this.address = '',
    this.referrer = '',
    this.qrToken,
  });

  @override
  Widget build(BuildContext context) {
    final fullName = ('$firstName $middleName $lastName').trim();
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        MemberQr(
          lastName: lastName,
          firstName: firstName,
          middleName: middleName,
          contactNo: contactNo,
          birthday: birthday,
          address: address,
          referrer: referrer,
          qrToken: qrToken,
          size: 180,
        ),
        const SizedBox(height: 10),
        Text(fullName, style: Theme.of(context).textTheme.titleLarge),
      ],
    );
  }
}

class _QrPainterFromMatrix extends CustomPainter {
  final QrImage qrImage;
  final Color color;

  _QrPainterFromMatrix({required this.qrImage, required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = color;
    final moduleCount = qrImage.moduleCount;
    final cellSize = size.width / moduleCount;
    for (var x = 0; x < moduleCount; x++) {
      for (var y = 0; y < moduleCount; y++) {
        if (qrImage.isDark(y, x)) {
          canvas.drawRect(
            Rect.fromLTWH(x * cellSize, y * cellSize, cellSize, cellSize),
            paint,
          );
        }
      }
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
