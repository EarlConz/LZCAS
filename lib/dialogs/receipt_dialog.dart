import 'dart:ui' as ui;
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import '../db/db.dart' show Sale;
import '../theme.dart' show appRadius;

/// Data for a single line item on a receipt.
class ReceiptLineItem {
  final String itemName;
  final int quantity;
  final int unitPrice;

  const ReceiptLineItem({
    required this.itemName,
    required this.quantity,
    required this.unitPrice,
  });

  int get subtotal => unitPrice * quantity;
}

/// A responsive receipt dialog with print support.
class ReceiptDialog extends StatefulWidget {
  final List<ReceiptLineItem> lineItems;
  final String? buyerName;
  final DateTime transactionTime;

  const ReceiptDialog({
    super.key,
    required this.lineItems,
    this.buyerName,
    required this.transactionTime,
  });

  factory ReceiptDialog.fromSale(Sale sale, {String? buyerName}) {
    return ReceiptDialog(
      lineItems: [
        ReceiptLineItem(
          itemName: sale.itemName,
          quantity: sale.quantity,
          unitPrice: sale.price,
        ),
      ],
      buyerName: buyerName,
      transactionTime: sale.timestamp,
    );
  }

  Future<void> show(BuildContext context) {
    return showDialog<void>(context: context, builder: (_) => this);
  }

  @override
  State<ReceiptDialog> createState() => _ReceiptDialogState();
}

class _ReceiptDialogState extends State<ReceiptDialog> {
  final _receiptKey = GlobalKey();

  String get _ref {
    final d = widget.transactionTime;
    return 'TXN-${d.year}${d.month.toString().padLeft(2, '0')}'
        '${d.day.toString().padLeft(2, '0')}'
        '-${d.hour.toString().padLeft(2, '0')}'
        '${d.minute.toString().padLeft(2, '0')}';
  }

  Future<void> _print() async {
    try {
      final boundary =
          _receiptKey.currentContext?.findRenderObject()
              as RenderRepaintBoundary?;
      if (boundary == null) return;
      final image = await boundary.toImage(pixelRatio: 3.0);
      final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
      if (byteData == null) return;

      // Save receipt image to temp directory
      final dir = await getTemporaryDirectory();
      final file = File('${dir.path}/$_ref.png');
      await file.writeAsBytes(byteData.buffer.asUint8List());

      // Open with system default viewer (can print from there)
      if (Platform.isWindows) {
        await Process.run('start', [file.path], runInShell: true);
      } else if (Platform.isMacOS) {
        await Process.run('open', [file.path]);
      } else if (Platform.isLinux) {
        await Process.run('xdg-open', [file.path]);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Print failed: $e')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final isMobile = MediaQuery.of(context).size.width < 600;

    final totalPrice = widget.lineItems.fold<int>(
      0,
      (sum, i) => sum + i.subtotal,
    );
    final fmtDate = DateFormat(
      'MMMM dd, yyyy  hh:mm a',
    ).format(widget.transactionTime);

    return AlertDialog(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(appRadius),
      ),
      insetPadding: isMobile
          ? const EdgeInsets.symmetric(horizontal: 12, vertical: 24)
          : const EdgeInsets.symmetric(horizontal: 40, vertical: 40),
      contentPadding: EdgeInsets.zero,
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520),
        child: RepaintBoundary(
          key: _receiptKey,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _ReceiptHeader(colorScheme: colorScheme),
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
                  child: Column(
                    children: [
                      _InfoRow(
                        label: 'Date',
                        value: fmtDate,
                        colorScheme: colorScheme,
                      ),
                      const SizedBox(height: 6),
                      _InfoRow(
                        label: 'Ref #',
                        value: _ref,
                        colorScheme: colorScheme,
                      ),
                      if (widget.buyerName != null &&
                          widget.buyerName!.isNotEmpty) ...[
                        const SizedBox(height: 6),
                        _InfoRow(
                          label: 'Buyer',
                          value: widget.buyerName!,
                          colorScheme: colorScheme,
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(height: 4),
                const _DashedDivider(),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: isMobile
                      ? _mobileItems(theme, colorScheme)
                      : _desktopItems(theme, colorScheme),
                ),
                const _DashedDivider(),
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
                  child: Column(
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            'TOTAL',
                            style: theme.textTheme.titleLarge?.copyWith(
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          Text(
                            '₱$totalPrice',
                            style: theme.textTheme.headlineMedium?.copyWith(
                              color: colorScheme.primary,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text(
                        '— Thank you for your purchase! —',
                        style: theme.textTheme.labelMedium?.copyWith(
                          color: colorScheme.onSurfaceVariant,
                          fontStyle: FontStyle.italic,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'LZCAS Sales System',
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: colorScheme.outline,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
                  child: Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: _print,
                          icon: const Icon(Icons.print_outlined, size: 18),
                          label: const Text('Print'),
                          style: OutlinedButton.styleFrom(
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: FilledButton.icon(
                          onPressed: () => Navigator.pop(context),
                          icon: const Icon(Icons.check_circle_outline),
                          label: const Text('Done'),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ── Desktop items ───────────────────────────────────────────────

  Widget _desktopItems(ThemeData theme, ColorScheme colorScheme) {
    return Table(
      columnWidths: const {
        0: FlexColumnWidth(3),
        1: FlexColumnWidth(1.0),
        2: FlexColumnWidth(2.4),
        3: FlexColumnWidth(2.4),
      },
      children: [
        TableRow(
          decoration: BoxDecoration(
            border: Border(
              bottom: BorderSide(color: colorScheme.outline, width: 0.5),
            ),
          ),
          children: [
            _hdr('Item', theme),
            _hdr('Qty', theme, rightAlign: true),
            _hdr('Price', theme, rightAlign: true),
            _hdr('Subtotal', theme, rightAlign: true),
          ],
        ),
        for (final item in widget.lineItems)
          TableRow(
            children: [
              _cell(item.itemName, theme),
              _cell(item.quantity.toString(), theme, rightAlign: true),
              _cell('₱${item.unitPrice}', theme, rightAlign: true),
              _cell('₱${item.subtotal}', theme, rightAlign: true, bold: true),
            ],
          ),
      ],
    );
  }

  Widget _hdr(String text, ThemeData theme, {bool rightAlign = false}) {
    final w = Text(
      text,
      style: theme.textTheme.labelMedium?.copyWith(fontWeight: FontWeight.w700),
    );
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: rightAlign ? Align(alignment: Alignment.centerRight, child: w) : w,
    );
  }

  Widget _cell(
    String text,
    ThemeData theme, {
    bool rightAlign = false,
    bool bold = false,
  }) {
    final style = theme.textTheme.bodyMedium?.copyWith(
      fontWeight: bold ? FontWeight.w600 : null,
    );
    final t = Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Text(text, style: style),
    );
    return rightAlign ? Align(alignment: Alignment.centerRight, child: t) : t;
  }

  // ── Mobile items ────────────────────────────────────────────────

  Widget _mobileItems(ThemeData theme, ColorScheme colorScheme) {
    return Column(
      children: [
        for (var i = 0; i < widget.lineItems.length; i++) ...[
          if (i > 0)
            Divider(
              height: 1,
              color: colorScheme.outline.withValues(alpha: 0.4),
            ),
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  flex: 3,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        widget.lineItems[i].itemName,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'Qty: ${widget.lineItems[i].quantity}  ×  '
                        '₱${widget.lineItems[i].unitPrice}',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                Text(
                  '₱${widget.lineItems[i].subtotal}',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }
}

// ── Private sub-widgets ───────────────────────────────────────────────

class _ReceiptHeader extends StatelessWidget {
  final ColorScheme colorScheme;
  const _ReceiptHeader({required this.colorScheme});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: colorScheme.primary,
        borderRadius: const BorderRadius.vertical(
          top: Radius.circular(appRadius),
        ),
      ),
      padding: const EdgeInsets.symmetric(vertical: 20),
      child: Column(
        children: [
          Icon(
            Icons.receipt_long_rounded,
            size: 36,
            color: colorScheme.onPrimary.withValues(alpha: 0.9),
          ),
          const SizedBox(height: 8),
          Text(
            'SALES RECEIPT',
            style: Theme.of(context).textTheme.headlineSmall?.copyWith(
              color: colorScheme.onPrimary,
              fontWeight: FontWeight.w800,
              letterSpacing: 1.5,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            'LZCAS',
            style: Theme.of(context).textTheme.labelMedium?.copyWith(
              color: colorScheme.onPrimary.withValues(alpha: 0.75),
              letterSpacing: 2,
            ),
          ),
        ],
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  final String label;
  final String value;
  final ColorScheme colorScheme;
  const _InfoRow({
    required this.label,
    required this.value,
    required this.colorScheme,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 60,
          child: Text(
            label,
            style: theme.textTheme.labelMedium?.copyWith(
              color: colorScheme.onSurfaceVariant,
            ),
          ),
        ),
        Expanded(child: Text(value, style: theme.textTheme.bodyMedium)),
      ],
    );
  }
}

class _DashedDivider extends StatelessWidget {
  const _DashedDivider();

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme.outline;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: CustomPaint(
        size: const Size(double.infinity, 1),
        painter: _DashPainter(color: color),
      ),
    );
  }
}

class _DashPainter extends CustomPainter {
  final Color color;
  _DashPainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 1
      ..style = PaintingStyle.stroke;
    const dashWidth = 4.0;
    const dashGap = 3.0;
    double x = 0;
    while (x < size.width) {
      canvas.drawLine(Offset(x, 0), Offset(x + dashWidth, 0), paint);
      x += dashWidth + dashGap;
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
