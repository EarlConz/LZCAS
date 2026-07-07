// lib/widgets/quota_compliance_queue.dart
// Admin Quota Compliance Queue — displays delinquent resellers in a
// clean data table with days-overdue, last remittance, and action buttons.

import 'package:flutter/material.dart';
import '../data/models.dart';
import '../db/db.dart';
import '../theme.dart';
import '../utils/fonts.dart';

class QuotaComplianceQueue extends StatefulWidget {
  const QuotaComplianceQueue({super.key});

  @override
  State<QuotaComplianceQueue> createState() => _QuotaComplianceQueueState();
}

class _QuotaComplianceQueueState extends State<QuotaComplianceQueue> {
  List<Map<String, dynamic>> _delinquents = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final rows = await repository.fetchQuotaDelinquentMembers();
      if (!mounted) return;
      setState(() {
        _delinquents = rows;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = 'Failed to load compliance data';
        _loading = false;
      });
    }
  }

  Future<void> _snooze(int alertId) async {
    await repository.snoozeQuotaAlert(alertId, hours: 24);
    await _load();
  }

  Future<void> _dismiss(int alertId) async {
    await repository.dismissQuotaAlert(alertId);
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final colorScheme = Theme.of(context).colorScheme;

    if (_loading) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(32),
          child: CircularProgressIndicator(),
        ),
      );
    }

    if (_error != null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.error_outline, size: 40, color: colorScheme.error),
            const SizedBox(height: 12),
            Text(
              _error!,
              style: StockpileFonts.satoshi(color: colorScheme.error),
            ),
            const SizedBox(height: 12),
            OutlinedButton(onPressed: _load, child: const Text('Retry')),
          ],
        ),
      );
    }

    if (_delinquents.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(48),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.check_circle_outline,
                size: 56,
                color: StockpileColors.success,
              ),
              const SizedBox(height: 16),
              Text(
                'All Resellers Compliant',
                style: StockpileFonts.satoshi(
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  color: isDark
                      ? StockpileColors.darkTextPrimary
                      : StockpileColors.darkText,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'No overdue quotas detected.',
                style: StockpileFonts.satoshi(
                  fontSize: 14,
                  color: isDark
                      ? StockpileColors.darkTextMuted
                      : StockpileColors.mutedText,
                ),
              ),
              const SizedBox(height: 24),
              OutlinedButton.icon(
                onPressed: _load,
                icon: const Icon(Icons.refresh, size: 18),
                label: const Text('Refresh'),
              ),
            ],
          ),
        ),
      );
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Row(
            children: [
              Icon(
                Icons.warning_amber_rounded,
                color: StockpileColors.danger,
                size: 28,
              ),
              const SizedBox(width: 12),
              Text(
                'Quota Compliance Queue',
                style: StockpileFonts.satoshi(
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                  color: isDark
                      ? StockpileColors.darkTextPrimary
                      : StockpileColors.darkText,
                ),
              ),
              const SizedBox(width: 12),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 4,
                ),
                decoration: BoxDecoration(
                  color: StockpileColors.danger,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  '${_delinquents.length}',
                  style: StockpileFonts.satoshi(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: Colors.white,
                  ),
                ),
              ),
              const Spacer(),
              IconButton(
                onPressed: _load,
                icon: const Icon(Icons.refresh, size: 20),
                tooltip: 'Refresh',
              ),
            ],
          ),
          const SizedBox(height: 20),

          // Data table
          ClipRRect(
            borderRadius: BorderRadius.circular(14),
            child: DataTable(
              headingRowColor: WidgetStateProperty.resolveWith(
                (_) => isDark
                    ? StockpileColors.darkInputBg
                    : StockpileColors.tableHead,
              ),
              headingTextStyle: StockpileFonts.satoshi(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: isDark
                    ? StockpileColors.darkTextMuted
                    : StockpileColors.mutedText,
              ),
              dataTextStyle: StockpileFonts.satoshi(
                fontSize: 14,
                color: isDark
                    ? StockpileColors.darkTextPrimary
                    : StockpileColors.darkText,
              ),
              horizontalMargin: 16,
              columnSpacing: 24,
              columns: const [
                DataColumn(label: Text('RESELLER')),
                DataColumn(label: Text('DAYS OVERDUE')),
                DataColumn(label: Text('QUOTA EXPIRED')),
                DataColumn(label: Text('LAST REMITTANCE')),
                DataColumn(label: Text('ACTIONS')),
              ],
              rows: _delinquents.map((row) {
                final alert = SystemAlert.fromJson(row);
                final member = row['members'] as Map<String, dynamic>? ?? {};
                final firstName = member['first_name'] as String? ?? '';
                final lastName = member['last_name'] as String? ?? '';
                final displayName = '$firstName $lastName'.trim().isEmpty
                    ? 'Reseller #${alert.memberId}'
                    : '$firstName $lastName'.trim();

                final quotaUntil = member['quota_valid_until'] != null
                    ? DateTime.tryParse(member['quota_valid_until'].toString())
                    : null;
                final lastRemit = member['last_remittance_at'] != null
                    ? DateTime.tryParse(member['last_remittance_at'].toString())
                    : null;

                final daysOverdue = quotaUntil != null
                    ? DateTime.now().difference(quotaUntil).inDays
                    : 0;

                final severity = daysOverdue > 14
                    ? 'critical'
                    : (alert.severity);

                return DataRow(
                  cells: [
                    DataCell(
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          CircleAvatar(
                            radius: 16,
                            backgroundColor: _severityColor(
                              severity,
                            ).withAlpha(30),
                            child: Text(
                              (firstName.isNotEmpty ? firstName[0] : 'R')
                                  .toUpperCase(),
                              style: StockpileFonts.satoshi(
                                fontSize: 13,
                                fontWeight: FontWeight.w700,
                                color: _severityColor(severity),
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Text(
                            displayName,
                            style: StockpileFonts.satoshi(
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                    DataCell(
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 4,
                            ),
                            decoration: BoxDecoration(
                              color: _severityColor(severity).withAlpha(25),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(
                              '$daysOverdue days',
                              style: StockpileFonts.satoshi(
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                                color: _severityColor(severity),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    DataCell(
                      Text(
                        quotaUntil != null ? _formatDate(quotaUntil) : '—',
                        style: StockpileFonts.satoshi(fontSize: 13),
                      ),
                    ),
                    DataCell(
                      Text(
                        lastRemit != null ? _formatDate(lastRemit) : 'Never',
                        style: StockpileFonts.satoshi(
                          fontSize: 13,
                          color: lastRemit == null
                              ? StockpileColors.mutedText
                              : null,
                        ),
                      ),
                    ),
                    DataCell(
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          _MiniActionButton(
                            icon: Icons.notifications_off_outlined,
                            label: 'Snooze 24h',
                            color: StockpileColors.secondary500,
                            onPressed: () => _snooze(alert.id!),
                          ),
                          const SizedBox(width: 8),
                          _MiniActionButton(
                            icon: Icons.check_circle_outline,
                            label: 'Dismiss',
                            color: StockpileColors.success,
                            onPressed: () => _dismiss(alert.id!),
                          ),
                        ],
                      ),
                    ),
                  ],
                );
              }).toList(),
            ),
          ),
        ],
      ),
    );
  }

  Color _severityColor(String severity) {
    switch (severity) {
      case 'critical':
        return StockpileColors.danger;
      case 'warning':
      default:
        return StockpileColors.primary900;
    }
  }

  String _formatDate(DateTime dt) {
    final now = DateTime.now();
    if (dt.year == now.year && dt.month == now.month && dt.day == now.day) {
      return 'Today';
    }
    return '${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')}';
  }
}

class _MiniActionButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onPressed;

  const _MiniActionButton({
    required this.icon,
    required this.label,
    required this.color,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onPressed,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          border: Border.all(color: color.withAlpha(80)),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 16, color: color),
            const SizedBox(width: 4),
            Text(
              label,
              style: StockpileFonts.satoshi(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: color,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
