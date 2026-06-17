import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'dart:convert';

class QrGenerator extends StatelessWidget {
  final String lastName;
  final String firstName;
  final String middleName;
  final String contactNo;
  final String birthday;
  final String address;
  final String referrer;

  const QrGenerator({
    super.key,
    required this.lastName,
    required this.firstName,
    required this.middleName,
    required this.contactNo,
    required this.birthday,
    required this.address,
    required this.referrer,
  });

  @override
  Widget build(BuildContext context) {
    // 1. Create a map of all parameters
    final qrDataMap = {
      'lastName': lastName,
      'firstName': firstName,
      'middleName': middleName,
      'contactNo': contactNo,
      'birthday': birthday,
      'address': address,
      'referrer': referrer,
    };

    // 2. Encode to a serialized string for the QR code
    final qrString = jsonEncode(qrDataMap);
    
    // 3. String to copy to clipboard
    final clipboardText = '$lastName, $firstName $middleName';

    return Center(
      child: Card(
        elevation: 6,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // 4. Generate QR Image
              QrImageView(
                data: qrString,
                version: QrVersions.auto,
                size: 200.0,
                backgroundColor: Colors.white,
              ),
              const SizedBox(height: 16),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Flexible(child: Text(clipboardText, style: const TextStyle(fontWeight: FontWeight.w500))),
                  const SizedBox(width: 12),
                  IconButton(
                    icon: const Icon(Icons.copy),
                    onPressed: () {
                      Clipboard.setData(ClipboardData(text: clipboardText));
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Name Copied to Clipboard')),
                      );
                    },
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
