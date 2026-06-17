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
      final payload = _payload();
      
      // qr_flutter handles the matrix rendering seamlessly here
      return QrImageView(
        data: payload,
        version: QrVersions.auto,
        size: size,
        gapless: false,
        eyeStyle: QrEyeStyle(
          eyeShape: QrEyeShape.square,
          color: Theme.of(context).colorScheme.onSurface,
        ),
        dataModuleStyle: QrDataModuleStyle(
          dataModuleShape: QrDataModuleShape.square,
          color: Theme.of(context).colorScheme.onSurface,
        ),
      );
    } catch (_) {
      // Fallback UI if the QR generation throws any unexpected errors
      final initials = '${firstName.isNotEmpty ? firstName[0] : ''}${lastName.isNotEmpty ? lastName[0] : ''}';
      return SizedBox(
        width: size,
        height: size,
        child: CircleAvatar(
          child: Text(initials.toUpperCase(), style: const TextStyle(fontSize: 24)),
        ),
      );
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
    required this.contactNo,
    required this.birthday,
    required this.address,
    required this.referrer,
  });

  @override
  Widget build(BuildContext context) {
    final fullName = '$lastName, $firstName $middleName'.trim();
    
    return Center(
      child: Card(
        elevation: 6,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Renders the updated QR code with full payload details
              MemberQr(
                lastName: lastName,
                firstName: firstName,
                middleName: middleName,
                contactNo: contactNo,
                birthday: birthday,
                address: address,
                referrer: referrer,
                size: 200,
              ),
              const SizedBox(height: 16),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Flexible(
                    child: Text(
                      fullName,
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  IconButton(
                    icon: const Icon(Icons.copy),
                    tooltip: 'Copy name to clipboard',
                    onPressed: () {
                      Clipboard.setData(ClipboardData(text: fullName));
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
