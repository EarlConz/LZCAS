import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../db/db.dart' show Borrow;
import '../theme.dart' show appRadius;

/// A receipt dialog shown after confirming a borrow transaction.
class BorrowReceiptDialog extends StatefulWidget {
  /// Borrow records that were just created.
  final List<Borrow> borrows;

  /// The reseller who borrowed the items.
  final String? memberName;

  /// When the borrow was recorded.
  final DateTime borrowedAt;

  /// When items are due (same for all items in a single borrow session).
  final DateTime dueDate;

  const BorrowReceiptDialog({
    super.key,
    required this.borrows,
    this.memberName,
    required this.borrowedAt,
    required this.dueDate,
  });

  @override
  State<BorrowReceiptDialog> createState() => _BorrowReceiptDialogState();
}

class _BorrowReceiptDialogState extends State<BorrowReceiptDialog> {
  String get _ref {
    final d = widget.borrowedAt;
    return 'BRW-${d.year}${d.month.toString().padLeft(2, '0')}'
        '${d.day.toString().padLeft(2, '0')}'
        '-${d.hour.toString().padLeft(2, '0')}'
        '${d.minute.toString().padLeft(2, '0')}';
  }

  int get _totalItems =>
      widget.borrows.fold<int>(0, (sum, b) => sum + b.quantity);

  String _format(DateTime? dt) =>
      dt != null ? DateFormat('MMM d, yyyy  h:mm a').format(dt) : '—';

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;
    final dueFmt = DateFormat('MMM d, yyyy').format(widget.dueDate);
    final daysLeft = widget.dueDate
        .difference(DateTime.now())
        .inDays
        .clamp(0, 999);

    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: Row(
        children: [
          Icon(
            Icons.receipt_long_rounded,
            color: colorScheme.primary,
            size: 28,
          ),
          const SizedBox(width: 10),
          Text(
            'Borrow Receipt',
            style: theme.textTheme.headlineSmall?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
      content: SizedBox(
        width: 520,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Reference + date
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    _ref,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: colorScheme.onSurface.withAlpha(150),
                    ),
                  ),
                  Text(
                    _format(widget.borrowedAt),
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: colorScheme.onSurface.withAlpha(150),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),

              // Member
              if (widget.memberName != null &&
                  widget.memberName!.isNotEmpty) ...[
                Text(
                  'Borrower',
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: colorScheme.onSurface.withAlpha(150),
                  ),
                ),
                Text(
                  widget.memberName!,
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 16),
              ],

              // Due date alert
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: daysLeft <= 3
                      ? Colors.orange.shade50
                      : Colors.blue.shade50,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: daysLeft <= 3
                        ? Colors.orange.shade200
                        : Colors.blue.shade200,
                  ),
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.schedule_rounded,
                      size: 22,
                      color: daysLeft <= 3 ? Colors.orange : Colors.blue,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: RichText(
                        text: TextSpan(
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: isDark
                                ? colorScheme.onSurface
                                : Colors.black87,
                          ),
                          children: [
                            const TextSpan(text: 'Due date: '),
                            TextSpan(
                              text: dueFmt,
                              style: const TextStyle(
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            TextSpan(
                              text:
                                  '  ($daysLeft day${daysLeft == 1 ? '' : 's'} left)',
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 14),

              // Divider
              Divider(color: theme.dividerColor),

              // Items borrowed
              ...widget.borrows.map(
                (b) => Padding(
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Text(
                          b.itemName,
                          style: theme.textTheme.bodyLarge?.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Text(
                        '× ${b.quantity}',
                        style: theme.textTheme.bodyLarge?.copyWith(
                          fontWeight: FontWeight.w700,
                          color: colorScheme.primary,
                        ),
                      ),
                      if (b.price > 0) ...[
                        const SizedBox(width: 8),
                        Text(
                          '₱${b.price}/ea',
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: colorScheme.onSurface.withAlpha(180),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),

              const SizedBox(height: 8),
              Divider(color: theme.dividerColor),

              // Totals
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'Total items borrowed',
                      style: theme.textTheme.bodyMedium,
                    ),
                    Text(
                      '$_totalItems',
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),

              if (widget.borrows.any((b) => b.price > 0)) ...[
                const SizedBox(height: 4),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text('Total value', style: theme.textTheme.bodyMedium),
                    Text(
                      '₱${widget.borrows.fold<int>(0, (sum, b) => sum + b.price * b.quantity)}',
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                        color: colorScheme.primary,
                      ),
                    ),
                  ],
                ),
              ],

              const SizedBox(height: 16),

              // Note
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: colorScheme.surfaceContainerHighest.withAlpha(80),
                  borderRadius: BorderRadius.circular(appRadius),
                ),
                child: Text(
                  '⚠️ Items must be returned or paid for by $dueFmt. '
                  'Late returns may affect your borrowing privileges.',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: colorScheme.onSurface.withAlpha(200),
                    height: 1.4,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
      actions: [
        FilledButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Done'),
        ),
      ],
    );
  }
}
