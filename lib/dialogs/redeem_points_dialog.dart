import 'package:flutter/material.dart';

class RedeemPointsDialog extends StatefulWidget {
  final List<Map<String, dynamic>> members;

  const RedeemPointsDialog({super.key, required this.members});

  @override
  State<RedeemPointsDialog> createState() => _RedeemPointsDialogState();
}

class _RedeemPointsDialogState extends State<RedeemPointsDialog> {
  final TextEditingController _pointsController = TextEditingController();
  final TextEditingController _memberSearchController = TextEditingController();
  final FocusNode _memberFocusNode = FocusNode();

  String? selectedMember;

  @override
  void dispose() {
    _pointsController.dispose();
    _memberSearchController.dispose();
    _memberFocusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text("Redeem Points"),
      content: SizedBox(
        width: 400,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Member Search with Dropdown
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
                      ),
                      onChanged: (_) => setState(() {}),
                    ),
                    if (_memberFocusNode.hasFocus || _memberSearchController.text.isNotEmpty)
                      Container(
                        constraints: const BoxConstraints(maxHeight: 200),
                        margin: const EdgeInsets.only(top: 4),
                        decoration: BoxDecoration(
                          color: Theme.of(context).cardColor,
                          border: Border.all(color: Colors.grey.shade300),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Builder(
                          builder: (context) {
                            final List<String> memberNames = widget.members.map((m) {
                              final lastName = m['lastName'] ?? '';
                              final firstName = m['firstName'] ?? '';
                              return '$firstName $lastName'.trim();
                            }).toList();

                            final query = _memberSearchController.text.toLowerCase();
                            final filtered = memberNames.where((m) => query.isEmpty || m.toLowerCase().contains(query)).toList();

                            return ListView.builder(
                              shrinkWrap: true,
                              itemCount: filtered.length,
                              itemBuilder: (ctx, i) => ListTile(
                                title: Text(filtered[i]),
                                onTap: () {
                                  setState(() {
                                    selectedMember = filtered[i];
                                    _memberSearchController.text = filtered[i];
                                    _memberFocusNode.unfocus();
                                  });
                                },
                              ),
                            );
                          },
                        ),
                      ),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 16),

            // Points input
            TextField(
              controller: _pointsController,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                hintText: "Enter points (e.g. 1000)",
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
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

            // Here you would typically call a repository method to update member points
            // await repository.redeemPoints(selectedMember, points);

            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text("Redeemed $points points for $selectedMember!"),
              ),
            );
            Navigator.pop(context);
          },
          child: const Text("Confirm"),
        ),
      ],
    );
  }
}
