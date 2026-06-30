import 'package:flutter/material.dart';
import 'package:bot_toast/bot_toast.dart';
import 'package:lzcas/utils/animations.dart';
import '../widgets/memberstable.dart';
import '../widgets/memberdetails.dart';
import '../dialogs/edit_member_dialog.dart';
import '../dialogs/confirmation_dialog.dart';
import '../theme.dart';
import '../utils/fonts.dart';

class SuppliersPage extends StatefulWidget {
  const SuppliersPage({super.key});

  @override
  State<SuppliersPage> createState() => _SuppliersPageState();
}

class _SuppliersPageState extends State<SuppliersPage>
    with SingleTickerProviderStateMixin {
  Map<String, dynamic>? _selectedMember;
  final _tableKey = GlobalKey<MembersTableState>();
  late final AnimationController _panelController;
  bool _panelVisible = false;

  @override
  void initState() {
    super.initState();
    _panelController = AnimationController(
      duration: const Duration(milliseconds: 300),
      vsync: this,
    );
  }

  @override
  void dispose() {
    _panelController.dispose();
    super.dispose();
  }

  void _onMemberSelected(Map<String, dynamic> member) {
    final isDesktop = MediaQuery.sizeOf(context).width >= 850;

    setState(() => _selectedMember = member);

    if (isDesktop) {
      if (!_panelVisible) {
        _panelVisible = true;
        _panelController.forward();
      }
    } else {
      _showMemberDialog(member);
    }
  }

  void _showMemberDialog(Map<String, dynamic> member) {
    final fullName = [
      member['firstName'],
      member['middleName'],
      member['lastName'],
    ].where((p) => p != null && p.toString().trim().isNotEmpty).join(' ');

    showAnimatedDialog(
      context,
      builder: (ctx) => Dialog(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(28),
          side: BorderSide(color: StockpileColors.primary900, width: 4),
        ),
        insetPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 24),
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: 760,
            maxHeight: MediaQuery.sizeOf(context).height * 0.85,
          ),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 18),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Header row
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        fullName.isEmpty ? 'Member Details' : fullName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: StockpileFonts.satoshi(
                          fontSize: 18,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    IconButton(
                      tooltip: 'Edit',
                      icon: const Icon(Icons.edit_outlined, color: Colors.blue),
                      onPressed: () {
                        Navigator.pop(ctx);
                        _openEditDialog(member);
                      },
                    ),
                    IconButton(
                      tooltip: 'Delete',
                      icon: const Icon(Icons.delete_outline, color: Colors.red),
                      onPressed: () {
                        Navigator.pop(ctx);
                        _confirmDelete(member);
                      },
                    ),
                    IconButton(
                      tooltip: 'Close',
                      icon: const Icon(Icons.close),
                      onPressed: () => Navigator.pop(ctx),
                    ),
                  ],
                ),
                const Divider(),
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
      ),
    );
  }

  void _openEditDialog(Map<String, dynamic> member) {
    showAnimatedDialog(
      context,
      builder: (_) => EditMemberDialog(
        member: member,
        onMemberUpdated: (updated) {
          _tableKey.currentState?.updateMember(member, updated);
          setState(() {
            _selectedMember = {...member, ...updated};
          });
          BotToast.showText(text: 'Member updated successfully!');
        },
      ),
    );
  }

  void _confirmDelete(Map<String, dynamic> member) {
    showDialog<bool>(
      context: context,
      builder: (_) => ConfirmationDialog(
        title: 'Confirm Delete',
        content: 'Delete ${member['firstName'] ?? 'this member'}?',
        onConfirm: () {
          _tableKey.currentState?.removeMember(member);
          if (_selectedMember?['id'] == member['id']) {
            setState(() => _selectedMember = null);
          }
          BotToast.showText(text: 'Member deleted');
        },
      ),
    );
  }

  void _closePanel() {
    _panelController.reverse().then((_) {
      if (mounted) {
        setState(() {
          _panelVisible = false;
          _selectedMember = null;
        });
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final isDesktop = MediaQuery.sizeOf(context).width >= 850;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final panelWidth = MediaQuery.sizeOf(context).width < 1200 ? 400.0 : 450.0;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Main table
        Expanded(
          child: MembersTable(key: _tableKey, onRowSelected: _onMemberSelected),
        ),

        // Slide-out detail panel (desktop only)
        if (isDesktop && _panelVisible)
          SlideTransition(
            position: Tween<Offset>(begin: const Offset(1, 0), end: Offset.zero)
                .animate(
                  CurvedAnimation(
                    parent: _panelController,
                    curve: Curves.easeOutCubic,
                  ),
                ),
            child: FadeTransition(
              opacity: _panelController,
              child: Container(
                width: panelWidth,
                decoration: BoxDecoration(
                  color: isDark
                      ? StockpileColors.darkSurface
                      : StockpileColors.surface,
                  border: Border(
                    left: BorderSide(
                      color: isDark
                          ? StockpileColors.darkDivider
                          : StockpileColors.divider,
                      width: 1,
                    ),
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withAlpha((0.06 * 255).round()),
                      blurRadius: 8,
                      offset: const Offset(-2, 0),
                    ),
                  ],
                ),
                child: _selectedMember != null
                    ? Column(
                        children: [
                          // Panel header
                          Padding(
                            padding: const EdgeInsets.fromLTRB(20, 16, 12, 12),
                            child: Row(
                              children: [
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        'Details',
                                        style: StockpileFonts.satoshi(
                                          fontSize: 12,
                                          fontWeight: FontWeight.w600,
                                          color: isDark
                                              ? StockpileColors.darkTextMuted
                                              : StockpileColors.mutedText,
                                          letterSpacing: 0.5,
                                        ),
                                      ),
                                      const SizedBox(height: 4),
                                      Text(
                                        [
                                              _selectedMember!['firstName'],
                                              _selectedMember!['lastName'],
                                            ]
                                            .where(
                                              (p) =>
                                                  p != null &&
                                                  p
                                                      .toString()
                                                      .trim()
                                                      .isNotEmpty,
                                            )
                                            .join(' '),
                                        style: StockpileFonts.satoshi(
                                          fontSize: 18,
                                          fontWeight: FontWeight.w700,
                                          color: isDark
                                              ? StockpileColors.darkTextPrimary
                                              : StockpileColors.darkText,
                                        ),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ],
                                  ),
                                ),
                                IconButton(
                                  tooltip: 'Edit',
                                  onPressed: () =>
                                      _openEditDialog(_selectedMember!),
                                  icon: const Icon(
                                    Icons.edit_outlined,
                                    color: Colors.blue,
                                  ),
                                ),
                                IconButton(
                                  tooltip: 'Delete',
                                  onPressed: () =>
                                      _confirmDelete(_selectedMember!),
                                  icon: const Icon(
                                    Icons.delete_outline,
                                    color: Colors.red,
                                  ),
                                ),
                                IconButton(
                                  tooltip: 'Close',
                                  onPressed: _closePanel,
                                  icon: Icon(
                                    Icons.close,
                                    color: isDark
                                        ? StockpileColors.darkTextMuted
                                        : StockpileColors.mutedText,
                                  ),
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
                                member: _selectedMember!,
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
    );
  }
}
