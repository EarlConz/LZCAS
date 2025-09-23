import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

// Placeholder generator UI — QR generation was removed from the product. This
// stub displays the name string and a copy button so importing code can still
// use this widget if needed without pulling qr_flutter.
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
    final label = '$lastName, $firstName $middleName';
    return Center(
      child: Card(
        elevation: 6,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Flexible(child: Text(label)),
              const SizedBox(width: 12),
              IconButton(
                icon: const Icon(Icons.copy),
                onPressed: () {
                  Clipboard.setData(ClipboardData(text: label));
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Copied')));
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}
