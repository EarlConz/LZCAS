// ignore_for_file: unnecessary_underscores
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:bot_toast/bot_toast.dart';
import 'package:lzcas/utils/animations.dart';
import 'package:lzcas/utils/toast_utils.dart';
import 'package:lzcas/utils/action_guard.dart';
import 'package:lzcas/theme.dart';
import 'package:lzcas/utils/fonts.dart';

import 'interactive_member_avatar.dart';
import '../utils/formatters.dart';
import 'package:lzcas/db/db.dart';
import 'package:lzcas/auth/auth_state.dart';
import 'package:lzcas/auth/role_visibility.dart';

class MemberDetailsCard extends StatefulWidget {
  final Map<String, dynamic> member;
  final bool showHeader;
  final bool showCardStyling;

  const MemberDetailsCard({
    super.key,
    required this.member,
    this.showHeader = true,
    this.showCardStyling = true,
  });

  @override
  State<MemberDetailsCard> createState() => _MemberDetailsCardState();
}

class _MemberDetailsCardState extends State<MemberDetailsCard> {
  late Map<String, dynamic> member;
  int _referralCount = 0;
  List<Member> _directReferrals = [];
  List<Member> _indirectReferrals = [];
  String _referrerName = '';
  bool _referralsLoading = true;
  List<Sale> _availedPackages = [];
  bool _packagesLoading = true;
  String _currentPackageName = '';
  late final StreamSubscription<String> _sub;

  @override
  void initState() {
    super.initState();
    member = widget.member;
    _computeReferralCount();
    _loadAvailedPackages();
    _sub = repository.changes.listen((e) {
      if (e == 'sale_added' ||
          e == 'sale_imported' ||
          e == 'sale_updated' ||
          e == 'sale_deleted' ||
          e == 'member_transactions_committed' ||
          e == 'member_updated' ||
          e == 'member_verified' ||
          e == 'member_added' ||
          e == 'member_imported' ||
          e == 'member_deleted' ||
          e == 'db_cleared') {
        if (mounted) {
          setState(() {});
          _computeReferralCount();
          _loadAvailedPackages();
        }
      }
    });
  }

  /// Resolves the current package name client-side (no PostgREST join):
  ///   1) member.packageId → lookup in catalog
  ///   2) Most-recent availed package from sales history
  Future<void> _loadAvailedPackages() async {
    final memberId = member['id'] as int?;
    if (memberId == null) {
      if (mounted) setState(() => _packagesLoading = false);
      return;
    }
    try {
      final results = await Future.wait([
        repository.fetchSalesForMember(memberId),
        repository.fetchPackages(),
      ]);
      if (!mounted) return;
      final sales = results[0] as List<Sale>;
      final packages = results[1] as List<Package>;
      final pkgById = {
        for (final p in packages)
          if (p.id != null) p.id!: p,
      };

      final availed =
          sales.where((s) => s.isPackage).map((s) {
            final current = pkgById[s.packageId];
            return current == null
                ? s
                : s.copyWith(itemName: current.name, price: current.price);
          }).toList()..sort(
            (a, b) => (b.timestamp ?? DateTime(0)).compareTo(
              a.timestamp ?? DateTime(0),
            ),
          );

      final rawPkgId = member['packageId'];
      final pkgId = rawPkgId is int ? rawPkgId : int.tryParse('$rawPkgId');

      debugPrint(
        '[MbrDetail] memberId=$memberId pkgId=$pkgId '
        'pkgIdType=${rawPkgId.runtimeType} '
        'catalogKeys=${pkgById.keys.toList()} '
        'availedCount=${availed.length}',
      );

      if (!mounted) return;
      setState(() {
        if (pkgId != null && pkgById.containsKey(pkgId)) {
          _currentPackageName = pkgById[pkgId]!.name;
          debugPrint('[MbrDetail] RESOLVED via catalog: $_currentPackageName');
        }
        if (_currentPackageName.isEmpty && availed.isNotEmpty) {
          _currentPackageName = availed.first.itemName;
          debugPrint('[MbrDetail] RESOLVED via availed: $_currentPackageName');
        }
        _availedPackages = availed;
        _packagesLoading = false;
        debugPrint(
          '[MbrDetail] FINAL _currentPackageName="$_currentPackageName"',
        );
      });
    } catch (e) {
      debugPrint('[MemberDetailsCard] _loadAvailedPackages error: $e');
      if (mounted) setState(() => _packagesLoading = false);
    }
  }

  Future<void> _computeReferralCount() async {
    final memberId = member['id'] as int?;
    if (memberId == null) {
      setState(() => _referralsLoading = false);
      return;
    }

    setState(() => _referralsLoading = true);

    final memberName =
        '${member['firstName'] ?? ''} ${member['lastName'] ?? ''}'
            .trim()
            .toLowerCase();

    final all = await repository.fetchMembers();
    if (!mounted) return;

    // ── Resolve the referrer's full name ───────────────
    String referrerName = '';
    final referrerIdRaw = member['referrerId'] as int?;
    if (referrerIdRaw != null) {
      final refMember = all.where((m) => m.id == referrerIdRaw).firstOrNull;
      if (refMember != null) {
        referrerName = [
          refMember.firstName,
          refMember.lastName,
        ].where((p) => p != null && p.isNotEmpty).join(' ');
      }
    }
    // Fallback to legacy text field
    if (referrerName.isEmpty) {
      referrerName = (member['referrer']?.toString() ?? '').trim();
    }

    // ── Direct referrals (members whose referrerId == this member's id) ──
    final direct = all.where((m) {
      if (m.referrerId == memberId) return true;
      // Fallback: match by referrer name string (legacy records)
      if (memberName.isNotEmpty) {
        final ref = (m.referrer ?? '').trim().toLowerCase();
        if (ref.isNotEmpty && ref == memberName) return true;
      }
      return false;
    }).toList();

    // ── Indirect referrals (members whose referrerId matches a direct referral's id) ──
    final directIds = direct.map((d) => d.id).whereType<int>().toSet();
    final indirect = all.where((m) {
      if (m.referrerId != null && directIds.contains(m.referrerId)) return true;
      return false;
    }).toList();

    setState(() {
      _referrerName = referrerName;
      _directReferrals = direct;
      _indirectReferrals = indirect;
      _referralCount = direct.length + indirect.length;
      _referralsLoading = false;
    });
  }

  @override
  void didUpdateWidget(covariant MemberDetailsCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.member['id'] != widget.member['id']) {
      member = widget.member;
      _computeReferralCount();
      _loadAvailedPackages();
    }
  }

  @override
  void dispose() {
    try {
      _sub.cancel();
    } catch (_) {}
    super.dispose();
  }

  void _showTransactionHistory() {
    final fullName =
        [member['firstName'], member['middleName'], member['lastName']]
            .where((part) => part != null && part.toString().trim().isNotEmpty)
            .join(' ');
    final memberId = (member['id'] ?? 0) as int;

    showDialog<void>(
      context: context,
      builder: (dialogContext) {
        final theme = Theme.of(dialogContext);
        final size = MediaQuery.of(dialogContext).size;

        return Dialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(28),
            side: BorderSide(color: StockpileColors.primary900, width: 4),
          ),
          insetPadding: EdgeInsets.symmetric(
            horizontal: size.width < 480 ? 12 : 24,
            vertical: 24,
          ),
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxWidth: 560,
              maxHeight: size.height * 0.85,
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
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              fullName.isEmpty ? 'Member History' : fullName,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.titleLarge?.copyWith(
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                            Text(
                              'Transaction history',
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: theme.colorScheme.onSurfaceVariant,
                              ),
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        tooltip: 'Close',
                        onPressed: () => Navigator.pop(dialogContext),
                        icon: const Icon(Icons.close),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  Flexible(
                    child: SingleChildScrollView(
                      child: _MemberTransactionHistory(memberId: memberId),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  void _showCreateAccountDialog() {
    final memberId = (member['id'] ?? 0) as int;
    final name = [
      member['firstName'],
      member['lastName'],
    ].where((p) => p != null && p.toString().trim().isNotEmpty).join(' ');
    final usernameCtrl = TextEditingController();
    final passwordCtrl = TextEditingController();
    final formKey = GlobalKey<FormState>();

    var obscured = true;
    showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: const Text('Create Login Account'),
          content: Form(
            key: formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('Create a login account for $name.'),
                const SizedBox(height: 12),
                TextFormField(
                  controller: usernameCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Username',
                    border: OutlineInputBorder(),
                  ),
                  validator: (v) =>
                      (v == null || v.trim().isEmpty) ? 'Required' : null,
                ),
                const SizedBox(height: 8),
                TextFormField(
                  controller: passwordCtrl,
                  decoration: InputDecoration(
                    labelText: 'Password',
                    border: const OutlineInputBorder(),
                    suffixIcon: IconButton(
                      icon: Icon(
                        obscured ? Icons.visibility_off : Icons.visibility,
                      ),
                      onPressed: () =>
                          setDialogState(() => obscured = !obscured),
                    ),
                  ),
                  obscureText: obscured,
                  validator: (v) =>
                      (v == null || v.trim().isEmpty) ? 'Required' : null,
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () async {
                if (!formKey.currentState!.validate()) return;
                final username = usernameCtrl.text.trim();
                final available = await repository.isUsernameAvailable(
                  username,
                );
                if (!available) {
                  showErrorToast('Username already exists');
                  return;
                }
                final result = await repository.createMemberAuthAccount(
                  memberId: memberId,
                  username: username,
                  password: passwordCtrl.text,
                );
                if (!mounted) return;
                if (result != null) {
                  final err = result['error']?.toString();
                  if (err != null) {
                    showErrorToast(err);
                  } else {
                    showSuccessToast(
                      'Account created!\nEmail: ${result['email']}\nPassword: ${result['password']}',
                    );
                    Navigator.pop(ctx); // close on success
                  }
                } else {
                  showErrorToast('Failed to create account.');
                }
              },
              child: const Text('Create'),
            ),
          ],
        ),
      ), // StatefulBuilder
    );
  }

  /// Show a package selection dialog and upgrade the member's package.
  /// Restricted to Admin and Cashier roles via [RoleVisibility] in the UI.
  Future<void> _showUpgradePackageDialog() async {
    final memberId = member['id'] as int?;
    if (memberId == null) return;

    // A package makes this member a Verified Reseller, and reseller records are
    // tied to a login account. Block availing one for an account-less member.
    final hasAccount = (member['email']?.toString() ?? '').trim().isNotEmpty;
    if (!hasAccount) {
      BotToast.showText(
        text:
            'This member needs a login account before availing a package. '
            'Create one from their details first.',
      );
      return;
    }

    final packages = await repository.fetchPackages();
    if (!mounted) return;

    // Filter out the member's current package (no-op upgrade)
    final rawPkgId = member['packageId'];
    final currentPkgId = rawPkgId is int ? rawPkgId : int.tryParse('$rawPkgId');
    final available = packages.where((p) => p.id != currentPkgId).toList();

    if (available.isEmpty) {
      BotToast.showText(text: 'No other packages available.');
      return;
    }

    final selected = await showDialog<Package>(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          title: const Text('Upgrade Package'),
          content: SizedBox(
            width: 360,
            child: ListView.builder(
              shrinkWrap: true,
              itemCount: available.length,
              itemBuilder: (_, i) {
                final pkg = available[i];
                return ListTile(
                  leading: CircleAvatar(
                    backgroundColor: StockpileColors.primary900,
                    child: Text(
                      pkg.name.isNotEmpty ? pkg.name[0].toUpperCase() : '?',
                      style: const TextStyle(color: Colors.white),
                    ),
                  ),
                  title: Text(pkg.name),
                  subtitle: Text('₱${pkg.price}'),
                  trailing: const Icon(Icons.arrow_forward_ios, size: 16),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                  onTap: () => Navigator.pop(ctx, pkg),
                );
              },
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel'),
            ),
          ],
        );
      },
    );

    if (selected == null || !mounted) return;

    // Guard against a double-click availing the package twice.
    await ActionGuard.run('avail_upgrade_$memberId', () async {
      try {
        // RPC handles: rank validation, member update, AND referrer bonus
        await repository.submitUpgrade(
          memberId: memberId,
          targetPackageId: selected.id!,
        );

      // ── POS: create a sale record for this upgrade ──
      await repository.addSale(
        itemId: 0,
        itemName: 'Package Upgrade: ${selected.name}',
        quantity: 1,
        price: selected.price,
        buyerId: memberId,
        buyerName: _memberDisplayName(),
        packageId: selected.id,
        timestamp: DateTime.now(),
      );

      showSuccessToast('${_memberDisplayName()} upgraded to ${selected.name}');

      // Refresh local state
      _loadAvailedPackages();
      if (mounted)
        setState(() {
          final selId = selected.id;
          if (selId != null) {
            member['packageId'] = selId;
            _currentPackageName = selected.name;
            // Holding a package = Verified Reseller (RPC promotes + syncs
            // the login role server-side; reflect it locally right away).
            member['role'] = 'Verified Reseller';
          }
        });
      } catch (e) {
        showErrorToast('Failed to upgrade package: $e');
      }
    });
  }

  String _memberDisplayName() {
    final name = [
      member['firstName'],
      member['lastName'],
    ].where((p) => p != null && p.toString().trim().isNotEmpty).join(' ');
    return name.isNotEmpty ? name : 'Member #${member['id']}';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final bool isCompact = MediaQuery.of(context).size.width < 480;

    if (!widget.showCardStyling) {
      // No card styling - used when part of a larger panel
      return LayoutBuilder(
        builder: (context, constraints) {
          return _MemberProfileSection(
            member: widget.member,
            referralCount: _referralCount,
            directReferrals: _directReferrals,
            indirectReferrals: _indirectReferrals,
            referrerName: _referrerName,
            referralsLoading: _referralsLoading,
            availedPackages: _availedPackages,
            packagesLoading: _packagesLoading,
            currentPackageName: _currentPackageName,
            onViewTransactions: _showTransactionHistory,
            showHeader: widget.showHeader,
            onCreateAccount: _showCreateAccountDialog,
            onUpgradePackage: _showUpgradePackageDialog,
          );
        },
      );
    }

    return Container(
      width: double.infinity,
      margin: EdgeInsets.zero,
      padding: EdgeInsets.all(isCompact ? 14 : 20),
      decoration: BoxDecoration(
        color: theme.cardColor,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: theme.dividerColor.withAlpha(80)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withAlpha(15),
            blurRadius: 20,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          return _MemberProfileSection(
            member: widget.member,
            referralCount: _referralCount,
            directReferrals: _directReferrals,
            indirectReferrals: _indirectReferrals,
            referrerName: _referrerName,
            referralsLoading: _referralsLoading,
            availedPackages: _availedPackages,
            packagesLoading: _packagesLoading,
            currentPackageName: _currentPackageName,
            onViewTransactions: _showTransactionHistory,
            showHeader: widget.showHeader,
            onCreateAccount: _showCreateAccountDialog,
            onUpgradePackage: _showUpgradePackageDialog,
          );
        },
      ),
    );
  }
}

class _MemberProfileSection extends StatelessWidget {
  const _MemberProfileSection({
    required this.member,
    required this.onViewTransactions,
    this.referralCount = 0,
    this.directReferrals = const [],
    this.indirectReferrals = const [],
    this.referrerName = '',
    this.referralsLoading = false,
    this.availedPackages = const [],
    this.packagesLoading = false,
    this.currentPackageName = '',
    this.showHeader = true,
    this.onCreateAccount,
    this.onUpgradePackage,
  });

  final Map<String, dynamic> member;
  final VoidCallback onViewTransactions;
  final int referralCount;
  final List<Member> directReferrals;
  final List<Member> indirectReferrals;
  final String referrerName;
  final bool referralsLoading;
  final List<Sale> availedPackages;
  final bool packagesLoading;
  final String currentPackageName;
  final bool showHeader;
  final VoidCallback? onCreateAccount;
  final VoidCallback? onUpgradePackage;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final fullName =
        [member['firstName'], member['middleName'], member['lastName']]
            .where((part) => part != null && part.toString().trim().isNotEmpty)
            .join(' ');

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (showHeader) ...[
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: theme.colorScheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(14),
                ),
                alignment: Alignment.center,
                child: Text(
                  fullName.isNotEmpty ? fullName[0].toUpperCase() : '?',
                  style: StockpileFonts.satoshi(
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                    color: theme.colorScheme.onSurface,
                  ),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      fullName.isEmpty ? 'Unnamed Member' : fullName,
                      style: StockpileFonts.satoshi(
                        fontSize: 20,
                        fontWeight: FontWeight.w800,
                        color: theme.colorScheme.onSurface,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Row(
                      children: [
                        Text(
                          'ID #${member['id'] ?? '—'}',
                          style: StockpileFonts.satoshi(
                            fontSize: 12,
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                        const SizedBox(width: 8),
                        InteractiveMemberAvatar(
                          memberId: member['id'] as int?,
                          lastName: (member['lastName'] ?? '').toString(),
                          firstName: (member['firstName'] ?? '').toString(),
                          middleName: (member['middleName'] ?? '').toString(),
                          imageUrl: (member['image'] ?? '').toString(),
                          qrToken: (member['qr'] ?? '').toString(),
                          size: 28,
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
        ],

        // ── Key Details card ──────────────────────────────
        _buildKeyDetailsCard(theme),
        const SizedBox(height: 16),

        // ── Personal Info section ─────────────────────────
        _SectionHeader(icon: Icons.person_outline, title: 'Personal Info'),
        const SizedBox(height: 8),
        _DetailLine(
          icon: Icons.cake_outlined,
          label: 'Birthday',
          value: member['birthday'],
        ),
        _DetailLine(
          icon: Icons.home_outlined,
          label: 'Address',
          value: member['address'],
        ),
        _DetailLine(
          icon: Icons.phone_outlined,
          label: 'Contact',
          value: member['contactNo'],
        ),
        const SizedBox(height: 8),

        // ── Referral section ──────────────────────────────
        _SectionHeader(icon: Icons.group_outlined, title: 'Referral'),
        const SizedBox(height: 8),
        // Referral details — a 2×2 grid when there's room, but a single
        // full-width column on narrow (mobile) layouts. In the grid each
        // cell is only half-width, which squeezes the "Referred by" name
        // until it wraps vertically; stacking gives every item full width.
        LayoutBuilder(
          builder: (context, constraints) {
            final referredBy = _ReferralDetailLine(
              icon: Icons.person_add_outlined,
              label: 'Referred by',
              value: referrerName.isEmpty ? 'None' : referrerName,
              isLoading: referralsLoading,
            );
            final directRef = _ReferralDropdown(
              icon: Icons.arrow_forward_rounded,
              label: 'Direct Referral',
              members: directReferrals,
              emptyText: 'No direct referrals',
              isLoading: referralsLoading,
            );
            final referralCountLine = _ReferralDetailLine(
              icon: Icons.people_outline,
              label: 'Referral Count',
              value: referralsLoading ? '...' : '$referralCount',
              isLoading: referralsLoading,
            );
            final indirectRef = _ReferralDropdown(
              icon: Icons.arrow_forward_rounded,
              label: 'Indirect Referral',
              members: indirectReferrals,
              emptyText: 'No indirect referrals',
              isLoading: referralsLoading,
            );

            if (constraints.maxWidth < 380) {
              return Column(
                children: [
                  referredBy,
                  const SizedBox(height: 8),
                  referralCountLine,
                  const SizedBox(height: 8),
                  directRef,
                  const SizedBox(height: 8),
                  indirectRef,
                ],
              );
            }

            return Column(
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(child: referredBy),
                    const SizedBox(width: 10),
                    Expanded(child: directRef),
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(child: referralCountLine),
                    const SizedBox(width: 10),
                    Expanded(child: indirectRef),
                  ],
                ),
              ],
            );
          },
        ),
        const SizedBox(height: 8),

        // ── Packages section (Verified Resellers only) ─────
        // Packages are exclusive to resellers; standard members never
        // see this section.
        if ((member['role'] ?? '').toString() == 'Verified Reseller') ...[
          _SectionHeader(
            icon: Icons.card_giftcard_outlined,
            title: 'Packages Availed',
          ),
          const SizedBox(height: 8),
          if (packagesLoading)
            _DetailLine(
              icon: Icons.card_giftcard_outlined,
              label: 'Packages',
              value: 'Loading…',
            )
          else if (availedPackages.isEmpty)
            _DetailLine(
              icon: Icons.card_giftcard_outlined,
              label: 'Packages',
              value: 'No package availed yet',
            )
          else
            ...availedPackages.map(
              (s) => _DetailLine(
                icon: Icons.card_giftcard_outlined,
                label: s.itemName,
                value:
                    '₱${s.price}'
                    '${s.timestamp != null ? ' · ${formatDisplayDate(s.timestamp)}' : ''}',
              ),
            ),
          const SizedBox(height: 8),
        ],

        // ── Account section ───────────────────────────────
        _SectionHeader(icon: Icons.security_outlined, title: 'Account'),
        const SizedBox(height: 8),
        _buildAccountStatus(context, theme),

        const SizedBox(height: 16),
        LayoutBuilder(
          builder: (context, constraints) {
            final isNarrow = constraints.maxWidth < 360;
            if (isNarrow) {
              return FilledButton.tonalIcon(
                onPressed: onViewTransactions,
                icon: const Icon(Icons.receipt_long_outlined, size: 18),
                label: const Text('View History'),
              );
            }

            return Row(
              children: [
                FilledButton.tonalIcon(
                  onPressed: onViewTransactions,
                  icon: const Icon(Icons.receipt_long_outlined, size: 18),
                  label: const Text('View History'),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Opens this member\'s purchases',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
              ],
            );
          },
        ),
        // ── Upgrade Package (Admin/Cashier) ─────────────────────────
        // Always available to staff — assigns a first package to a plain
        // Member or raises a reseller's tier. The account-required rule is
        // enforced by the guard in _showUpgradePackageDialog.
        if (onUpgradePackage != null) ...[
          const SizedBox(height: 16),
          const Divider(height: 1),
          const SizedBox(height: 12),
          RoleVisibility(
            allowedRoles: {UserRole.admin, UserRole.cashier},
            child: SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: onUpgradePackage,
                icon: const Icon(Icons.upgrade, size: 18),
                label: const Text('Upgrade Package'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: StockpileColors.primary900,
                  side: const BorderSide(
                    color: StockpileColors.primary900,
                    width: 1.5,
                  ),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 4),
        ],
      ],
    );
  }

  Widget _buildAccountStatus(BuildContext context, ThemeData theme) {
    final hasEmail = (member['email']?.toString() ?? '').trim().isNotEmpty;
    final hasAccount = hasEmail;
    final email = hasEmail ? member['email']!.toString().trim() : null;
    final pkgLabel = currentPackageName.isNotEmpty
        ? currentPackageName
        : 'Standard Account';

    if (hasAccount) {
      // ── Has login account ──────────────────────────────
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _DetailLine(
            icon: Icons.check_circle_outline,
            label: 'Status',
            value: 'Active login account',
          ),
          _DetailLine(
            icon: Icons.inventory_2_outlined,
            label: 'Package',
            value: pkgLabel,
          ),
          if (email != null)
            _DetailLine(
              icon: Icons.email_outlined,
              label: 'Email',
              value: email,
            ),
        ],
      );
    }

    // ── No login account ─────────────────────────────────
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _DetailLine(
          icon: Icons.person_outline,
          label: 'Status',
          value: 'No login account',
        ),
        _DetailLine(
          icon: Icons.inventory_2_outlined,
          label: 'Package',
          value: pkgLabel,
        ),
        if (onCreateAccount != null) ...[
          const SizedBox(height: 6),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: onCreateAccount,
              icon: const Icon(Icons.person_add_rounded, size: 18),
              label: const Text('Create Login Account'),
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildKeyDetailsCard(ThemeData theme) {
    final role = (member['role'] ?? 'Member').toString();
    final isReseller = role == 'Verified Reseller';
    final memberId = member['id']?.toString() ?? '—';
    final displayPkg = currentPackageName.isNotEmpty
        ? currentPackageName
        : 'Standard Account';

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: theme.dividerColor.withAlpha(50)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withAlpha(8),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        children: [
          // ── Member ID ──────────────────────────────────
          Expanded(
            flex: 2,
            child: _KeyDetailTile(
              icon: Icons.fingerprint,
              label: 'ID',
              value: '#$memberId',
            ),
          ),
          // ── Divider ────────────────────────────────────
          Container(
            width: 1,
            height: 28,
            color: theme.dividerColor.withAlpha(50),
          ),
          const SizedBox(width: 12),
          // ── Role ────────────────────────────────────────
          Expanded(
            flex: 2,
            child: _KeyDetailTile(
              icon: isReseller ? Icons.verified_user : Icons.badge_outlined,
              label: 'Role',
              value: role,
            ),
          ),
          // ── Divider ────────────────────────────────────
          Container(
            width: 1,
            height: 28,
            color: theme.dividerColor.withAlpha(50),
          ),
          const SizedBox(width: 12),
          // ── Package (always visible, positioned beside role/account) ─
          Expanded(
            flex: 3,
            child: _KeyDetailTile(
              icon: Icons.inventory_2_outlined,
              label: 'Package',
              value: displayPkg,
            ),
          ),
        ],
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.icon, required this.title});

  final IconData icon;
  final String title;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Row(
        children: [
          Icon(icon, size: 16, color: theme.colorScheme.onSurfaceVariant),
          const SizedBox(width: 8),
          Text(
            title,
            style: StockpileFonts.satoshi(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: theme.colorScheme.onSurface,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Divider(
              color: theme.dividerColor.withAlpha(60),
              thickness: 1,
            ),
          ),
        ],
      ),
    );
  }
}

class _KeyDetailTile extends StatelessWidget {
  const _KeyDetailTile({
    required this.icon,
    required this.label,
    required this.value,
  });

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 16, color: theme.colorScheme.primary),
        const SizedBox(width: 8),
        Text(
          label,
          style: theme.textTheme.labelSmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
            fontWeight: FontWeight.w500,
          ),
        ),
        const SizedBox(width: 6),
        Flexible(
          child: Text(
            value,
            style: theme.textTheme.labelMedium?.copyWith(
              fontWeight: FontWeight.w800,
              color: theme.colorScheme.onSurface,
            ),
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }
}

class _MemberTransactionHistory extends StatelessWidget {
  const _MemberTransactionHistory({required this.memberId});

  final int memberId;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(Icons.receipt_long_outlined, color: theme.colorScheme.primary),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                'Member Transaction History',
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        FutureBuilder<List<Sale>>(
          future: repository.fetchSalesForMember(memberId),
          builder: (context, snap) {
            if (snap.connectionState == ConnectionState.waiting) {
              return const SizedBox(
                height: 180,
                child: SingleChildScrollView(child: SkeletonList(count: 3)),
              );
            }

            final sales = snap.data ?? [];

            // Build sorted timeline (newest first)
            final allEntries = <_TimelineEntry>[
              for (final s in sales)
                _TimelineEntry(
                  type: 'sale',
                  timestamp: s.timestamp ?? DateTime(2000),
                  sale: s,
                ),
            ]..sort((a, b) => b.timestamp.compareTo(a.timestamp));

            if (allEntries.isEmpty) return const _EmptyTransactions();

            final totalSalesQty = sales.fold<int>(
              0,
              (s, sale) => s + sale.quantity,
            );
            final totalSalesPrice = sales.fold<int>(
              0,
              (s, sale) => s + sale.price * sale.quantity,
            );
            final visibleEntries = allEntries.take(8).toList();

            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    _InfoPill(
                      icon: Icons.shopping_bag_outlined,
                      label: 'Sales',
                      value: sales.length.toString(),
                    ),
                    _InfoPill(
                      icon: Icons.inventory_2_outlined,
                      label: 'Sold Qty',
                      value: totalSalesQty.toString(),
                    ),
                    _InfoPill(
                      icon: Icons.payments_outlined,
                      label: 'Total',
                      value: '₱$totalSalesPrice',
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                SizedBox(
                  height: 350,
                  child: ListView.separated(
                    itemCount: visibleEntries.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 8),
                    itemBuilder: (context, index) =>
                        _TransactionRow(entry: visibleEntries[index]),
                  ),
                ),
                if (allEntries.length > visibleEntries.length) ...[
                  const SizedBox(height: 8),
                  Text(
                    '${allEntries.length - visibleEntries.length} more transaction(s)',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ],
            );
          },
        ),
      ],
    );
  }
}

class _TimelineEntry {
  final String type; // 'sale'
  final DateTime timestamp;
  final Sale? sale;

  const _TimelineEntry({
    required this.type,
    required this.timestamp,
    this.sale,
  });
}

class _TransactionRow extends StatelessWidget {
  const _TransactionRow({required this.entry});

  final _TimelineEntry entry;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final sale = entry.sale!;

    final typeColor = Colors.green.shade600;
    const typeLabel = 'Sold';
    const typeIcon = Icons.shopping_cart;
    final itemName = sale.itemName;
    final quantity = sale.quantity;
    final timestamp = sale.timestamp;
    final price = sale.price;

    return DecoratedBox(
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.7),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: theme.dividerColor.withValues(alpha: 0.5)),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        child: Row(
          children: [
            Container(
              width: 38,
              height: 38,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: typeColor.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                quantity.toString(),
                style: theme.textTheme.titleSmall?.copyWith(
                  color: typeColor,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          itemName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      const SizedBox(width: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: typeColor.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(typeIcon, size: 12, color: typeColor),
                            const SizedBox(width: 3),
                            Text(
                              typeLabel,
                              style: theme.textTheme.labelSmall?.copyWith(
                                color: typeColor,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 3),
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          formatDisplayDate(timestamp),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  '₱${price}',
                  style: theme.textTheme.labelLarge?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  'S${sale.id}',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _InfoPill extends StatelessWidget {
  const _InfoPill({
    required this.icon,
    required this.label,
    required this.value,
  });

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return DecoratedBox(
      decoration: BoxDecoration(
        color: colorScheme.primary.withAlpha(15),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: colorScheme.primary.withAlpha(30)),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 16, color: colorScheme.primary),
            const SizedBox(width: 6),
            Text(
              '$label: ',
              style: theme.textTheme.labelMedium?.copyWith(
                color: colorScheme.onSurfaceVariant,
              ),
            ),
            Text(
              value,
              style: theme.textTheme.labelMedium?.copyWith(
                fontWeight: FontWeight.w800,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DetailLine extends StatelessWidget {
  const _DetailLine({
    required this.icon,
    required this.label,
    required this.value,
  });

  final IconData icon;
  final String label;
  final Object? value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final text = value == null || value.toString().trim().isEmpty
        ? 'Not set'
        : value.toString();

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: theme.colorScheme.surfaceContainerHighest.withAlpha(80),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, size: 17, color: theme.colorScheme.onSurfaceVariant),
            const SizedBox(width: 10),
            SizedBox(
              width: 70,
              child: Text(
                label,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            Expanded(
              child: Text(
                text,
                style: theme.textTheme.bodyMedium?.copyWith(
                  fontStyle: FontStyle.normal,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _EmptyTransactions extends StatelessWidget {
  const _EmptyTransactions();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return DecoratedBox(
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.7),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: theme.dividerColor.withValues(alpha: 0.5)),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 22),
        child: Row(
          children: [
            Icon(
              Icons.history_outlined,
              color: theme.colorScheme.onSurfaceVariant,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                'No purchases recorded for this member yet.',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Referral UI helpers ───────────────────────────────────────────────────

/// Compact detail line for the two-column referral layout.
class _ReferralDetailLine extends StatelessWidget {
  const _ReferralDetailLine({
    required this.icon,
    required this.label,
    required this.value,
    this.isLoading = false,
  });

  final IconData icon;
  final String label;
  final String value;
  final bool isLoading;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest.withAlpha(80),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          Icon(icon, size: 17, color: theme.colorScheme.onSurfaceVariant),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              label,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
                fontWeight: FontWeight.w600,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          Flexible(
            child: Text(
              isLoading ? '...' : value,
              style: theme.textTheme.bodyMedium?.copyWith(
                fontWeight: FontWeight.w700,
              ),
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.end,
            ),
          ),
        ],
      ),
    );
  }
}

/// Dropdown button showing a list of referral member names.
class _ReferralDropdown extends StatelessWidget {
  const _ReferralDropdown({
    required this.icon,
    required this.label,
    required this.members,
    required this.emptyText,
    this.isLoading = false,
  });

  final IconData icon;
  final String label;
  final List<Member> members;
  final String emptyText;
  final bool isLoading;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final hasItems = members.isNotEmpty && !isLoading;

    return PopupMenuButton<Member>(
      enabled: hasItems,
      offset: const Offset(0, 44),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      itemBuilder: (_) => members.map((m) {
        final name = [
          m.firstName,
          m.lastName,
        ].where((p) => p != null && p.isNotEmpty).join(' ');
        return PopupMenuItem<Member>(
          value: m,
          child: Row(
            children: [
              Icon(
                Icons.person_outline,
                size: 18,
                color: theme.colorScheme.primary,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  name.isNotEmpty ? name : 'Member #${m.id}',
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        );
      }).toList(),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: theme.colorScheme.surfaceContainerHighest.withAlpha(80),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(
          children: [
            Icon(icon, size: 17, color: theme.colorScheme.onSurfaceVariant),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                label,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                  fontWeight: FontWeight.w600,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            Text(
              isLoading
                  ? '...'
                  : hasItems
                  ? '${members.length} ▼'
                  : emptyText,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: hasItems
                    ? theme.colorScheme.primary
                    : theme.colorScheme.onSurfaceVariant,
                fontWeight: hasItems ? FontWeight.w600 : FontWeight.normal,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
