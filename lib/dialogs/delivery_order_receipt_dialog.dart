// lib/dialogs/delivery_order_receipt_dialog.dart
// Receipt preview + print for an Agreed delivery order. Itemized lines use
// the cashier-set unit prices; the delivery fee is the negotiated amount and
// the final total is the locked items_total + delivery_fee.

import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:bot_toast/bot_toast.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import '../db/db.dart' show DeliveryOrder;
import '../utils/formatters.dart' show formatMoney;

class DeliveryOrderReceiptDialog extends StatefulWidget {
  final DeliveryOrder order;
  final String currencySymbol;

  const DeliveryOrderReceiptDialog({
    super.key,
    required this.order,
    this.currencySymbol = '₱',
  });

  Future<void> show(BuildContext context) {
    return showDialog<void>(context: context, builder: (_) => this);
  }

  @override
  State<DeliveryOrderReceiptDialog> createState() =>
      _DeliveryOrderReceiptDialogState();
}

class _DeliveryOrderReceiptDialogState
    extends State<DeliveryOrderReceiptDialog> {
  final _receiptKey = GlobalKey();

  String get _ref {
    final d = DateTime.now().toLocal();
    return 'DEL-${d.year}${d.month.toString().padLeft(2, '0')}'
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
      final dir = await getTemporaryDirectory();
      final file = File('${dir.path}/$_ref.png');
      await file.writeAsBytes(byteData.buffer.asUint8List());
      if (Platform.isWindows) {
        await Process.run('start', [file.path], runInShell: true);
      } else if (Platform.isMacOS) {
        await Process.run('open', [file.path]);
      } else if (Platform.isLinux) {
        await Process.run('xdg-open', [file.path]);
      }
    } catch (e) {
      if (mounted) BotToast.showText(text: 'Print failed: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final order = widget.order;
    final symbol = widget.currencySymbol;
    final fmtDate = DateFormat(
      'MMMM dd, yyyy  hh:mm a',
    ).format(DateTime.now().toLocal());

    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      contentPadding: EdgeInsets.zero,
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520),
        child: RepaintBoundary(
          key: _receiptKey,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(20),
                  color: colorScheme.primaryContainer,
                  child: Column(
                    children: [
                      Text(
                        'Delivery Order Receipt',
                        style: theme.textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'GUTVita Sales System',
                        style: theme.textTheme.bodySmall,
                      ),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(24, 20, 24, 0),
                  child: Column(
                    children: [
                      _infoRow('Date', fmtDate, theme),
                      const SizedBox(height: 6),
                      _infoRow('Ref #', _ref, theme),
                      if ((order.memberName ?? '').isNotEmpty) ...[
                        const SizedBox(height: 6),
                        _infoRow('Buyer', order.memberName!, theme),
                      ],
                      if ((order.deliveryAddress ?? '').isNotEmpty) ...[
                        const SizedBox(height: 6),
                        _infoRow('Deliver to', order.deliveryAddress!, theme),
                      ],
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                const Divider(height: 1),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: Table(
                    columnWidths: const {
                      0: FlexColumnWidth(3),
                      1: FlexColumnWidth(0.8),
                      2: FlexColumnWidth(1.6),
                      3: FlexColumnWidth(1.6),
                    },
                    children: [
                      TableRow(
                        children: [
                          _hdr('Item', theme),
                          _hdr('Qty', theme, right: true),
                          _hdr('Price', theme, right: true),
                          _hdr('Subtotal', theme, right: true),
                        ],
                      ),
                      for (final item in order.items)
                        TableRow(
                          children: [
                            _cell(item.productName ?? 'Item', theme),
                            _cell('${item.quantity}', theme, right: true),
                            _cell(
                              formatMoney(item.unitPrice, symbol: symbol),
                              theme,
                              right: true,
                            ),
                            _cell(
                              formatMoney(
                                (item.unitPrice ?? 0) * item.quantity,
                                symbol: symbol,
                              ),
                              theme,
                              right: true,
                              bold: true,
                            ),
                          ],
                        ),
                    ],
                  ),
                ),
                const Divider(height: 1),
                Padding(
                  padding: const EdgeInsets.fromLTRB(24, 16, 24, 0),
                  child: Column(
                    children: [
                      _totalRow(
                        'Items total',
                        formatMoney(order.itemsTotal, symbol: symbol),
                        theme,
                      ),
                      const SizedBox(height: 6),
                      _totalRow(
                        'Delivery fee',
                        formatMoney(order.deliveryFee, symbol: symbol),
                        theme,
                      ),
                      const SizedBox(height: 12),
                      _totalRow(
                        'FINAL TOTAL',
                        formatMoney(order.finalTotal, symbol: symbol),
                        theme,
                        bold: true,
                      ),
                      const SizedBox(height: 12),
                      Text(
                        '— Thank you for your purchase! —',
                        style: theme.textTheme.bodyMedium?.copyWith(
                          fontStyle: FontStyle.italic,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 20),
                Padding(
                  padding: const EdgeInsets.fromLTRB(24, 0, 24, 20),
                  child: Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: _print,
                          icon: const Icon(Icons.print_outlined, size: 20),
                          label: const Text('Print'),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: FilledButton.icon(
                          onPressed: () => Navigator.pop(context),
                          icon: const Icon(
                            Icons.check_circle_outline,
                            size: 20,
                          ),
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

  Widget _hdr(String text, ThemeData theme, {bool right = false}) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 8),
    child: Text(
      text,
      textAlign: right ? TextAlign.right : TextAlign.left,
      style: theme.textTheme.labelMedium?.copyWith(fontWeight: FontWeight.w700),
    ),
  );

  Widget _cell(
    String text,
    ThemeData theme, {
    bool right = false,
    bool bold = false,
  }) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 8),
    child: Text(
      text,
      textAlign: right ? TextAlign.right : TextAlign.left,
      style: theme.textTheme.bodyMedium?.copyWith(
        fontWeight: bold ? FontWeight.w700 : FontWeight.w400,
      ),
    ),
  );

  Widget _infoRow(String label, String value, ThemeData theme) => Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      SizedBox(
        width: 90,
        child: Text(
          label,
          style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ),
      Expanded(child: Text(value, style: theme.textTheme.bodyMedium)),
    ],
  );

  Widget _totalRow(
    String label,
    String value,
    ThemeData theme, {
    bool bold = false,
  }) => Row(
    mainAxisAlignment: MainAxisAlignment.spaceBetween,
    children: [
      Text(
        label,
        style: theme.textTheme.titleMedium?.copyWith(
          fontWeight: bold ? FontWeight.w800 : FontWeight.w500,
        ),
      ),
      Text(
        value,
        style: theme.textTheme.titleMedium?.copyWith(
          fontWeight: bold ? FontWeight.w800 : FontWeight.w600,
        ),
      ),
    ],
  );
}
