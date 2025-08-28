import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';

class QrGenerator extends StatelessWidget {
  final String lastName;
  final String firstName;
  final String middleName;

  const QrGenerator({
    super.key,
    required this.lastName,
    required this.firstName,
    required this.middleName,
  });

  @override
  Widget build(BuildContext context) {
    final qrData = "$lastName, $firstName $middleName"; // QR content

    return Center(
      child: Card(
        elevation: 8,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        child: Stack(
          children: [
            Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  QrImageView(
                    data: qrData,
                    version: QrVersions.auto,
                    size: 200,
                  ),
                  const SizedBox(height: 12),
                  Text(
                    qrData,
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                ],
              ),
            ),
            // ❌ Close button
            Positioned(
              right: 0,
              child: IconButton(
                icon: const Icon(Icons.close, color: Colors.red),
                onPressed: () => Navigator.pop(context),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
