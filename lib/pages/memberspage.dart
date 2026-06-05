import 'package:flutter/material.dart';
import '/widgets/memberstable.dart';
import '/widgets/memberdetails.dart';
import 'package:lzcas/dialogs/edit_member_dialog.dart';
import '/dialogs/confirmation_dialog.dart';

class MembersPage extends StatefulWidget {
  const MembersPage({super.key});

  @override
  State<MembersPage> createState() => _MembersPageState();
}

class _MembersPageState extends State<MembersPage> {
  Map<String, dynamic>? selectedMember;
  final GlobalKey<MembersTableState> _tableKey = GlobalKey<MembersTableState>();

  void _handleRowSelection(Map<String, dynamic> member, bool isDesktop) {
    setState(() {
      selectedMember = member;
    });

    if (!isDesktop) {
      showDialog<void>(
        context: context,
        builder: (dialogContext) => _MemberDetailsDialog(
          member: member,
          onEdit: () {
            Navigator.pop(dialogContext);
            _openEditDialog(member);
          },
          onDelete: () {
            Navigator.pop(dialogContext);
            _confirmDeleteMember(member);
          },
        ),
      );
    }
  }

  void _openEditDialog(Map<String, dynamic> member) {
    showDialog(
      context: context,
      builder: (context) => EditMemberDialog(
        member: member,
        onMemberUpdated: (updatedMember) => _updateMember(member, updatedMember),
      ),
    );
  }

  void _confirmDeleteMember(Map<String, dynamic> member) {
    showDialog<bool>(
      context: context,
      builder: (context) => ConfirmationDialog(
        title: "Confirm Delete",
        content: "Do you want to delete ${member['firstName']}?",
        onConfirm: () => _deleteMember(member),
      ),
    );
  }

  void _updateMember(Map<String, dynamic> oldMember, Map<String, dynamic> updatedMember) {
    _tableKey.currentState?.updateMember(oldMember, updatedMember);
    setState(() {
      selectedMember = {...oldMember, ...updatedMember};
    });

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text("Member updated successfully!")),
    );
  }

  void _deleteMember(Map<String, dynamic> member) {
    _tableKey.currentState?.removeMember(member);
    setState(() {
      if (selectedMember?['id'] == member['id']) {
        selectedMember = null;
      }
    });

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text("Member deleted")),
    );
  }

  @override
  Widget build(BuildContext context) {
    final double screenWidth = MediaQuery.of(context).size.width;
    final bool isDesktop = screenWidth >= 850;

    return Scaffold(
      body: SafeArea(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              flex: 3,
              child: MembersTable(
                key: _tableKey,
                onRowSelected: (member) => _handleRowSelection(member, isDesktop),
              ),
            ),

            if (isDesktop && selectedMember != null) ...[
              const VerticalDivider(width: 1, thickness: 1),
              Container(
                width: 380,
                color: Theme.of(context).colorScheme.surface,
                child: Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(20, 16, 12, 8),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(
                              "Details",
                              style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
                            ),
                          ),
                          IconButton(
                            tooltip: 'Edit member',
                            onPressed: () => _openEditDialog(selectedMember!),
                            icon: const Icon(Icons.edit_outlined, color: Colors.blue),
                          ),
                          IconButton(
                            tooltip: 'Delete member',
                            onPressed: () => _confirmDeleteMember(selectedMember!),
                            icon: const Icon(Icons.delete_outline, color: Colors.red),
                          ),
                          IconButton(
                            tooltip: 'Close panel',
                            onPressed: () => setState(() => selectedMember = null),
                            icon: const Icon(Icons.close),
                          ),
                        ],
                      ),
                    ),
                    const Divider(),
                    Expanded(
                      child: SingleChildScrollView(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        child: MemberDetailsCard(member: selectedMember!),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}


class _MemberDetailsDialog extends StatelessWidget {
  const _MemberDetailsDialog({
    required this.member,
    required this.onEdit,
    required this.onDelete,
  });

  final Map<String, dynamic> member;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final fullName = [
      member['firstName'],
      member['middleName'],
      member['lastName'],
    ].where((part) => part != null && part.toString().trim().isNotEmpty).join(' ');

    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 760),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(18, 16, 18, 18),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      fullName.isEmpty ? 'Member Information' : fullName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
                    ),
                  ),
                  IconButton(
                    tooltip: 'Edit member',
                    onPressed: onEdit,
                    icon: const Icon(Icons.edit_outlined, color: Colors.blue),
                  ),
                  IconButton(
                    tooltip: 'Delete member',
                    onPressed: onDelete,
                    icon: const Icon(Icons.delete_outline, color: Colors.red),
                  ),
                  IconButton(
                    tooltip: 'Close',
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Flexible(
                child: SingleChildScrollView(
                  child: MemberDetailsCard(member: member),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
