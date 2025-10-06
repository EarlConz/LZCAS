import 'package:flutter/material.dart';
import 'package:lzcas/db/db.dart';

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
  Member? _resolvedMember;
  int? _selectedDenomination;
  final List<int> _denoms = [1000, 2000, 5000, 10000, 20000];

  @override
  void initState() {
    super.initState();
    _pointsController.addListener(() => setState(() {}));
  }

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
      title: const Text('Redeem Points'),
      content: SizedBox(
        width: 400,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Focus(
              focusNode: _memberFocusNode,
              child: Column(
                children: [
                  TextField(
                    controller: _memberSearchController,
                    decoration: const InputDecoration(
                      labelText: 'Search Member',
                      hintText: 'Type to search...',
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
                        builder: (ctx) {
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
                            itemBuilder: (c, i) {
                              return ListTile(
                                title: Text(filtered[i]),
                                onTap: () async {
                                  setState(() {
                                    selectedMember = filtered[i];
                                    _memberSearchController.text = filtered[i];
                                    _memberFocusNode.unfocus();
                                  });
                                  // resolve member and cache
                                  final rows = await repository.fetchMembers();
                                  try {
                                    final m = rows.firstWhere((r) {
                                      final name = '${r.firstName ?? ''} ${r.lastName ?? ''}'.trim();
                                      return name == selectedMember;
                                    });
                                    setState(() => _resolvedMember = m);
                                  } catch (_) {
                                    setState(() => _resolvedMember = null);
                                  }
                                },
                              );
                            },
                          );
                        },
                      ),
                    ),
                ],
              ),
            ),

            const SizedBox(height: 16),

            // Denomination picker (only allow predefined redeemable amounts)
            Builder(builder: (ctx) {
              // Only show denominations after a member has been resolved.
              if (_resolvedMember == null) {
                return const SizedBox.shrink();
              }
              final available = _resolvedMember!.points;
              final canUse = _denoms.where((d) => d <= available).toList();
              if (canUse.isEmpty) {
                return Card(
                  color: Colors.red.shade50,
                  child: Padding(
                    padding: const EdgeInsets.all(8.0),
                    child: Row(
                      children: [
                        const Icon(Icons.error_outline, color: Colors.red),
                        const SizedBox(width: 8),
                        Expanded(child: Text('Insufficient Reward Points: ${_resolvedMember!.points}')),
                      ],
                    ),
                  ),
                );
              }
              return DropdownButtonFormField<int>(
                decoration: const InputDecoration(labelText: 'Redeem Amount'),
                initialValue: _selectedDenomination,
                items: canUse.map((d) => DropdownMenuItem(value: d, child: Text(d.toString()))).toList(),
                onChanged: (v) => setState(() => _selectedDenomination = v),
              );
            }),
            const SizedBox(height: 8),
            // show warning if redeem amount exceeds member balance
            const SizedBox.shrink(),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        ElevatedButton(
          onPressed: () async {
            // move all async work into a helper to avoid using BuildContext after awaits
            final response = await _attemptRedeem();
            if (!mounted) return;

            // handle UI synchronously after the mounted check
            _handleRedeemResult(response);
          },
          child: const Text('Confirm'),
        ),
      ],
    );
  }

  Future<_RedeemResult> _attemptRedeem() async {
    final points = _selectedDenomination ?? 0;

    if (selectedMember == null || selectedMember!.isEmpty) return _RedeemResult.notSelected;
    if (points <= 0) return _RedeemResult.invalidAmount;

    // Resolve member id from selectedMember label
    final memberRows = await repository.fetchMembers();
    Member? target;
    try {
      target = memberRows.firstWhere((r) {
        final name = '${r.firstName ?? ''} ${r.lastName ?? ''}'.trim();
        return name == selectedMember;
      });
    } catch (_) {
      target = null;
    }
    if (target == null) return _RedeemResult.notFound;

  if (target.points < points) return _RedeemResult.insufficient;

    // Use repository helper to deduct points
    final ok = await repository.redeemPoints(memberId: target.id, points: points);
    return ok ? _RedeemResult.success : _RedeemResult.failed;
  }

  void _handleRedeemResult(_RedeemResult response) {
    switch (response) {
      case _RedeemResult.notSelected:
        showDialog(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('Error'),
            content: const Text('Please select a member.'),
            actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('OK'))],
          ),
        );
        break;
      case _RedeemResult.invalidAmount:
        showDialog(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('Error'),
            content: const Text('Please enter valid points.'),
            actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('OK'))],
          ),
        );
        break;
      case _RedeemResult.notFound:
        showDialog(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('Error'),
            content: const Text('Selected member not found.'),
            actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('OK'))],
          ),
        );
        break;
      case _RedeemResult.insufficient:
        showDialog(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('Error'),
            content: const Text('Member does not have enough points to redeem.'),
            actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('OK'))],
          ),
        );
        break;
      case _RedeemResult.success:
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Redeemed ${_selectedDenomination ?? 0} points for $selectedMember')),
        );
        Navigator.pop(context);
        break;
      case _RedeemResult.failed:
        showDialog(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('Error'),
            content: const Text('Failed to redeem points.'),
            actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('OK'))],
          ),
        );
    }
  }
}

enum _RedeemResult { notSelected, invalidAmount, notFound, insufficient, success, failed }
