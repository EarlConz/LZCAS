// lib/widgets/admin_members_page.dart
// SHARED members page widget used by BOTH Admin and Cashier dashboards.
// Contains the EXACT same member detail dialog with all callbacks.
import 'package:flutter/material.dart';
import 'package:bot_toast/bot_toast.dart';
import 'package:lzcas/utils/animations.dart';
import 'package:lzcas/theme.dart';
import 'package:lzcas/utils/fonts.dart';
import 'package:lzcas/utils/toast_utils.dart';
import 'package:lzcas/widgets/memberstable.dart';
import 'package:lzcas/widgets/memberdetails.dart';
import 'package:lzcas/dialogs/edit_member_dialog.dart';
import 'package:lzcas/db/db.dart';
import 'package:flutter/services.dart';

/// Members page with full detail dialog, shared by Admin and Cashier.
class AdminMembersPage extends StatefulWidget {
  const AdminMembersPage({super.key});

  @override
  State<AdminMembersPage> createState() => AdminMembersPageState();
}

class AdminMembersPageState extends State<AdminMembersPage> {
  final _tableKey = GlobalKey<MembersTableState>();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: MembersTable(
        key: _tableKey,
        onRowSelected: (member) => _showMemberDetail(context, member),
      ),
    );
  }

  void _showMemberDetail(
    BuildContext context,
    Map<String, dynamic> member,
  ) async {
    String packageName = '';
    try {
      final pkgIdRaw = member['packageId'];
      final pkgId = pkgIdRaw is int ? pkgIdRaw : int.tryParse('$pkgIdRaw');
      if (pkgId != null) {
        final packages = await repository.fetchPackages();
        final pkg = packages.where((p) => p.id == pkgId).firstOrNull;
        if (pkg != null) packageName = pkg.name;
      }
    } catch (_) {}
    if (!mounted) return;

    final fullName = [
      member['firstName'],
      member['middleName'],
      member['lastName'],
    ].where((p) => p != null && p.toString().trim().isNotEmpty).join(' ');
    final initials = fullName.isNotEmpty ? fullName[0].toUpperCase() : 'M';
    final isReseller =
        (member['role']?.toString() ?? '') == 'Verified Reseller';
    final email = (member['email']?.toString() ?? '').trim();
    final hasAccount = email.isNotEmpty;

    showAnimatedDialog(
      context,
      builder: (ctx) {
        final theme = Theme.of(ctx);
        final isDark = theme.brightness == Brightness.dark;
        final surface = isDark
            ? StockpileColors.darkSurface
            : StockpileColors.surface;
        final textColor = isDark
            ? StockpileColors.darkTextPrimary
            : StockpileColors.darkText;
        final muted = isDark
            ? StockpileColors.darkTextMuted
            : StockpileColors.mutedText;
        final divider = isDark
            ? StockpileColors.darkDivider
            : StockpileColors.divider;

        return Dialog(
          backgroundColor: surface,
          surfaceTintColor: Colors.transparent,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(24),
          ),
          insetPadding: const EdgeInsets.symmetric(
            horizontal: 24,
            vertical: 24,
          ),
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxWidth: 600,
              maxHeight: MediaQuery.of(context).size.height * 0.88,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Align(
                  alignment: Alignment.topRight,
                  child: Padding(
                    padding: const EdgeInsets.only(right: 8, top: 8),
                    child: IconButton(
                      tooltip: 'Close',
                      onPressed: () => Navigator.pop(ctx),
                      icon: const Icon(Icons.close),
                      visualDensity: VisualDensity.compact,
                    ),
                  ),
                ),
                Flexible(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
                    child: Column(
                      children: [
                        _AvatarHeader(
                          initials: initials,
                          fullName: fullName.isEmpty
                              ? 'Unnamed Member'
                              : fullName,
                          memberId: member['id']?.toString() ?? '—',
                          isReseller: isReseller,
                          email: email,
                          hasAccount: hasAccount,
                          packageName: packageName,
                          isDark: isDark,
                          textColor: textColor,
                          muted: muted,
                        ),
                        const SizedBox(height: 20),
                        _InfoCard(
                          isDark: isDark,
                          textColor: textColor,
                          muted: muted,
                          surface: surface,
                          divider: divider,
                          title: 'Personal Info',
                          icon: Icons.person_outline_rounded,
                          children: [
                            _InfoRow(
                              icon: Icons.cake_outlined,
                              label: 'Birthday',
                              value: member['birthday'],
                              muted: muted,
                              textColor: textColor,
                              isDark: isDark,
                            ),
                            _InfoRow(
                              icon: Icons.home_outlined,
                              label: 'Address',
                              value: member['address'],
                              muted: muted,
                              textColor: textColor,
                              isDark: isDark,
                            ),
                            _InfoRow(
                              icon: Icons.phone_outlined,
                              label: 'Contact',
                              value: member['contactNo'],
                              muted: muted,
                              textColor: textColor,
                              isDark: isDark,
                              isLast: true,
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        _ReferralCard(
                          member: member,
                          isDark: isDark,
                          textColor: textColor,
                          muted: muted,
                          surface: surface,
                          divider: divider,
                        ),
                        const SizedBox(height: 12),
                        if ((member['idImagePath']?.toString() ?? '')
                            .isNotEmpty)
                          _InfoCard(
                            isDark: isDark,
                            textColor: textColor,
                            muted: muted,
                            surface: surface,
                            divider: divider,
                            title: 'ID Verification',
                            icon: Icons.verified_user,
                            children: [
                              _InfoRow(
                                icon: Icons.credit_card_outlined,
                                label: 'ID Type',
                                value: member['idType'],
                                muted: muted,
                                textColor: textColor,
                                isDark: isDark,
                              ),
                              if ((member['idNumber']?.toString() ?? '')
                                  .isNotEmpty)
                                _InfoRow(
                                  icon: Icons.numbers_outlined,
                                  label: 'ID Number',
                                  value: member['idNumber'],
                                  muted: muted,
                                  textColor: textColor,
                                  isDark: isDark,
                                ),
                              GestureDetector(
                                onTap: () {
                                  final path = member['idImagePath']
                                      ?.toString();
                                  if (path != null && path.isNotEmpty)
                                    _showIdImage(ctx, path);
                                },
                                child: ClipRRect(
                                  borderRadius: BorderRadius.circular(10),
                                  child: buildIdImage(
                                    ctx,
                                    member['idImagePath'].toString(),
                                    height: 140,
                                    width: double.infinity,
                                    fit: BoxFit.contain,
                                  ),
                                ),
                              ),
                              const SizedBox(height: 4),
                            ],
                          ),
                        const SizedBox(height: 20),
                        if (!hasAccount)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 12),
                            child: SizedBox(
                              width: double.infinity,
                              child: OutlinedButton.icon(
                                onPressed: () =>
                                    _showCreateAccountDialog(ctx, member),
                                icon: const Icon(
                                  Icons.person_add_rounded,
                                  size: 18,
                                ),
                                label: const Text('Create Login Account'),
                                style: OutlinedButton.styleFrom(
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 14,
                                  ),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        if (hasAccount)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 12),
                            child: SizedBox(
                              width: double.infinity,
                              child: OutlinedButton.icon(
                                onPressed: () =>
                                    _viewMemberPassword(ctx, member, fullName),
                                icon: const Icon(
                                  Icons.vpn_key_rounded,
                                  size: 18,
                                  color: Colors.amber,
                                ),
                                label: const Text('View Password'),
                                style: OutlinedButton.styleFrom(
                                  foregroundColor: Colors.amber.shade800,
                                  side: BorderSide(
                                    color: Colors.amber.shade300,
                                  ),
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 14,
                                  ),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        Row(
                          children: [
                            Expanded(
                              child: OutlinedButton.icon(
                                onPressed: () =>
                                    _showTransactionHistory(ctx, member),
                                icon: const Icon(
                                  Icons.receipt_long_outlined,
                                  size: 18,
                                ),
                                label: const Text('View History'),
                                style: OutlinedButton.styleFrom(
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 14,
                                  ),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: FilledButton.icon(
                                onPressed: () {
                                  Navigator.pop(ctx);
                                  _openEditDialog(member);
                                },
                                icon: const Icon(Icons.edit_outlined, size: 18),
                                label: const Text('Edit Member'),
                                style: FilledButton.styleFrom(
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 14,
                                  ),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                        Padding(
                          padding: const EdgeInsets.only(top: 12),
                          child: SizedBox(
                            width: double.infinity,
                            child: FilledButton.icon(
                              onPressed: () =>
                                  _showUpgradePackageDialog(ctx, member),
                              icon: const Icon(Icons.upgrade, size: 18),
                              label: const Text('Upgrade Package'),
                              style: FilledButton.styleFrom(
                                backgroundColor: StockpileColors.primary900,
                                padding: const EdgeInsets.symmetric(
                                  vertical: 14,
                                ),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 12),
                        SizedBox(
                          width: double.infinity,
                          child: TextButton.icon(
                            onPressed: () =>
                                _confirmDeleteMemberDialog(ctx, member),
                            icon: const Icon(Icons.delete_outline, size: 18),
                            label: const Text('Delete Member'),
                            style: TextButton.styleFrom(
                              foregroundColor: StockpileColors.danger,
                              padding: const EdgeInsets.symmetric(vertical: 14),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  // ── Helper dialogs ─────────────────────────────────────────────────

  void _showTransactionHistory(BuildContext ctx, Map<String, dynamic> member) {
    final fullName = [
      member['firstName'],
      member['lastName'],
    ].where((p) => p != null && p.toString().trim().isNotEmpty).join(' ');
    final memberId = (member['id'] ?? 0) as int;
    showDialog(
      context: ctx,
      builder: (c) => AlertDialog(
        title: Text(fullName.isEmpty ? 'Member History' : fullName),
        content: SizedBox(
          width: 500,
          height: 400,
          child: FutureBuilder<List<Sale>>(
            future: repository.fetchSalesForMember(memberId),
            builder: (_, snap) {
              if (snap.connectionState == ConnectionState.waiting)
                return const Center(child: CircularProgressIndicator());
              final sales = snap.data ?? [];
              if (sales.isEmpty)
                return const Center(child: Text('No transactions'));
              return ListView.builder(
                itemCount: sales.length,
                itemBuilder: (_, i) {
                  final s = sales[i];
                  return ListTile(
                    title: Text(s.itemName),
                    subtitle: Text('Qty: ${s.quantity} · ₱${s.price}'),
                    trailing: Text(
                      s.timestamp != null
                          ? '${s.timestamp!.month}/${s.timestamp!.day}'
                          : '',
                    ),
                  );
                },
              );
            },
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  void _viewMemberPassword(
    BuildContext ctx,
    Map<String, dynamic> member,
    String fullName,
  ) {
    final email = (member['email']?.toString() ?? '').trim();
    if (email.isEmpty) {
      BotToast.showText(text: 'No login account.');
      return;
    }
    showDialog(
      context: ctx,
      builder: (c) => FutureBuilder<String?>(
        future: repository.fetchMemberPassword(member['id'] as int? ?? 0),
        builder: (_, snap) {
          final pwd = snap.data ?? 'N/A';
          return AlertDialog(
            title: Text('Password for $fullName'),
            content: Text(
              pwd,
              style: const TextStyle(fontSize: 18, fontFamily: 'monospace'),
            ),
            actions: [
              FilledButton(
                onPressed: () => Navigator.pop(c),
                child: const Text('Close'),
              ),
            ],
          );
        },
      ),
    );
  }

  void _showCreateAccountDialog(BuildContext ctx, Map<String, dynamic> member) {
    final memberId = (member['id'] ?? 0) as int;
    final nameCtrl = TextEditingController();
    final passCtrl = TextEditingController();
    showDialog(
      context: ctx,
      builder: (c) => AlertDialog(
        title: const Text('Create Login Account'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: nameCtrl,
              decoration: const InputDecoration(
                labelText: 'Username',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: passCtrl,
              obscureText: true,
              decoration: const InputDecoration(
                labelText: 'Password',
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () async {
              final result = await repository.createMemberAuthAccount(
                memberId: memberId,
                username: nameCtrl.text.trim(),
                password: passCtrl.text,
              );
              if (!c.mounted) return;
              Navigator.pop(c);
              BotToast.showText(
                text: result?['error'] != null
                    ? result!['error'].toString()
                    : 'Account created!',
              );
            },
            child: const Text('Create'),
          ),
        ],
      ),
    );
  }

  void _confirmDeleteMemberDialog(
    BuildContext ctx,
    Map<String, dynamic> member,
  ) {
    showDialog<bool>(
      context: ctx,
      builder: (c) => AlertDialog(
        title: const Text('Delete Member'),
        content: Text(
          'Delete ${member['firstName'] ?? 'this member'} permanently?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () {
              Navigator.pop(c, true);
              _deleteMember(member);
              Navigator.pop(ctx);
            },
            child: const Text('Delete'),
          ),
        ],
      ),
    );
  }

  void _deleteMember(Map<String, dynamic> member) {
    _tableKey.currentState?.removeMember(member);
    showSuccessToast('Member deleted.');
  }

  void _openEditDialog(Map<String, dynamic> member) {
    showAnimatedDialog(
      context,
      builder: (_) => EditMemberDialog(
        member: member,
        onMemberUpdated: (updated) {
          _tableKey.currentState?.updateMember(member, updated);
        },
      ),
    );
  }

  void _showIdImage(BuildContext ctx, String path) {
    showDialog(
      context: ctx,
      builder: (c) => Dialog(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: buildIdImage(c, path, fit: BoxFit.contain),
            ),
            TextButton(
              onPressed: () => Navigator.pop(c),
              child: const Text('Close'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _showUpgradePackageDialog(
    BuildContext ctx,
    Map<String, dynamic> member,
  ) async {
    final memberId = member['id'] as int?;
    if (memberId == null) return;
    final rawPkgId = member['packageId'];
    final currentPkgId = rawPkgId is int ? rawPkgId : int.tryParse('$rawPkgId');
    int currentRank = 0;
    if (currentPkgId != null) {
      final currentPkg = await repository.getPackageById(currentPkgId);
      currentRank = currentPkg?.hierarchyRank ?? 0;
    }
    final selected = await showModalBottomSheet<Package>(
      context: ctx, isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (c) => _PkgUpgradeSheet(currentRank: currentRank, currentPkgId: currentPkgId,
          memberName: member['firstName']?.toString() ?? 'Member'),
    );
    if (selected == null || !mounted) return;
    try {
      await repository.submitUpgrade(memberId: memberId, targetPackageId: selected.id!);
      await repository.processPackageUpgrade(memberId: memberId, upgradedPackageId: selected.id!);
      await repository.addSale(itemId: 0, itemName: 'Package Upgrade: ${selected.name}',
          quantity: 1, price: selected.price, buyerId: memberId,
          buyerName: member['firstName']?.toString(), packageId: selected.id, timestamp: DateTime.now());
      BotToast.showText(text: '${member['firstName'] ?? 'Member'} upgraded to ${selected.name}');
    } catch (e) {
      final msg = e.toString();
      BotToast.showText(text: msg.contains('Invalid upgrade') || msg.contains('downgrade')
          ? 'Cannot downgrade or side-grade packages.' : 'Failed: $e');
    }
  }
}

// ── Package Upgrade Bottom Sheet ──────────────────────────────────────────

class _PkgUpgradeSheet extends StatelessWidget {
  final int currentRank; final int? currentPkgId; final String memberName;
  const _PkgUpgradeSheet({required this.currentRank, required this.currentPkgId, required this.memberName});
  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return DraggableScrollableSheet(initialChildSize: 0.5, minChildSize: 0.3, maxChildSize: 0.8, expand: false,
      builder: (_, scrollCtrl) => Padding(padding: const EdgeInsets.all(24), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Center(child: Container(width: 40, height: 4, decoration: BoxDecoration(color: Colors.grey.shade400, borderRadius: BorderRadius.circular(2)))),
        const SizedBox(height: 20),
        Text('Upgrade Package', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: isDark ? Colors.white : const Color(0xFF1E293B))),
        const SizedBox(height: 4),
        Text('Available upgrades for $memberName', style: TextStyle(fontSize: 13, color: isDark ? Colors.white54 : const Color(0xFF64748B))),
        const SizedBox(height: 20),
        Expanded(child: FutureBuilder<List<Package>>(future: repository.fetchAvailableUpgrades(currentRank), builder: (_, snap) {
          if (snap.connectionState == ConnectionState.waiting) return const Center(child: CircularProgressIndicator());
          final upgrades = snap.data ?? [];
          if (upgrades.isEmpty) return Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
            Icon(Icons.verified, size: 56, color: const Color(0xFF0037FD).withAlpha(100)),
            const SizedBox(height: 16),
            Text('You are currently on the highest tier!', textAlign: TextAlign.center,
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: isDark ? Colors.white70 : const Color(0xFF334155))),
          ]));
          return ListView.builder(controller: scrollCtrl, itemCount: upgrades.length, itemBuilder: (_, i) {
            final pkg = upgrades[i];
            return Card(elevation: 0, margin: const EdgeInsets.only(bottom: 12),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16),
                  side: BorderSide(color: isDark ? Colors.white12 : Colors.grey.shade200)),
              child: Padding(padding: const EdgeInsets.all(20), child: Row(children: [
                Container(width: 48, height: 48, decoration: BoxDecoration(color: const Color(0xFF0037FD).withAlpha(25), borderRadius: BorderRadius.circular(14)),
                    child: Center(child: Text(pkg.name.isNotEmpty ? pkg.name[0].toUpperCase() : '?',
                        style: const TextStyle(color: Color(0xFF0037FD), fontSize: 20, fontWeight: FontWeight.w700)))),
                const SizedBox(width: 16),
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(pkg.name, style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: isDark ? Colors.white : const Color(0xFF1E293B))),
                  const SizedBox(height: 4),
                  Text('₱${pkg.price}', style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: Color(0xFF0037FD))),
                ])),
                _PkgUpgradeBtn(package: pkg),
              ])));
          });
        })),
      ])));
  }
}

class _PkgUpgradeBtn extends StatefulWidget {
  final Package package;
  const _PkgUpgradeBtn({required this.package});
  @override
  State<_PkgUpgradeBtn> createState() => _PkgUpgradeBtnState();
}
class _PkgUpgradeBtnState extends State<_PkgUpgradeBtn> {
  bool _loading = false;
  @override
  Widget build(BuildContext c) => FilledButton(
    onPressed: _loading ? null : () { setState(() => _loading = true); Navigator.pop(c, widget.package); },
    style: FilledButton.styleFrom(backgroundColor: const Color(0xFF0037FD), padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
    child: _loading ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
        : const Text('Upgrade', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
  );
}

// ── Private modal widgets ──────────────────────────────────────────────

class _AvatarHeader extends StatelessWidget {
  final String initials, fullName, memberId, email, packageName;
  final bool isReseller, hasAccount, isDark;
  final Color textColor, muted;
  const _AvatarHeader({
    required this.initials,
    required this.fullName,
    required this.memberId,
    required this.isReseller,
    required this.email,
    required this.hasAccount,
    required this.packageName,
    required this.isDark,
    required this.textColor,
    required this.muted,
  });
  @override
  Widget build(BuildContext c) => Column(
    children: [
      const SizedBox(height: 4),
      CircleAvatar(
        radius: 36,
        backgroundColor: StockpileColors.primary900,
        child: Text(
          initials,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 24,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
      const SizedBox(height: 14),
      Text(
        fullName,
        style: StockpileFonts.satoshi(
          fontSize: 20,
          fontWeight: FontWeight.w800,
          color: textColor,
        ),
      ),
      const SizedBox(height: 4),
      Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            'ID #$memberId',
            style: StockpileFonts.satoshi(fontSize: 13, color: muted),
          ),
          if (isReseller) ...[
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: StockpileColors.success.withAlpha(25),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                'Verified Reseller',
                style: StockpileFonts.satoshi(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: StockpileColors.success,
                ),
              ),
            ),
          ],
        ],
      ),
      if (email.isNotEmpty || packageName.isNotEmpty) ...[
        const SizedBox(height: 8),
        if (email.isNotEmpty)
          Text(
            email,
            style: StockpileFonts.satoshi(fontSize: 12, color: muted),
          ),
        if (packageName.isNotEmpty && hasAccount)
          Text(
            packageName,
            style: StockpileFonts.satoshi(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: StockpileColors.primary900,
            ),
          ),
      ],
    ],
  );
}

class _InfoCard extends StatelessWidget {
  final bool isDark;
  final Color textColor, muted, surface, divider;
  final String title;
  final IconData icon;
  final List<Widget> children;
  const _InfoCard({
    required this.isDark,
    required this.textColor,
    required this.muted,
    required this.surface,
    required this.divider,
    required this.title,
    required this.icon,
    required this.children,
  });
  @override
  Widget build(BuildContext c) => Container(
    width: double.infinity,
    padding: const EdgeInsets.all(18),
    decoration: BoxDecoration(
      color: surface,
      borderRadius: BorderRadius.circular(16),
      border: Border.all(color: divider),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(icon, size: 18, color: textColor),
            const SizedBox(width: 8),
            Text(
              title,
              style: StockpileFonts.satoshi(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: textColor,
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        ...children,
      ],
    ),
  );
}

class _InfoRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final dynamic value;
  final Color muted, textColor;
  final bool isDark, isLast;
  const _InfoRow({
    required this.icon,
    required this.label,
    this.value,
    required this.muted,
    required this.textColor,
    required this.isDark,
    this.isLast = false,
  });
  @override
  Widget build(BuildContext c) {
    final display = value?.toString();
    return Padding(
      padding: EdgeInsets.only(bottom: isLast ? 0 : 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 15, color: muted),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              display != null && display.isNotEmpty ? display : '—',
              style: StockpileFonts.satoshi(fontSize: 13, color: textColor),
            ),
          ),
        ],
      ),
    );
  }
}

class _ReferralCard extends StatefulWidget {
  final Map<String, dynamic> member;
  final bool isDark;
  final Color textColor, muted, surface, divider;
  const _ReferralCard({
    required this.member,
    required this.isDark,
    required this.textColor,
    required this.muted,
    required this.surface,
    required this.divider,
  });
  @override
  State<_ReferralCard> createState() => _ReferralCardState();
}

class _ReferralCardState extends State<_ReferralCard> {
  String _referrerName = '';
  List<Member> _directReferrals = [];
  List<Member> _indirectReferrals = [];
  int _referralCount = 0;
  bool _loading = true;
  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final memberId = widget.member['id'] as int?;
    if (memberId == null) {
      if (mounted) setState(() => _loading = false);
      return;
    }
    final memberName =
        '${widget.member['firstName'] ?? ''} ${widget.member['lastName'] ?? ''}'
            .trim()
            .toLowerCase();
    final all = await repository.fetchMembers();
    if (!mounted) return;
    String referrerName = '';
    final referrerIdRaw = widget.member['referrerId'] as int?;
    if (referrerIdRaw != null) {
      final ref = all.where((m) => m.id == referrerIdRaw).firstOrNull;
      if (ref != null)
        referrerName = [
          ref.firstName,
          ref.lastName,
        ].where((p) => p != null && p.isNotEmpty).join(' ');
    }
    if (referrerName.isEmpty)
      referrerName = (widget.member['referrer']?.toString() ?? '').trim();
    final direct = all.where((m) {
      if (m.referrerId == memberId) return true;
      if (memberName.isNotEmpty) {
        final ref = (m.referrer ?? '').trim().toLowerCase();
        if (ref.isNotEmpty && ref == memberName) return true;
      }
      return false;
    }).toList();
    final directIds = direct.map((d) => d.id).whereType<int>().toSet();
    final indirect = all
        .where((m) => m.referrerId != null && directIds.contains(m.referrerId))
        .toList();
    if (mounted)
      setState(() {
        _referrerName = referrerName;
        _directReferrals = direct;
        _indirectReferrals = indirect;
        _referralCount = direct.length + indirect.length;
        _loading = false;
      });
  }

  @override
  Widget build(BuildContext c) {
    final w = widget;
    return _InfoCard(
      isDark: w.isDark,
      textColor: w.textColor,
      muted: w.muted,
      surface: w.surface,
      divider: w.divider,
      title: 'Referral',
      icon: Icons.group_outlined,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: _InfoRow(
                icon: Icons.person_add_outlined,
                label: 'Referred by',
                value: _loading
                    ? '...'
                    : (_referrerName.isEmpty ? 'None' : _referrerName),
                muted: w.muted,
                textColor: w.textColor,
                isDark: w.isDark,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _ReferralDropdown(
                label: 'Direct Referral',
                members: _directReferrals,
                emptyText: 'No direct referrals',
                isLoading: _loading,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: _InfoRow(
                icon: Icons.people_outline,
                label: 'Referral Count',
                value: _loading ? '...' : '$_referralCount',
                muted: w.muted,
                textColor: w.textColor,
                isDark: w.isDark,
                isLast: true,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _ReferralDropdown(
                label: 'Indirect Referral',
                members: _indirectReferrals,
                emptyText: 'No indirect referrals',
                isLoading: _loading,
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
      ],
    );
  }
}

class _ReferralDropdown extends StatelessWidget {
  final String label, emptyText;
  final List<Member> members;
  final bool isLoading;
  const _ReferralDropdown({
    required this.label,
    required this.members,
    required this.emptyText,
    this.isLoading = false,
  });
  @override
  Widget build(BuildContext c) {
    final hasItems = members.isNotEmpty;
    return InkWell(
      onTap: hasItems ? () => _showDropdown(c) : null,
      borderRadius: BorderRadius.circular(10),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: Colors.grey.shade300),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.arrow_forward_rounded,
              size: 16,
              color: hasItems ? StockpileColors.primary900 : Colors.grey,
            ),
            const SizedBox(width: 6),
            Flexible(
              child: Text(
                isLoading
                    ? '...'
                    : (hasItems ? '${members.length}' : emptyText),
                style: TextStyle(
                  fontSize: 13,
                  color: hasItems ? StockpileColors.primary900 : Colors.grey,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            if (hasItems)
              const Icon(
                Icons.arrow_drop_down,
                size: 18,
                color: StockpileColors.primary900,
              ),
          ],
        ),
      ),
    );
  }

  void _showDropdown(BuildContext c) {
    showDialog(
      context: c,
      builder: (ctx) => AlertDialog(
        title: Text(label),
        content: SizedBox(
          width: 300,
          child: ListView.builder(
            shrinkWrap: true,
            itemCount: members.length,
            itemBuilder: (_, i) {
              final m = members[i];
              final name = [
                m.firstName,
                m.lastName,
              ].where((p) => p != null && p.isNotEmpty).join(' ');
              return ListTile(
                title: Text(name.isNotEmpty ? name : 'Member #${m.id}'),
                subtitle: Text(m.role ?? 'Member'),
              );
            },
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }
}
