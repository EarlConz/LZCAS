import 'package:flutter/material.dart';

class RedeemButton extends StatefulWidget {
  const RedeemButton({super.key});

  @override
  State<RedeemButton> createState() => _RedeemButtonState();
}

class _RedeemButtonState extends State<RedeemButton> {
  final TextEditingController _pointsController = TextEditingController();
  final TextEditingController _memberSearchController = TextEditingController();
  final FocusNode _memberFocusNode = FocusNode();

  String? selectedMember;
  // ✅ Only real members, no "Non Member"
  final List<String> members = ["Member A", "Member B", "Member C"];

  @override
  void dispose() {
    _pointsController.dispose();
    _memberSearchController.dispose();
    _memberFocusNode.dispose();
    super.dispose();
  }

  void _showRedeemDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setState) {
            return AlertDialog(
              title: const Text("Redeem Points"),
              content: SizedBox(
                width: 400,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // 🔎 Member Search with Dropdown
                    FocusScope(
                      child: Focus(
                        focusNode: _memberFocusNode,
                        child: Column(
                          children: [
                            TextField(
                              controller: _memberSearchController,
                              decoration: const InputDecoration(
                                labelText: "Search Member",
                                hintText: "Type to search...",
                                prefixIcon: Icon(Icons.search),
                                border: OutlineInputBorder(),
                              ),
                              onChanged: (_) => setState(() {}),
                            ),
                            if (_memberFocusNode.hasFocus ||
                                _memberSearchController.text.isNotEmpty)
                              Container(
                                constraints: const BoxConstraints(maxHeight: 200),
                                margin: const EdgeInsets.only(top: 4),
                                decoration: BoxDecoration(
                                  color: Colors.white,
                                  border: Border.all(color: Colors.grey.shade300),
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: ListView(
                                  shrinkWrap: true,
                                  children: members
                                      .where((m) {
                                        final query =
                                            _memberSearchController.text.toLowerCase();
                                        return query.isEmpty ||
                                            m.toLowerCase().contains(query);
                                      })
                                      .map((m) => ListTile(
                                            title: Text(m),
                                            onTap: () {
                                              setState(() {
                                                selectedMember = m;
                                                _memberSearchController.text = m;
                                                _memberFocusNode.unfocus();
                                              });
                                            },
                                          ))
                                      .toList(),
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),

                    const SizedBox(height: 16),

                    // 🔢 Points input
                    TextField(
                      controller: _pointsController,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                        hintText: "Enter points (e.g. 1000)",
                        border: OutlineInputBorder(),
                      ),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(dialogContext),
                  child: const Text("Cancel"),
                ),
                ElevatedButton(
                  onPressed: () {
                    final points = int.tryParse(_pointsController.text) ?? 0;

                    if (selectedMember == null || selectedMember!.isEmpty) {
                      showDialog(
                        context: context,
                        builder: (ctx) => AlertDialog(
                          title: const Text("Error"),
                          content: const Text("Please select a member."),
                          actions: [
                            TextButton(
                              onPressed: () => Navigator.pop(ctx),
                              child: const Text("OK"),
                            ),
                          ],
                        ),
                      );
                      return;
                    }

                    if (points <= 0) {
                      showDialog(
                        context: context,
                        builder: (ctx) => AlertDialog(
                          title: const Text("Error"),
                          content: const Text("Please enter valid points."),
                          actions: [
                            TextButton(
                              onPressed: () => Navigator.pop(ctx),
                              child: const Text("OK"),
                            ),
                          ],
                        ),
                      );
                      return;
                    }

                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                          content:
                              Text("Redeemed $points points for $selectedMember!")),
                    );
                    Navigator.pop(dialogContext);
                  },
                  child: const Text("Confirm"),
                ),
              ],
            );
          },
        );
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
