import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';

class MemberQr extends StatelessWidget {
  final String lastName;
  final String firstName;
  final String middleName;

  const MemberQr({
    super.key,
    required this.lastName,
    required this.firstName,
    required this.middleName,
  });

  @override
  Widget build(BuildContext context) {
    final qrData = "$lastName, $firstName $middleName";

    return QrImageView(
      data: qrData,
      version: QrVersions.auto,
      size: 100.0,
      backgroundColor: Colors.white,
    );
  }
}