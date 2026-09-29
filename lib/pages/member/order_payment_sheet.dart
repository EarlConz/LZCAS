// lib/pages/member/order_payment_sheet.dart
//
// How a member pays for an agreed delivery order (v52, plan §7).
//
// The choice is offered at Agreed, not at checkout, because until both
// sides have settled the delivery fee there is no total to pay.
//
// Two ways:
//   Funds — deducted from Balance or Total Earnings, the same two buckets
//           withdrawals already use, so the member's mental model of "where
//           my money lives" does not change. The database refuses if the
//           bucket does not cover the total, and its message names both
//           figures, so it is shown verbatim rather than replaced.
//   Cash  — the member shows a single-use code; the rider scans it at
//           handover. That one scan is both the receipt confirmation and
//           the payment record, which is why there is no separate "I paid"
//           button anywhere.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:bot_toast/bot_toast.dart';

import '../../db/db.dart';
import '../../theme.dart';
import '../../utils/fonts.dart';
import '../../utils/formatters.dart' show formatMoney;
import '../../widgets/qr_code_view.dart';

/// Returns true when something changed and the caller should reload.
Future<bool> showOrderPaymentSheet(
  BuildContext context, {
  required DeliveryOrder order,
  required String currencySymbol,
}) async {
  final changed = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) =>
        _PaymentSheet(order: order, currencySymbol: currencySymbol),
  );
  return changed ?? false;
}

class _PaymentSheet extends StatefulWidget {
  final DeliveryOrder order;
  final String currencySymbol;

  const _PaymentSheet({required this.order, required this.currencySymbol});

  @override
  State<_PaymentSheet> createState() => _PaymentSheetState();
}

class _PaymentSheetState extends State<_PaymentSheet> {
  Map<String, int>? _funds;
  bool _loading = true;
  bool _busy = false;

  /// Non-null once the member has asked for their cash code, which is also
  /// what marks the order as CoD.
  String? _codCode;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final memberId = widget.order.memberId;
    Map<String, int>? funds;
    if (memberId != null) {
      try {
        funds = await repository.fetchMemberEarningsBreakdown(memberId);
      } catch (_) {
        // Leave it null: the funds option then says it cannot read the
        // balance rather than offering a figure it does not have.
      }
    }
    if (!mounted) return;
    setState(() {
      _funds = funds;
      _loading = false;
    });
    // An order already marked CoD reopens straight onto its code: the
    // member came back to show it, not to choose again.
    if (widget.order.isCod && !widget.order.isPaid) await _showCode();
  }

  double get _total => widget.order.finalTotal ?? 0;

  Future<void> _payWithFunds(String bucket) async {
    setState(() => _busy = true);
    final error = await repository.payOrderWithFunds(
      orderId: widget.order.id,
      sourceBucket: bucket,
    );
    if (!mounted) return;
    setState(() => _busy = false);
    if (error != null) {
      // Shown as the database phrased it: it names what is available and
      // what is needed, which is more use than "payment failed".
      BotToast.showText(text: error, duration: const Duration(seconds: 5));
      return;
    }
    Navigator.pop(context, true);
    BotToast.showText(text: 'Paid ${formatMoney(_total, symbol: widget.currencySymbol)} from your funds');
  }

  Future<void> _showCode() async {
    setState(() => _busy = true);
    final code = await repository.memberOrderCodCode(widget.order.id);
    if (!mounted) return;
    setState(() {
      _busy = false;
      _codCode = code;
    });
    if (code == null) {
      BotToast.showText(
        text: 'Could not get your cash code. Please try again.',
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final surface = isDark
        ? StockpileColors.darkSurface
        : StockpileColors.surface;
    final text = isDark
        ? StockpileColors.darkTextPrimary
        : StockpileColors.darkText;
    final muted = isDark
        ? StockpileColors.darkTextMuted
        : StockpileColors.mutedText;

    return SafeArea(
      top: false,
      child: Container(
        margin: const EdgeInsets.all(12),
        padding: const EdgeInsets.fromLTRB(20, 14, 20, 20),
        decoration: BoxDecoration(
          color: surface,
          borderRadius: BorderRadius.circular(20),
        ),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: 16),
                  decoration: BoxDecoration(
                    color: muted.withAlpha(60),
                    borderRadius: BorderRadius.circular(100),
                  ),
                ),
              ),
              Text(
                _codCode == null ? 'How would you like to pay?' : 'Show this to your rider',
                style: StockpileFonts.satoshi(
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  color: text,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                _codCode == null
                    ? 'Total to pay: ${formatMoney(_total, symbol: widget.currencySymbol)}'
                    : 'They scan it when they hand your order over. That '
                          'one scan confirms you received it and records '
                          'the payment.',
                style: StockpileFonts.satoshi(fontSize: 13, color: muted),
              ),
              const SizedBox(height: 18),
              if (_loading)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 40),
                  child: Center(child: CircularProgressIndicator()),
                )
              else if (_codCode != null)
                _codeView(text, muted)
              else
                ..._choices(isDark, text, muted),
            ],
          ),
        ),
      ),
    );
  }

  // ── The cash code ──────────────────────────────────────────────────
  Widget _codeView(Color text, Color muted) {
    final code = _codCode!;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Center(child: QrCodeView(data: code, size: 220)),
        const SizedBox(height: 14),
        // The digits are the fallback for a cracked screen or a camera that
        // will not focus: the rider can type them instead of scanning.
        Center(
          child: SelectableText(
            code,
            textAlign: TextAlign.center,
            style: StockpileFonts.satoshi(
              fontSize: 12,
              color: muted,
              letterSpacing: 0.5,
            ),
          ),
        ),
        const SizedBox(height: 6),
        Center(
          child: TextButton.icon(
            onPressed: () {
              Clipboard.setData(ClipboardData(text: code));
              BotToast.showText(text: 'Code copied');
            },
            icon: const Icon(Icons.copy_rounded, size: 16),
            label: const Text('Copy code'),
          ),
        ),
        const SizedBox(height: 10),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: StockpileColors.primary50,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Icon(
                Icons.payments_rounded,
                size: 18,
                color: StockpileColors.primary900,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Have ${formatMoney(_total, symbol: widget.currencySymbol)} '
                  'ready in cash.',
                  style: StockpileFonts.satoshi(fontSize: 13, color: text),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        TextButton(
          onPressed: () => Navigator.pop(context, true),
          child: const Text('Done'),
        ),
      ],
    );
  }

  // ── The two choices ────────────────────────────────────────────────
  List<Widget> _choices(bool isDark, Color text, Color muted) {
    final balance = _funds?['balance'];
    final earnings = _funds?['totalEarnings'];

    return [
      _optionCard(
        isDark: isDark,
        text: text,
        muted: muted,
        icon: Icons.savings_rounded,
        title: 'Pay from Balance',
        subtitle: balance == null
            ? 'Could not read your balance right now'
            : 'You have ${formatMoney(balance, symbol: widget.currencySymbol)}',
        // Offered even when it looks short: the database is the authority on
        // what is available, and its refusal explains itself better than a
        // greyed-out row that says nothing.
        enabled: !_busy && balance != null,
        onTap: () => _payWithFunds('balance'),
      ),
      const SizedBox(height: 10),
      _optionCard(
        isDark: isDark,
        text: text,
        muted: muted,
        icon: Icons.account_balance_wallet_rounded,
        title: 'Pay from Total Earnings',
        subtitle: earnings == null
            ? 'Could not read your earnings right now'
            : 'You have ${formatMoney(earnings, symbol: widget.currencySymbol)}',
        enabled: !_busy && earnings != null,
        onTap: () => _payWithFunds('total_earnings'),
      ),
      const SizedBox(height: 10),
      _optionCard(
        isDark: isDark,
        text: text,
        muted: muted,
        icon: Icons.local_atm_rounded,
        title: 'Cash on delivery',
        subtitle: 'Pay the rider when your order arrives',
        enabled: !_busy,
        onTap: _showCode,
      ),
      if (_busy) ...[
        const SizedBox(height: 16),
        const Center(child: CircularProgressIndicator()),
      ],
    ];
  }

  Widget _optionCard({
    required bool isDark,
    required Color text,
    required Color muted,
    required IconData icon,
    required String title,
    required String subtitle,
    required bool enabled,
    required VoidCallback onTap,
  }) {
    return Opacity(
      opacity: enabled ? 1 : 0.5,
      child: InkWell(
        onTap: enabled ? onTap : null,
        borderRadius: BorderRadius.circular(14),
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: isDark
                  ? StockpileColors.darkDivider
                  : StockpileColors.divider,
            ),
          ),
          child: Row(
            children: [
              Icon(icon, size: 22, color: StockpileColors.primary900),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: StockpileFonts.satoshi(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: text,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: StockpileFonts.satoshi(
                        fontSize: 12,
                        color: muted,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(Icons.chevron_right_rounded, size: 20, color: muted),
            ],
          ),
        ),
      ),
    );
  }
}
