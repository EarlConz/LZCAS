import 'package:flutter/material.dart';
import 'package:lzcas/db/db.dart';
import '../dialogs/redeem_points_dialog.dart';

class RedeemButton extends StatefulWidget {
  const RedeemButton({super.key});

  @override
  State<RedeemButton> createState() => _RedeemButtonState();
}

class _RedeemButtonState extends State<RedeemButton> {
  List<Map<String, dynamic>> members = [];

  @override
  void initState() {
    super.initState();
    _loadMembers();
  }

  Future<void> _loadMembers() async {
    final memberRows = await repository.fetchMembers();
    if (mounted) {
      setState(() {
        members = membersFromRows(memberRows);
      });
    }
  }

  void _showRedeemDialog(BuildContext context) {
    // Ensure members are loaded before showing the dialog
    _loadMembers();
    showDialog(
      context: context,
      builder: (dialogContext) {
        return RedeemPointsDialog(members: members);
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return ElevatedButton.icon(
      onPressed: () => _showRedeemDialog(context),
      icon: const Icon(Icons.redeem),
      label: const Text("Redeem Points"),
    );
  }
}
