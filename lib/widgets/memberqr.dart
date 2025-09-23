import 'package:flutter/material.dart';

// Placeholder for Member QR view. QR features were removed from the UI and
// QR package dependencies were removed from pubspec.yaml. Keep a small stub
// so other code can import this file without pulling qr_flutter.
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
    // Render a simple avatar with initials instead of a QR code
    final initials = '${firstName.isNotEmpty ? firstName[0] : ''}${lastName.isNotEmpty ? lastName[0] : ''}';
    return CircleAvatar(
      child: Text(initials.toUpperCase()),
    );
  }
}
