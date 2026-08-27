import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import 'package:lzcas/db/db.dart';
import 'package:lzcas/services/config_service.dart';
import 'package:lzcas/theme.dart';
import 'package:lzcas/utils/animations.dart';
import 'package:lzcas/utils/toast_utils.dart';

/// Admin-only correction of a member's earned funds.
///
/// Nothing here edits an existing credit. Posting an adjustment appends a
/// signed row to the frozen ledger whose `item_name` keeps the bucket's
/// prefix, so the totals move on their own and the original credits stay
/// intact and reconcilable (migration v35).
///
/// Returns true when an adjustment was posted, so the caller can refresh.
Future<bool> showAdjustFundsDialog(
  BuildContext context, {
  required int memberId,
  required String memberName,
}) async {
  final result = await showAnimatedDialog<bool>(
    context,
    builder: (ctx) =>
        _AdjustFundsDialog(memberId: memberId, memberName: memberName),
  );
  return result ?? false;
}

class _AdjustFundsDialog extends StatefulWidget {
  final int memberId;
  final String memberName;

  const _AdjustFundsDialog({required this.memberId, required this.memberName});

  @override
  State<_AdjustFundsDialog> createState() => _AdjustFundsDialogState();
}

class _AdjustFundsDialogState extends State<_AdjustFundsDialog> {
  final _amountController = TextEditingController();
  final _reasonController = TextEditingController();

  /// Matches the server's cap, which truncates the reason before writing it
  /// into `item_name` — better to stop the admin at the limit than to let
  /// them type text that silently disappears.
  static const _reasonMaxLength = 120;

  EarningsBucket _bucket = EarningsBucket.directReferral;
  bool _isDeduction = true;
  bool _loading = true;
  bool _submitting = false;

  Map<EarningsBucket, int> _totals = const {};

  /// The wallet figures the member actually sees. Empty when the lookup
  /// failed — see [_walletBefore].
  Map<String, int> _wallets = const {};

  @override
  void initState() {
    super.initState();
    _amountController.addListener(_onInputChanged);
    _reasonController.addListener(_onInputChanged);
    _loadTotals();
  }

  @override
  void dispose() {
    _amountController.dispose();
    _reasonController.dispose();
    super.dispose();
  }

  void _onInputChanged() => setState(() {});

  /// The design system's muted tone.
  ///
  /// Flutter's own `theme.hintColor` is black at 38% (≈ #9E9E9E) and sits a
  /// shade off the system's #8E8E9A — close enough that using both on the
  /// same row reads as an accident rather than a distinction.
  Color _muted(ThemeData theme) => theme.brightness == Brightness.dark
      ? StockpileColors.darkTextMuted
      : StockpileColors.mutedText;

  Future<void> _loadTotals() async {
    // Two different views of the same ledger, and the second cannot be
    // derived from the first: the buckets are GROSS sums (what the
    // below-zero guard compares against), while the wallets are net of
    // approved withdrawals (what the member is shown). Started together so
    // they overlap rather than queue.
    final bucketsFuture = repository.fetchMemberFundBuckets(widget.memberId);
    final walletsFuture = repository
        .fetchMemberEarningsBreakdown(widget.memberId)
        // The wallet figures are a courtesy — losing them costs one line of
        // the preview, so they must never take the whole dialog down with
        // them (unlike the buckets, which the guard depends on).
        .catchError((Object e) {
          debugPrint('[AdjustFunds] wallet lookup failed: $e');
          return <String, int>{};
        });

    final buckets = await bucketsFuture;
    final wallets = await walletsFuture;
    if (!mounted) return;
    setState(() {
      _totals = buckets;
      _wallets = wallets;
      _loading = false;
    });
  }

  int get _currentBucketTotal => _totals[_bucket] ?? 0;

  /// Which wallet this bucket feeds. Direct Referral pays Balance; every
  /// other bucket feeds Total Earnings (v24's split).
  String get _walletLabel => _bucket.isBalance ? 'Balance' : 'Total Earnings';

  /// The wallet's current figure, or null when the lookup failed — in which
  /// case the preview drops that tier rather than showing a fabricated zero.
  int? get _walletBefore =>
      _wallets[_bucket.isBalance ? 'balance' : 'totalEarnings'];

  /// Where the wallet lands. `get_member_earnings` floors its wallets at 0,
  /// so this mirrors that. Exact whenever the current figure is above zero,
  /// which is every case that isn't a member who has already withdrawn
  /// everything.
  int get _walletAfter {
    final after = (_walletBefore ?? 0) + _signedAmount;
    return after < 0 ? 0 : after;
  }

  /// The signed change, as the RPC expects it.
  int get _signedAmount {
    final magnitude = int.tryParse(_amountController.text.trim()) ?? 0;
    return _isDeduction ? -magnitude : magnitude;
  }

  int get _projectedTotal => _currentBucketTotal + _signedAmount;

  /// Why the form can't be submitted yet, or null when it can. Mirrors the
  /// server's checks so the admin is told before the round trip — the RPC
  /// still enforces every one of them.
  String? get _blocker {
    if (_loading) return null;
    if (_signedAmount == 0) return null; // nothing typed yet — not an error
    if (_reasonController.text.trim().length < 3) return null;
    if (_projectedTotal < 0) {
      final cs = context.read<ConfigService>().currencySymbol;
      return '${_bucket.label} is only $cs$_currentBucketTotal — '
          'deducting $cs${_signedAmount.abs()} would leave it below zero.';
    }
    return null;
  }

  bool get _canSubmit =>
      !_loading &&
      !_submitting &&
      _signedAmount != 0 &&
      _reasonController.text.trim().length >= 3 &&
      _projectedTotal >= 0;

  Future<void> _submit() async {
    if (!_canSubmit) return;
    setState(() => _submitting = true);

    final error = await repository.adjustMemberFunds(
      memberId: widget.memberId,
      bucket: _bucket,
      amount: _signedAmount,
      reason: _reasonController.text.trim(),
    );

    if (!mounted) return;

    if (error != null) {
      setState(() => _submitting = false);
      showErrorToast(error);
      return;
    }

    final cs = context.read<ConfigService>().currencySymbol;
    final verb = _isDeduction ? 'Deducted' : 'Added';
    showSuccessToast(
      '$verb $cs${_signedAmount.abs()} '
      '${_isDeduction ? 'from' : 'to'} ${_bucket.label}',
    );
    Navigator.pop(context, true);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final isNarrow = MediaQuery.sizeOf(context).width < 500;
    final cs = context.watch<ConfigService>().currencySymbol;
    final accent = _isDeduction
        ? StockpileColors.danger
        : StockpileColors.success;

    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      titlePadding: const EdgeInsets.fromLTRB(24, 22, 24, 0),
      contentPadding: const EdgeInsets.fromLTRB(24, 16, 24, 8),
      title: Row(
        children: [
          Icon(
            Icons.account_balance_wallet_outlined,
            color: colorScheme.primary,
            size: 28,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'Adjust Funds',
                  style: theme.textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                Text(
                  widget.memberName,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: _muted(theme),
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ],
      ),
      // The form is shown immediately, never behind a spinner. Only the
      // figures depend on the fetch, so gating the whole dialog on it would
      // resize the modal the moment the totals landed — and would stop the
      // admin typing the reason for no reason. Submission stays blocked until
      // the totals are in (see _canSubmit), because the below-zero check
      // needs them.
      content: SizedBox(
        width: isNarrow ? double.maxFinite : 480,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildBucketPicker(theme, cs),
              const SizedBox(height: 16),
              _buildDirectionTiles(theme),
              const SizedBox(height: 16),
              _buildAmountField(theme, accent, cs),
              const SizedBox(height: 16),
              _buildReasonField(theme),
              const SizedBox(height: 14),
              _buildPreview(theme, accent, cs),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _submitting ? null : () => Navigator.pop(context, false),
          child: const Text('Cancel'),
        ),
        FilledButton.icon(
          onPressed: _canSubmit ? _submit : null,
          icon: _submitting
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : Icon(
                  _isDeduction ? Icons.remove_rounded : Icons.add_rounded,
                  size: 18,
                ),
          label: Text(_isDeduction ? 'Post Deduction' : 'Post Addition'),
          style: FilledButton.styleFrom(backgroundColor: accent),
        ),
      ],
    );
  }

  Widget _buildBucketPicker(ThemeData theme, String cs) {
    return DropdownButtonFormField<EarningsBucket>(
      isExpanded: true,
      initialValue: _bucket,
      decoration: const InputDecoration(
        labelText: 'Which earnings',
        helperText: 'Only this type changes — the rest are untouched.',
      ),
      items: [
        for (final b in EarningsBucket.adjustable)
          DropdownMenuItem(
            value: b,
            child: Row(
              children: [
                Expanded(child: Text(b.label)),
                const SizedBox(width: 8),
                // Shimmer only the figure — the label is known up front, so
                // the row keeps its shape and nothing shifts when the total
                // arrives.
                if (_loading)
                  const SkeletonBlock(width: 44, height: 12, borderRadius: 6)
                else
                  Text(
                    '$cs${_totals[b] ?? 0}',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                      color: _muted(theme),
                    ),
                  ),
              ],
            ),
          ),
      ],
      onChanged: _submitting
          ? null
          : (v) => setState(() => _bucket = v ?? _bucket),
    );
  }

  /// The direction choice, on its own row as two large tiles.
  ///
  /// Deliberately NOT a SegmentedButton. That control's selected fill is
  /// Material's seed-derived `secondaryContainer` — the same amber for both
  /// options — so nothing but the fill's *position* told you which way the
  /// money was moving. These carry the red/green the preview and the submit
  /// button already use, and at 52px they clear a comfortable target size
  /// for a screen that moves real balances.
  Widget _buildDirectionTiles(ThemeData theme) {
    return Row(
      children: [
        Expanded(
          child: _directionTile(
            theme,
            label: 'Deduct',
            icon: Icons.remove_rounded,
            color: StockpileColors.danger,
            containerColor: StockpileColors.dangerBg,
            selected: _isDeduction,
            onTap: () => setState(() => _isDeduction = true),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _directionTile(
            theme,
            label: 'Add',
            icon: Icons.add_rounded,
            color: StockpileColors.success,
            containerColor: StockpileColors.successBg,
            selected: !_isDeduction,
            onTap: () => setState(() => _isDeduction = false),
          ),
        ),
      ],
    );
  }

  Widget _directionTile(
    ThemeData theme, {
    required String label,
    required IconData icon,
    required Color color,
    required Color containerColor,
    required bool selected,
    required VoidCallback onTap,
  }) {
    final isDark = theme.brightness == Brightness.dark;
    final idleFill = isDark
        ? StockpileColors.darkInputBg
        : StockpileColors.inputBg;
    final idleBorder = isDark
        ? StockpileColors.darkDivider
        : StockpileColors.divider;
    final idleText = _muted(theme);

    // dangerBg / successBg are light-mode tints and glare on the dark
    // surface, so dark mode derives its fill from the accent instead.
    final fill = selected
        ? (isDark ? color.withValues(alpha: 0.18) : containerColor)
        : idleFill;
    final foreground = selected ? color : idleText;
    final radius = BorderRadius.circular(12);

    return Material(
      color: fill,
      borderRadius: radius,
      child: InkWell(
        onTap: _submitting ? null : onTap,
        borderRadius: radius,
        child: Container(
          height: 52,
          decoration: BoxDecoration(
            borderRadius: radius,
            border: Border.all(
              color: selected ? color : idleBorder,
              width: selected ? 1.5 : 1,
            ),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 18, color: foreground),
              const SizedBox(width: 8),
              Text(
                label,
                style: theme.textTheme.labelLarge?.copyWith(
                  color: foreground,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildAmountField(ThemeData theme, Color accent, String cs) {
    final numberStyle = theme.textTheme.headlineSmall?.copyWith(
      fontSize: 24,
      fontWeight: FontWeight.w700,
      height: 1.2,
    );

    return TextField(
      controller: _amountController,
      enabled: !_submitting,
      keyboardType: TextInputType.number,
      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
      decoration: InputDecoration(
        labelText: 'Amount',
        // A signed prefix, so the figure itself carries the direction. The
        // tiles above state it once; this repeats it where the eye actually
        // lands when checking the number.
        prefixText: '${_isDeduction ? '−' : '+'}$cs',
        prefixStyle: numberStyle?.copyWith(color: accent),
        // Trimmed from the theme's 16 because the figure is 24px here — the
        // default padding would leave the field noticeably taller than the
        // others in the same column.
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 18,
          vertical: 14,
        ),
      ),
      style: numberStyle,
    );
  }

  Widget _buildReasonField(ThemeData theme) {
    return TextField(
      controller: _reasonController,
      enabled: !_submitting,
      maxLength: _reasonMaxLength,
      maxLines: 2,
      textCapitalization: TextCapitalization.sentences,
      decoration: const InputDecoration(
        labelText: 'Reason (required)',
        hintText: 'e.g. Duplicate referral reversed',
        // The reason is stored in the ledger row's name, which is exactly
        // what the member's earnings breakdown renders. Say so plainly —
        // an admin writing an internal note here would be publishing it.
        helperText: 'The member will see this in their earnings breakdown.',
        helperMaxLines: 2,
      ),
    );
  }

  Widget _buildPreview(ThemeData theme, Color accent, String cs) {
    final blocker = _blocker;
    if (blocker != null) {
      return _banner(
        theme,
        icon: Icons.error_outline_rounded,
        color: StockpileColors.danger,
        text: blocker,
      );
    }

    // Until the totals land there is nothing truthful to project — a
    // "before → after" built on a zero current figure would be wrong. The
    // standing note is true either way, so it holds the space meanwhile.
    if (_loading || _signedAmount == 0) {
      return _banner(
        theme,
        icon: Icons.info_outline_rounded,
        color: _muted(theme),
        text:
            'This is recorded as a correction, not a withdrawal. '
            'The original earnings stay in the member’s history.',
      );
    }

    final signedText =
        '${_signedAmount < 0 ? '−' : '+'}$cs${_signedAmount.abs()}';
    final walletBefore = _walletBefore;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      decoration: BoxDecoration(
        color: accent.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: accent.withValues(alpha: 0.30)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Tier one — the bucket being changed. Loudest thing in the box,
          // because it is the figure the admin is actually setting.
          _previewTier(
            theme,
            label: _bucket.label,
            before: _currentBucketTotal,
            after: _projectedTotal,
            cs: cs,
            accent: accent,
            emphatic: true,
            // The amount, restated. It is the value most easily mistyped
            // (50 vs 500) and this box is the last thing before a live
            // ledger write — leaving the admin to subtract for it would
            // make the check weaker than the risk.
            trailing: Text(
              signedText,
              style: TextStyle(
                fontSize: 13,
                height: 1.3,
                fontWeight: FontWeight.w800,
                color: accent,
              ),
            ),
          ),

          // Tier two — where the member's wallet lands. Dropped entirely
          // rather than guessed when the lookup failed; a fabricated zero
          // here would read as "you are about to wipe them out".
          if (walletBefore != null) ...[
            const SizedBox(height: 14),
            Container(height: 1, color: accent.withValues(alpha: 0.22)),
            const SizedBox(height: 14),
            _previewTier(
              theme,
              label: _walletLabel,
              before: walletBefore,
              after: _walletAfter,
              cs: cs,
              accent: accent,
              emphatic: false,
            ),
          ] else ...[
            const SizedBox(height: 6),
            Text(
              'Their $_walletLabel moves by $signedText.',
              style: theme.textTheme.bodySmall?.copyWith(color: _muted(theme)),
            ),
          ],
        ],
      ),
    );
  }

  /// One "before → after" tier of the changes box.
  ///
  /// The bucket and the wallet are genuinely different quantities, so they
  /// get the same structure at two weights rather than one being narrated in
  /// prose — the old box showed the bucket's figures and then talked about
  /// the wallet, leaving the admin no way to see where the member landed.
  Widget _previewTier(
    ThemeData theme, {
    required String label,
    required int before,
    required int after,
    required String cs,
    required Color accent,
    required bool emphatic,
    Widget? trailing,
  }) {
    final muted = _muted(theme);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                label.toUpperCase(),
                style: TextStyle(
                  fontSize: 11,
                  height: 1.3,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.7,
                  color: muted,
                ),
              ),
            ),
            if (trailing != null) trailing,
          ],
        ),
        const SizedBox(height: 3),
        Row(
          children: [
            Text(
              '$cs$before',
              style: TextStyle(
                fontSize: emphatic ? 20 : 16,
                height: 1.3,
                color: muted,
              ),
            ),
            const SizedBox(width: 10),
            Icon(
              Icons.arrow_forward_rounded,
              size: emphatic ? 14 : 12,
              color: emphatic ? accent : muted,
            ),
            const SizedBox(width: 10),
            Flexible(
              child: Text(
                '$cs$after',
                style: TextStyle(
                  fontSize: emphatic ? 26 : 18,
                  height: 1.2,
                  fontWeight: emphatic ? FontWeight.w800 : FontWeight.w700,
                  color: emphatic ? accent : theme.colorScheme.onSurface,
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _banner(
    ThemeData theme, {
    required IconData icon,
    required Color color,
    required String text,
  }) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: color),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: theme.textTheme.bodySmall?.copyWith(color: color),
            ),
          ),
        ],
      ),
    );
  }
}
