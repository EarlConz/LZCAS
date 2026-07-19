// lib/widgets/member_detail_dialog.dart
// Shared member detail dialog used by both Admin and Cashier dashboards.
// Shows full member info with action buttons (View History, Edit, Delete).
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:lzcas/utils/animations.dart';
import 'package:lzcas/theme.dart';
import 'package:lzcas/utils/fonts.dart';
import 'package:lzcas/db/db.dart';

/// Opens the shared member detail dialog.
/// [onViewHistory] — called when "View History" is tapped.
/// [onEdit] — called when "Edit Member" is tapped (dialog closes first).
/// [onDelete] — called when "Delete Member" is confirmed.
/// [onCreateAccount] — called when "Create Login Account" is tapped.
/// [onViewPassword] — called when "View Password" is tapped.
/// [onUpgrade] — called when "Upgrade Package" is tapped (Verified Resellers only).
Future<void> showMemberDetailDialog({
  required BuildContext context,
  required Map<String, dynamic> member,
  VoidCallback? onViewHistory,
  VoidCallback? onEdit,
  VoidCallback? onDelete,
  VoidCallback? onCreateAccount,
  VoidCallback? onViewPassword,
  VoidCallback? onUpgrade,
}) async {
  // Resolve package name
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

  if (!context.mounted) return;

  final fullName = [
    member['firstName'],
    member['middleName'],
    member['lastName'],
  ].where((p) => p != null && p.toString().trim().isNotEmpty).join(' ');
  final initials = fullName.isNotEmpty ? fullName[0].toUpperCase() : 'M';
  final isReseller = (member['role']?.toString() ?? '') == 'Verified Reseller';
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
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
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
                      if ((member['idImagePath']?.toString() ?? '').isNotEmpty)
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
                                final path = member['idImagePath']?.toString();
                                if (path != null && path.isNotEmpty) {
                                  _showIdImagePreview(ctx, path);
                                }
                              },
                              child: ClipRRect(
                                borderRadius: BorderRadius.circular(10),
                                child: _buildIdImage(
                                  member['idImagePath'].toString(),
                                ),
                              ),
                            ),
                            const SizedBox(height: 4),
                          ],
                        ),
                      const SizedBox(height: 20),
                      if (!hasAccount && onCreateAccount != null)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: SizedBox(
                            width: double.infinity,
                            child: OutlinedButton.icon(
                              onPressed: onCreateAccount,
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
                      if (hasAccount && onViewPassword != null)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: SizedBox(
                            width: double.infinity,
                            child: OutlinedButton.icon(
                              onPressed: onViewPassword,
                              icon: const Icon(
                                Icons.vpn_key_rounded,
                                size: 18,
                                color: Colors.amber,
                              ),
                              label: const Text('View Password'),
                              style: OutlinedButton.styleFrom(
                                foregroundColor: Colors.amber.shade800,
                                side: BorderSide(color: Colors.amber.shade300),
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
                              onPressed:
                                  onViewHistory ?? () => Navigator.pop(ctx),
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
                                onEdit?.call();
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
                      // ── Upgrade Package (Verified Resellers only) ─
                      if (onUpgrade != null && isReseller)
                        Padding(
                          padding: const EdgeInsets.only(top: 8),
                          child: SizedBox(
                            width: double.infinity,
                            child: OutlinedButton.icon(
                              onPressed: onUpgrade,
                              icon: const Icon(Icons.upgrade, size: 18),
                              label: const Text('Upgrade Package'),
                              style: OutlinedButton.styleFrom(
                                foregroundColor: StockpileColors.primary900,
                                side: const BorderSide(
                                  color: StockpileColors.primary900,
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
                      if (onDelete != null) ...[
                        const SizedBox(height: 8),
                        SizedBox(
                          width: double.infinity,
                          child: TextButton.icon(
                            onPressed: onDelete,
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

void _showIdImagePreview(BuildContext context, String path) {
  showDialog(
    context: context,
    builder: (ctx) => Dialog(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: _buildIdImage(path),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Close'),
          ),
        ],
      ),
    ),
  );
}

Widget _buildIdImage(String source) {
  if (source.startsWith('http://') || source.startsWith('https://')) {
    return Image.network(
      source,
      fit: BoxFit.contain,
      errorBuilder: (_, __, ___) => const Icon(Icons.broken_image, size: 48),
    );
  }
  if (source.startsWith('data:')) {
    final commaIdx = source.indexOf(',');
    if (commaIdx < 0) return const Icon(Icons.broken_image, size: 48);
    final bytes = base64Decode(source.substring(commaIdx + 1));
    return Image.memory(
      Uint8List.fromList(bytes),
      fit: BoxFit.contain,
      errorBuilder: (_, __, ___) => const Icon(Icons.broken_image, size: 48),
    );
  }
  final file = File(source);
  if (!file.existsSync()) return const Icon(Icons.broken_image, size: 48);
  return Image.file(
    file,
    fit: BoxFit.contain,
    errorBuilder: (_, __, ___) => const Icon(Icons.broken_image, size: 48),
  );
}

// ── Private helper widgets ─────────────────────────────────────────────

class _AvatarHeader extends StatelessWidget {
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
  final String initials, fullName, memberId, email, packageName;
  final bool isReseller, hasAccount, isDark;
  final Color textColor, muted;

  @override
  Widget build(BuildContext context) {
    return Column(
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
}

class _InfoCard extends StatelessWidget {
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
  final bool isDark;
  final Color textColor, muted, surface, divider;
  final String title;
  final IconData icon;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Container(
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
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({
    required this.icon,
    required this.label,
    this.value,
    required this.muted,
    required this.textColor,
    required this.isDark,
    this.isLast = false,
  });
  final IconData icon;
  final String label;
  final dynamic value;
  final Color muted, textColor;
  final bool isDark, isLast;

  @override
  Widget build(BuildContext context) {
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
  const _ReferralCard({
    required this.member,
    required this.isDark,
    required this.textColor,
    required this.muted,
    required this.surface,
    required this.divider,
  });
  final Map<String, dynamic> member;
  final bool isDark;
  final Color textColor, muted, surface, divider;

  @override
  State<_ReferralCard> createState() => _ReferralCardState();
}

class _ReferralCardState extends State<_ReferralCard> {
  String _referrerName = '';
  int _directCount = 0;
  int _indirectCount = 0;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final memberId = widget.member['id'] as int?;
    final memberName = [widget.member['firstName'], widget.member['lastName']]
        .where((p) => p != null && p.toString().trim().isNotEmpty)
        .join(' ')
        .toLowerCase();

    final all = await repository.fetchMembers();
    if (!mounted) return;

    String referrerName = '';
    final referrerIdRaw = widget.member['referrerId'] as int?;
    if (referrerIdRaw != null) {
      final ref = all.where((m) => m.id == referrerIdRaw).firstOrNull;
      if (ref != null) {
        referrerName = [
          ref.firstName,
          ref.lastName,
        ].where((p) => p != null && p.isNotEmpty).join(' ');
      }
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
    final indirectCount = all
        .where((m) => m.referrerId != null && directIds.contains(m.referrerId))
        .length;

    if (mounted)
      setState(() {
        _referrerName = referrerName;
        _directCount = direct.length;
        _indirectCount = indirectCount;
        _loading = false;
      });
  }

  @override
  Widget build(BuildContext context) {
    return _InfoCard(
      isDark: widget.isDark,
      textColor: widget.textColor,
      muted: widget.muted,
      surface: widget.surface,
      divider: widget.divider,
      title: 'Referral',
      icon: Icons.group_outlined,
      children: [
        _InfoRow(
          icon: Icons.person_add_outlined,
          label: 'Referred by',
          value: _referrerName.isEmpty ? 'None' : _referrerName,
          muted: widget.muted,
          textColor: widget.textColor,
          isDark: widget.isDark,
        ),
        _InfoRow(
          icon: Icons.arrow_forward_rounded,
          label: 'Direct Referrals',
          value: _loading ? '...' : '$_directCount',
          muted: widget.muted,
          textColor: widget.textColor,
          isDark: widget.isDark,
        ),
        _InfoRow(
          icon: Icons.arrow_forward_rounded,
          label: 'Indirect Referrals',
          value: _loading ? '...' : '$_indirectCount',
          muted: widget.muted,
          textColor: widget.textColor,
          isDark: widget.isDark,
          isLast: true,
        ),
      ],
    );
  }
}
