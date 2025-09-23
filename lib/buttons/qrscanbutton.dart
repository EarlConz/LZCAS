// QR scanning has been removed. This button provides a manual QR lookup
// to search for a member by QR code without requiring the mobile_scanner package.
// It avoids platform camera dependencies and keeps the UI functional on desktop.
//
// If you later reintroduce scanning, replace this with a platform-aware
// implementation that conditionally imports mobile_scanner.

import 'package:flutter/material.dart';
import 'package:lzcas/db/db.dart';

class QRScanButton extends StatelessWidget {
  const QRScanButton({super.key});

  Future<void> _manualLookup(BuildContext context) async {
    final tc = TextEditingController();
    final result = await showDialog<String?>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Find member by QR'),
        content: TextField(
          controller: tc,
          decoration: const InputDecoration(hintText: 'Paste QR code here'),
          autofocus: true,
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(ctx, tc.text.trim()), child: const Text('Find')),
        ],
      ),
    );

    if (result == null || result.isEmpty) return;

    final rows = await repository.fetchMembers();
    Member? memberRow;
    try {
      memberRow = rows.firstWhere((r) => r.qr == result);
    } catch (_) {
      memberRow = null;
    }

    if (!context.mounted) return;

    if (memberRow != null) {
      final m = memberRow;
      showDialog(
        context: context,
        builder: (_) => AlertDialog(
          title: const Text('Member Found'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Name: ${m.firstName ?? ''} ${m.middleName ?? ''} ${m.lastName ?? ''}'),
              Text('Role: ${m.role ?? ''}'),
              Text('Contact: ${m.contactNo ?? ''}'),
              Text('Birthday: ${m.birthday ?? ''}'),
              Text('Address: ${m.address ?? ''}'),
              Text('Referrer: ${m.referrer ?? ''}'),
              Text('Points: ${m.points}'),
            ],
          ),
          actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('Close'))],
        ),
      );
    } else {
      showDialog(
        context: context,
        builder: (_) => AlertDialog(
          title: const Text('Not Found'),
          content: Text('No member matches QR: $result'),
          actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('Close'))],
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return ElevatedButton.icon(
      icon: const Icon(Icons.qr_code),
      label: const Text('Find by QR'),
      onPressed: () => _manualLookup(context),
    );
  }
}
