import 'package:flutter/material.dart';
import 'package:lzcas/utils/animations.dart';
import '/widgets/memberstable.dart';
import '/widgets/memberdetails.dart';
import 'package:lzcas/dialogs/edit_member_dialog.dart';
import '/dialogs/confirmation_dialog.dart';

class MembersPage extends StatefulWidget {
  const MembersPage({super.key});

  @override
  State<MembersPage> createState() => _MembersPageState();
}

class _MembersPageState extends State<MembersPage>
    with SingleTickerProviderStateMixin {
  Map<String, dynamic>? selectedMember;
  final GlobalKey<MembersTableState> _tableKey = GlobalKey<MembersTableState>();
  late AnimationController _panelAnimationController;

  @override
  void initState() {
    super.initState();
    _panelAnimationController = AnimationController(
      duration: const Duration(milliseconds: 300),
      vsync: this,
    );
  }

  @override
  void dispose() {
    _panelAnimationController.dispose();
    super.dispose();
  }

  void _handleRowSelection(Map<String, dynamic> member, bool isDesktop) {
    setState(() {
      selectedMember = member;
    });

    if (isDesktop) {
      _panelAnimationController.forward();
    } else {
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
    showAnimatedDialog(
      context,
      builder: (context) => EditMemberDialog(
        member: member,
        onMemberUpdated: (updatedMember) =>
            _updateMember(member, updatedMember),
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

  void _updateMember(
    Map<String, dynamic> oldMember,
    Map<String, dynamic> updatedMember,
  ) {
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

    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text("Member deleted")));
  }

  void _closeMemberPanel() {
    _panelAnimationController.reverse().then((_) {
      setState(() {
        selectedMember = null;
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    final double screenWidth = MediaQuery.of(context).size.width;
    final bool isDesktop = screenWidth >= 850;
    final panelWidth = screenWidth < 1200 ? 400.0 : 450.0;

    return Scaffold(
      body: SafeArea(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              flex: 3,
              child: MembersTable(
                key: _tableKey,
                onRowSelected: (member) =>
                    _handleRowSelection(member, isDesktop),
              ),
            ),

            if (isDesktop)
              SlideTransition(
                position:
                    Tween<Offset>(
                      begin: const Offset(1, 0),
                      end: Offset.zero,
                    ).animate(
                      CurvedAnimation(
                        parent: _panelAnimationController,
                        curve: Curves.easeOutCubic,
                      ),
                    ),
                child: AnimatedBuilder(
                  animation: _panelAnimationController,
                  builder: (context, child) {
                    return Opacity(
                      opacity: _panelAnimationController.value,
                      child: child,
                    );
                  },
                  child: Container(
                    width: panelWidth,
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.surface,
                      border: Border(
                        left: BorderSide(
                          color: Theme.of(context).dividerColor,
                          width: 1,
                        ),
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.05),
                          blurRadius: 8,
                          offset: const Offset(-2, 0),
                        ),
                      ],
                    ),
                    child: selectedMember != null
                        ? Column(
                            children: [
                              Padding(
                                padding: const EdgeInsets.fromLTRB(
                                  20,
                                  16,
                                  12,
                                  12,
                                ),
                                child: Row(
                                  children: [
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            "Details",
                                            style: Theme.of(context)
                                                .textTheme
                                                .labelMedium
                                                ?.copyWith(
                                                  color: Theme.of(context)
                                                      .colorScheme
                                                      .onSurfaceVariant,
                                                  letterSpacing: 0.5,
                                                ),
                                          ),
                                          const SizedBox(height: 4),
                                          Text(
                                            [
                                                  selectedMember!['firstName'],
                                                  selectedMember!['lastName'],
                                                ]
                                                .where(
                                                  (part) =>
                                                      part != null &&
                                                      part
                                                          .toString()
                                                          .trim()
                                                          .isNotEmpty,
                                                )
                                                .join(' '),
                                            style: Theme.of(context)
                                                .textTheme
                                                .titleLarge
                                                ?.copyWith(
                                                  fontWeight: FontWeight.bold,
                                                ),
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        ],
                                      ),
                                    ),
                                    IconButton(
                                      tooltip: 'Edit member',
                                      onPressed: () =>
                                          _openEditDialog(selectedMember!),
                                      icon: const Icon(
                                        Icons.edit_outlined,
                                        color: Colors.blue,
                                      ),
                                    ),
                                    IconButton(
                                      tooltip: 'Delete member',
                                      onPressed: () =>
                                          _confirmDeleteMember(selectedMember!),
                                      icon: const Icon(
                                        Icons.delete_outline,
                                        color: Colors.red,
                                      ),
                                    ),
                                    IconButton(
                                      tooltip: 'Close panel',
                                      onPressed: _closeMemberPanel,
                                      icon: const Icon(Icons.close),
                                    ),
                                  ],
                                ),
                              ),
                              const Divider(height: 1),
                              Expanded(
                                child: SingleChildScrollView(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 16,
                                    vertical: 12,
                                  ),
                                  child: MemberDetailsCard(
                                    member: selectedMember!,
                                    showHeader: false,
                                    showCardStyling: false,
                                  ),
                                ),
                              ),
                            ],
                          )
                        : const SizedBox.shrink(),
                  ),
                ),
              ),
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
    final size = MediaQuery.of(context).size;
    final fullName =
        [member['firstName'], member['middleName'], member['lastName']]
            .where((part) => part != null && part.toString().trim().isNotEmpty)
            .join(' ');

    return Dialog(
      insetPadding: EdgeInsets.symmetric(
        horizontal: size.width < 480 ? 12 : 24,
        vertical: 24,
      ),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: 760,
          maxHeight: size.height * 0.9,
        ),
        child: Padding(
          padding: EdgeInsets.fromLTRB(
            size.width < 480 ? 12 : 18,
            16,
            size.width < 480 ? 12 : 18,
            18,
          ),
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
                      style: theme.textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
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
                  child: MemberDetailsCard(
                    member: member,
                    showHeader: false,
                    showCardStyling: false,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
