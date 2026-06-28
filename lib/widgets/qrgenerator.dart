import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:bot_toast/bot_toast.dart';
import '../theme.dart';
import 'memberqr.dart';

class QrGenerator extends StatelessWidget {
  final String lastName;
  final String firstName;
  final String middleName;
  final String contactNo;
  final String birthday;
  final String address;
  final String referrer;
  final String? qrToken;

  const QrGenerator({
    super.key,
    required this.lastName,
    required this.firstName,
    required this.middleName,
    required this.contactNo,
    required this.birthday,
    required this.address,
    required this.referrer,
    this.qrToken,
  });

  @override
  Widget build(BuildContext context) {
    // String to copy to clipboard
    final clipboardText = '$lastName, $firstName $middleName';

    return Center(
      child: Card(
        elevation: 6,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(appRadius),
        ),
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // 4. Generate QR Image
              MemberQr(
                lastName: lastName,
                firstName: firstName,
                middleName: middleName,
                contactNo: contactNo,
                birthday: birthday,
                address: address,
                referrer: referrer,
                qrToken: qrToken,
                size: 240,
              ),
              const SizedBox(height: 20),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Flexible(
                    child: Text(
                      clipboardText,
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  IconButton(
                    iconSize: 28,
                    icon: const Icon(Icons.copy),
                    tooltip: 'Copy name',
                    onPressed: () {
                      Clipboard.setData(ClipboardData(text: clipboardText));
                      BotToast.showText(text: 'Name Copied to Clipboard');
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
