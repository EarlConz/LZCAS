import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:qr_flutter/qr_flutter.dart';
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
  });

  String _payload() {
    // Standardizes all properties into a clean JSON structure
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
      final qr = QrCode(4, QrErrorCorrectLevel.L);
      qr.addData(payload);
      qr.make();
      return CustomPaint(
        size: Size.square(size),
        painter: _QrPainterFromMatrix(
          qr: qr,
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

  const MemberQrWithName({
    super.key,
    required this.lastName,
    required this.firstName,
    required this.middleName,
    this.id,
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
          id: id,
          size: 160,
        ),
        const SizedBox(height: 8),
        Text(fullName, style: Theme.of(context).textTheme.titleMedium),
      ],
    );
  }
}

class _QrPainterFromMatrix extends CustomPainter {
  final QrCode qr;
  final Color color;

  _QrPainterFromMatrix({required this.qr, required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = color;
    final moduleCount = qr.moduleCount;
    final cellSize = size.width / moduleCount;
    for (var x = 0; x < moduleCount; x++) {
      for (var y = 0; y < moduleCount; y++) {
        if (qr.isDark(y, x)) {
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
