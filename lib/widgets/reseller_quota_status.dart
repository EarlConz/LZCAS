// lib/widgets/reseller_quota_status.dart
// Reseller-facing quota status widget — visual countdown with progress bar,
// showing days remaining to meet the weekly box remittance quota.

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/quota_service.dart';
import '../theme.dart';
import '../utils/fonts.dart';

class ResellerQuotaStatus extends StatefulWidget {
  final int memberId;

  const ResellerQuotaStatus({super.key, required this.memberId});

  @override
  State<ResellerQuotaStatus> createState() => _ResellerQuotaStatusState();
}

class _ResellerQuotaStatusState extends State<ResellerQuotaStatus> {
  late final QuotaProvider _quota;

  @override
  void initState() {
    super.initState();
    _quota = QuotaProvider();
    _quota.subscribe(widget.memberId);
  }

  @override
  void dispose() {
    _quota.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider<QuotaProvider>.value(
      value: _quota,
      child: Consumer<QuotaProvider>(
        builder: (context, quota, _) {
          if (quota.loading) {
            return const _QuotaCardSkeleton();
          }

          if (quota.error != null) {
            return _buildErrorCard(quota.error!);
          }

          if (!quota.hasQuota) {
            return _buildNoQuotaCard();
          }

          final days = quota.daysRemaining;
          final fraction = quota.quotaFraction;

          if (days > 7) {
            return _buildSafeCard(quota);
          }

          if (days >= 0) {
            return _buildCountdownCard(quota, fraction);
          }

          return _buildOverdueCard(quota);
        },
      ),
    );
  }

  Widget _buildNoQuotaCard() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(
          color: isDark ? StockpileColors.darkDivider : StockpileColors.divider,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: StockpileColors.secondary500.withAlpha(25),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(
                Icons.info_outline,
                color: StockpileColors.secondary500,
                size: 32,
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'No Quota Set',
                    style: StockpileFonts.satoshi(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      color: isDark
                          ? StockpileColors.darkTextPrimary
                          : StockpileColors.darkText,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Remit boxes to activate your weekly quota.',
                    style: StockpileFonts.satoshi(
                      fontSize: 13,
                      color: isDark
                          ? StockpileColors.darkTextMuted
                          : StockpileColors.bodyText,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSafeCard(QuotaProvider quota) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: StockpileColors.success.withAlpha(80)),
      ),
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          gradient: LinearGradient(
            colors: [
              StockpileColors.success.withAlpha(isDark ? 25 : 20),
              StockpileColors.success.withAlpha(isDark ? 10 : 6),
            ],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            Row(
              children: [
                // Badge
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [StockpileColors.success, Color(0xFF16A34A)],
                    ),
                    borderRadius: BorderRadius.circular(14),
                    boxShadow: [
                      BoxShadow(
                        color: StockpileColors.success.withAlpha(60),
                        blurRadius: 12,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: const Icon(
                    Icons.check_rounded,
                    color: Colors.white,
                    size: 28,
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Quota Met',
                        style: StockpileFonts.satoshi(
                          fontSize: 18,
                          fontWeight: FontWeight.w800,
                          color: StockpileColors.success,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'Your weekly box remittance is up to date.',
                        style: StockpileFonts.satoshi(
                          fontSize: 13,
                          color: isDark
                              ? StockpileColors.darkTextMuted
                              : StockpileColors.bodyText,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            // Days remaining pill
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 12),
              decoration: BoxDecoration(
                color: StockpileColors.success.withAlpha(isDark ? 20 : 15),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.schedule_rounded,
                    size: 18,
                    color: StockpileColors.success,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    quota.daysHoursLabel,
                    style: StockpileFonts.satoshi(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: StockpileColors.success,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCountdownCard(QuotaProvider quota, double fraction) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final days = quota.daysRemaining;
    final color = days <= 1
        ? StockpileColors.danger
        : days <= 3
        ? StockpileColors.primary900
        : StockpileColors.secondary500;

    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: color.withAlpha(60)),
      ),
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          gradient: LinearGradient(
            colors: [
              color.withAlpha(isDark ? 20 : 14),
              color.withAlpha(isDark ? 8 : 4),
            ],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                // Gradient icon badge
                Container(
                  width: 46,
                  height: 46,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [color, color.withBlue((color.blue + 40).clamp(0, 255))],
                    ),
                    borderRadius: BorderRadius.circular(13),
                    boxShadow: [
                      BoxShadow(
                        color: color.withAlpha(50),
                        blurRadius: 10,
                        offset: const Offset(0, 3),
                      ),
                    ],
                  ),
                  child: const Icon(Icons.timer_outlined, color: Colors.white, size: 26),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Weekly Quota',
                        style: StockpileFonts.satoshi(
                          fontSize: 16,
                          fontWeight: FontWeight.w800,
                          color: isDark
                              ? StockpileColors.darkTextPrimary
                              : StockpileColors.darkText,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'Remit boxes to extend your compliance status',
                        style: StockpileFonts.satoshi(
                          fontSize: 12,
                          color: isDark
                              ? StockpileColors.darkTextMuted
                              : StockpileColors.mutedText,
                        ),
                      ),
                    ],
                  ),
                ),
                _dayBadge(quota),
              ],
            ),
            const SizedBox(height: 18),
            // Progress bar with percentage label
            Row(
              children: [
                Expanded(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(5),
                    child: LinearProgressIndicator(
                      value: fraction,
                      minHeight: 8,
                      backgroundColor: color.withAlpha(35),
                      valueColor: AlwaysStoppedAnimation(color),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Text(
                  '${(fraction * 100).round()}%',
                  style: StockpileFonts.satoshi(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: color,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            // Bottom row
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: color.withAlpha(isDark ? 25 : 18),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    quota.daysHoursLabel,
                    style: StockpileFonts.satoshi(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: color,
                    ),
                  ),
                ),
                const Spacer(),
                Icon(Icons.calendar_today, size: 12, color: isDark ? StockpileColors.darkTextMuted : StockpileColors.mutedText),
                const SizedBox(width: 4),
                Text(
                  _quota.quotaValidUntil != null ? _formatDate(_quota.quotaValidUntil!) : '—',
                  style: StockpileFonts.satoshi(
                    fontSize: 11,
                    color: isDark ? StockpileColors.darkTextMuted : StockpileColors.mutedText,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildOverdueCard(QuotaProvider quota) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    const color = StockpileColors.danger;

    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: color.withAlpha(100)),
      ),
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          gradient: LinearGradient(
            colors: [
              color.withAlpha(isDark ? 28 : 20),
              color.withAlpha(isDark ? 12 : 6),
            ],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                // Pulsing danger badge
                Container(
                  width: 46,
                  height: 46,
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [StockpileColors.danger, StockpileColors.error700],
                    ),
                    borderRadius: BorderRadius.circular(13),
                    boxShadow: [
                      BoxShadow(
                        color: color.withAlpha(70),
                        blurRadius: 14,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: const Icon(Icons.warning_rounded, color: Colors.white, size: 26),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Quota Overdue',
                        style: StockpileFonts.satoshi(
                          fontSize: 18,
                          fontWeight: FontWeight.w800,
                          color: color,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'Your status is at risk — remit a box to reactivate.',
                        style: StockpileFonts.satoshi(
                          fontSize: 12,
                          color: isDark ? StockpileColors.darkTextMuted : StockpileColors.bodyText,
                        ),
                      ),
                    ],
                  ),
                ),
                _dayBadge(quota, isOverdue: true),
              ],
            ),
            const SizedBox(height: 18),
            // Action button
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: () {},
                icon: const Icon(Icons.shopping_cart_rounded, size: 20),
                label: const Text('Remit a Box Now'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: color,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  elevation: 0,
                ),
              ),
            ),
            const SizedBox(height: 10),
            // Info footer
            Row(
              children: [
                Icon(Icons.info_outline, size: 13, color: color.withAlpha(150)),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    'Remitting even 1 box automatically restores your active '
                    'reseller status and clears this warning.',
                    style: StockpileFonts.satoshi(
                      fontSize: 11,
                      color: isDark ? StockpileColors.darkTextMuted : StockpileColors.mutedText,
                    ).copyWith(fontStyle: FontStyle.italic),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildErrorCard(String error) {
    return Card(
      elevation: 0,
      color: StockpileColors.dangerBg.withAlpha(100),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            const Icon(Icons.error_outline, color: StockpileColors.danger),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                error,
                style: StockpileFonts.satoshi(
                  color: StockpileColors.danger,
                  fontSize: 13,
                ),
              ),
            ),
            TextButton(
              onPressed: () => _quota.subscribe(widget.memberId),
              child: const Text('Retry'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _dayBadge(QuotaProvider quota, {bool isOverdue = false}) {
    final color = isOverdue
        ? StockpileColors.danger
        : quota.daysRemaining <= 1
            ? StockpileColors.danger
            : quota.daysRemaining <= 3
                ? StockpileColors.primary900
                : StockpileColors.secondary500;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color: color.withAlpha(25),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withAlpha(60)),
      ),
      child: Text(
        isOverdue ? '-${quota.daysHoursLabel}' : quota.daysHoursLabel,
        style: StockpileFonts.satoshi(
          fontSize: 18,
          fontWeight: FontWeight.w800,
          color: color,
        ),
      ),
    );
  }

  String _formatDate(DateTime dt) {
    return '${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')}';
  }
}

class _QuotaCardSkeleton extends StatelessWidget {
  const _QuotaCardSkeleton();

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(
          color: isDark ? StockpileColors.darkDivider : StockpileColors.divider,
        ),
      ),
      child: const Padding(
        padding: EdgeInsets.all(20),
        child: Center(
          child: SizedBox(
            width: 24,
            height: 24,
            child: CircularProgressIndicator(strokeWidth: 2.5),
          ),
        ),
      ),
    );
  }
}
