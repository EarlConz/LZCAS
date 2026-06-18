// QR scanning button with camera-based QR code scanning via mobile_scanner.
// Falls back to manual text-paste lookup if the camera is unavailable.

import 'package:flutter/material.dart';
import 'package:lzcas/db/db.dart';
import 'package:lzcas/dialogs/qr_scanner_dialog.dart';

class QRScanButton extends StatelessWidget {
  /// Optional callback invoked after a member is found via QR scan.
  /// Receives the found [Member] row. When provided, the default info
  /// dialog is skipped so the caller can handle the result.
  final void Function(Member member)? onMemberFound;

  const QRScanButton({super.key, this.onMemberFound});

  Future<void> _scanAndLookup(BuildContext context) async {
    final scanned = await showQrScannerDialog(context);

    if (scanned == null || scanned.isEmpty) return;
    if (!context.mounted) return;

    await _lookupByQr(context, scanned);
  }

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
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, tc.text.trim()),
            child: const Text('Find'),
          ),
        ],
      ),
    );

    if (result == null || result.isEmpty) return;

    await _lookupByQr(context, result);
  }

  Future<void> _lookupByQr(BuildContext context, String qrValue) async {
    final rows = await repository.fetchMembers();
    Member? memberRow;
    try {
      memberRow = rows.firstWhere((r) => r.qr == qrValue);
    } catch (_) {
      memberRow = null;
    }

    if (!context.mounted) return;

    if (memberRow != null) {
      final m = memberRow;

      // If a callback was provided, invoke it and skip the detail dialog
      if (onMemberFound != null) {
        onMemberFound!(m);
        return;
      }

      showDialog(
        context: context,
        builder: (_) => AlertDialog(
          title: const Text('Member Found'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Name: ${m.firstName ?? ''} ${m.middleName ?? ''} ${m.lastName ?? ''}',
              ),
              Text('Role: ${m.role ?? ''}'),
              Text('Contact: ${m.contactNo ?? ''}'),
              Text('Birthday: ${m.birthday ?? ''}'),
              Text('Address: ${m.address ?? ''}'),
              Text('Referrer: ${m.referrer ?? ''}'),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Close'),
            ),
          ],
        ),
      );
    } else {
      showDialog(
        context: context,
        builder: (_) => AlertDialog(
          title: const Text('Not Found'),
          content: Text('No member matches QR: $qrValue'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Close'),
            ),
          ],
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<String>(
      tooltip: 'Find by QR',
      icon: const Icon(Icons.qr_code_scanner),
      onSelected: (action) {
        if (action == 'scan') {
          _scanAndLookup(context);
        } else if (action == 'paste') {
          _manualLookup(context);
        }
      },
      itemBuilder: (_) => [
        const PopupMenuItem(
          value: 'scan',
          child: ListTile(
            leading: Icon(Icons.camera_alt),
            title: Text('Scan QR'),
            subtitle: Text('Use camera'),
            dense: true,
            contentPadding: EdgeInsets.zero,
          ),
        ),
        const PopupMenuItem(
          value: 'paste',
          child: ListTile(
            leading: Icon(Icons.paste),
            title: Text('Paste QR'),
            subtitle: Text('Manual entry'),
            dense: true,
            contentPadding: EdgeInsets.zero,
          ),
        ),
      ],
    );
  }
}
