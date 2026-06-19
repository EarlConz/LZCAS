// ignore_for_file: unnecessary_underscores
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';

import 'interactive_member_avatar.dart';
import '../utils/formatters.dart';
import 'package:lzcas/db/db.dart';

/// Build an image widget from either a file path (native) or a data URL (web).
Widget buildIdImage(
  BuildContext context,
  String source, {
  BoxFit fit = BoxFit.contain,
  double? height,
  double? width,
}) {
  if (source.startsWith('data:')) {
    final commaIdx = source.indexOf(',');
    if (commaIdx < 0) {
      return const Icon(Icons.broken_image, size: 48);
    }
    final bytes = base64Decode(source.substring(commaIdx + 1));
    return Image.memory(
      Uint8List.fromList(bytes),
      fit: fit,
      height: height,
      width: width,
      errorBuilder: (_, __, ___) => Container(
        height: 60,
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        child: const Center(child: Text('Image not available')),
      ),
    );
  }
  return Image.file(
    File(source),
    fit: fit,
    height: height,
    width: width,
    errorBuilder: (_, __, ___) => Container(
      height: 60,
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      child: const Center(child: Text('Image not available')),
    ),
  );
}

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
  late final StreamSubscription<String> _sub;

  @override
  void initState() {
    super.initState();
    member = widget.member;
    _computeReferralCount();
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
        }
      }
    });
  }

  Future<void> _computeReferralCount() async {
    final memberId = member['id'] as int?;
    if (memberId == null) return;

    final memberName =
        '${member['firstName'] ?? ''} ${member['lastName'] ?? ''}'
            .trim()
            .toLowerCase();

    final all = await repository.fetchMembers();
    if (!mounted) return;
    final count = all.where((m) {
      // Primary: match by referrerId (new records)
      if (m.referrerId == memberId) return true;
      // Fallback: match by referrer name string (legacy records)
      if (memberName.isNotEmpty) {
        final ref = (m.referrer ?? '').trim().toLowerCase();
        if (ref.isNotEmpty && ref == memberName) return true;
      }
      return false;
    }).length;
    setState(() => _referralCount = count);
  }

  @override
  void didUpdateWidget(covariant MemberDetailsCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    member = widget.member;
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

  void _showIdImagePreview(String imagePath) {
    showDialog(
      context: context,
      builder: (ctx) => Dialog(
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.of(ctx).size.height * 0.8,
            maxWidth: MediaQuery.of(ctx).size.width * 0.9,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Expanded(
                child: InteractiveViewer(
                  child: buildIdImage(context, imagePath, fit: BoxFit.contain),
                ),
              ),
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Close'),
              ),
            ],
          ),
        ),
      ),
    );
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
            onViewTransactions: _showTransactionHistory,
            showHeader: widget.showHeader,
            onIdImageTap: () {
              final path = widget.member['idImagePath']?.toString();
              if (path != null && path.isNotEmpty) {
                _showIdImagePreview(path);
              }
            },
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
        borderRadius: BorderRadius.circular(8),
        boxShadow: [
          BoxShadow(
            color: Colors.grey.withValues(alpha: 0.2),
            blurRadius: 10,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          return _MemberProfileSection(
            member: widget.member,
            referralCount: _referralCount,
            onViewTransactions: _showTransactionHistory,
            showHeader: widget.showHeader,
            onIdImageTap: () {
              final path = widget.member['idImagePath']?.toString();
              if (path != null && path.isNotEmpty) {
                _showIdImagePreview(path);
              }
            },
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
    this.showHeader = true,
    this.onIdImageTap,
  });

  final Map<String, dynamic> member;
  final VoidCallback onViewTransactions;
  final int referralCount;
  final bool showHeader;
  final VoidCallback? onIdImageTap;

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
          RichText(
            text: TextSpan(
              style: DefaultTextStyle.of(
                context,
              ).style.copyWith(fontSize: 22, fontWeight: FontWeight.bold),
              children: [
                TextSpan(text: fullName.isEmpty ? 'Unnamed Member' : fullName),
                WidgetSpan(
                  alignment: PlaceholderAlignment.middle,
                  child: Padding(
                    padding: const EdgeInsets.only(left: 8.0),
                    child: InteractiveMemberAvatar(
                      memberId: member['id'] as int?,
                      lastName: (member['lastName'] ?? '').toString(),
                      firstName: (member['firstName'] ?? '').toString(),
                      middleName: (member['middleName'] ?? '').toString(),
                      imageUrl: (member['image'] ?? '').toString(),
                      qrToken: (member['qr'] ?? '').toString(),
                      size: 36,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
        ],
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            _InfoPill(
              icon: Icons.badge_outlined,
              label: 'Role',
              value: (member['idImagePath']?.toString() ?? '').isNotEmpty
                  ? 'Verified Reseller'
                  : (member['role'] ?? 'Member').toString(),
            ),
            if ((member['role'] ?? '') == 'Verified Reseller')
              _InfoPill(
                icon: Icons.stars_outlined,
                label: 'Level',
                value: (member['level'] ?? 1).toString(),
              ),
          ],
        ),
        const SizedBox(height: 14),
        _DetailLine(
          icon: Icons.phone_outlined,
          label: 'Contact',
          value: member['contactNo'],
        ),
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
          icon: Icons.group_outlined,
          label: 'Referrer',
          value:
              member['referrer'] != null &&
                  member['referrer'].toString().trim().isNotEmpty
              ? member['referrer']
              : 'None',
          italic: true,
        ),
        _DetailLine(
          icon: Icons.people_outline,
          label: 'Referrals',
          value: referralCount > 0 ? '$referralCount' : 'None',
        ),
        // ── ID Verification section ────────────────────────
        if ((member['idImagePath']?.toString() ?? '').isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 12),
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.green.shade50,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: Colors.green.shade200),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(
                        Icons.verified_user,
                        size: 18,
                        color: Colors.green.shade700,
                      ),
                      const SizedBox(width: 6),
                      Text(
                        'Verified Reseller',
                        style: theme.textTheme.labelMedium?.copyWith(
                          color: Colors.green.shade700,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  _DetailLine(
                    icon: Icons.credit_card_outlined,
                    label: 'ID Type',
                    value: member['idType'],
                  ),
                  if ((member['idNumber']?.toString() ?? '').isNotEmpty)
                    _DetailLine(
                      icon: Icons.numbers_outlined,
                      label: 'ID Number',
                      value: member['idNumber'],
                    ),
                  if ((member['idImagePath']?.toString() ?? '').isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: GestureDetector(
                        onTap: () => onIdImageTap?.call(),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(8),
                          child: buildIdImage(
                            context,
                            member['idImagePath'].toString(),
                            height: 120,
                            width: double.infinity,
                            fit: BoxFit.contain,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        const SizedBox(height: 8),
        LayoutBuilder(
          builder: (context, constraints) {
            final isNarrow = constraints.maxWidth < 360;
            if (isNarrow) {
              return ElevatedButton.icon(
                onPressed: onViewTransactions,
                icon: const Icon(Icons.receipt_long_outlined),
                label: const Text('View History'),
              );
            }

            return Row(
              children: [
                ElevatedButton.icon(
                  onPressed: onViewTransactions,
                  icon: const Icon(Icons.receipt_long_outlined),
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
                child: Center(child: CircularProgressIndicator()),
              );
            }

            final sales = [...?snap.data]
              ..sort((a, b) => b.timestamp.compareTo(a.timestamp));
            if (sales.isEmpty) return const _EmptyTransactions();

            final totalQuantity = sales.fold<int>(
              0,
              (sum, sale) => sum + sale.quantity,
            );
            final totalPoints = sales.fold<int>(
              0,
              (sum, sale) => sum + sale.price,
            );
            final totalPrice = sales.fold<int>(
              0,
              (sum, sale) => sum + sale.price,
            );
            final visibleSales = sales.take(8).toList();

            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    _InfoPill(
                      icon: Icons.shopping_bag_outlined,
                      label: 'Purchases',
                      value: sales.length.toString(),
                    ),
                    _InfoPill(
                      icon: Icons.inventory_2_outlined,
                      label: 'Qty',
                      value: totalQuantity.toString(),
                    ),
                    _InfoPill(
                      icon: Icons.stars_outlined,
                      label: 'Points',
                      value: totalPoints.toString(),
                    ),
                    _InfoPill(
                      icon: Icons.payments_outlined,
                      label: 'Total',
                      value: totalPrice.toString(),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                SizedBox(
                  height: 300,
                  child: ListView.separated(
                    itemCount: visibleSales.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 8),
                    itemBuilder: (context, index) =>
                        _TransactionRow(sale: visibleSales[index]),
                  ),
                ),
                if (sales.length > visibleSales.length) ...[
                  const SizedBox(height: 8),
                  Text(
                    '${sales.length - visibleSales.length} more transaction${sales.length - visibleSales.length == 1 ? '' : 's'} in the Transactions page',
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

class _TransactionRow extends StatelessWidget {
  const _TransactionRow({required this.sale});

  final Sale sale;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

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
                color: colorScheme.primary.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                sale.quantity.toString(),
                style: theme.textTheme.titleSmall?.copyWith(
                  color: colorScheme.primary,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    sale.itemName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    formatDisplayDate(sale.timestamp),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  '₱${sale.price}',
                  style: theme.textTheme.labelLarge?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  'ID ${sale.id}',
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
        color: colorScheme.primary.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
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
    this.italic = false,
  });

  final IconData icon;
  final String label;
  final Object? value;
  final bool italic;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final text = value == null || value.toString().trim().isEmpty
        ? 'Not set'
        : value.toString();

    return Padding(
      padding: const EdgeInsets.only(bottom: 7),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 17, color: theme.colorScheme.onSurfaceVariant),
          const SizedBox(width: 8),
          SizedBox(
            width: 74,
            child: Text(
              label,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          Expanded(
            child: Text(
              text,
              style: theme.textTheme.bodyMedium?.copyWith(
                fontStyle: italic ? FontStyle.italic : FontStyle.normal,
              ),
            ),
          ),
        ],
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
