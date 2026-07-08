// lib/widgets/quota_compliance_queue.dart
// Reseller Quota Compliance Page — responsive admin view with KPI ribbon,
// desktop sortable DataTable, mobile card feed with progress bars, and
// three-tier status system. Breakpoint: 800 px.

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../db/db.dart';
import '../theme.dart';
import '../utils/fonts.dart';

// ── Design constants ────────────────────────────────────────────────────────

const _kOrange = StockpileColors.primary900; // #FF6700
const _kBlue = StockpileColors.secondary500; // #0037FD
const _kGreen = StockpileColors.success; // #22C55E
const _kRed = StockpileColors.danger; // #EF4444
const _kAmber = Color(0xFFF59E0B);
const _kGreenBg = StockpileColors.successBg;
const _kBreakpoint = 800.0;

const _kCardBg = Color(0xFFFFFFFF);
const _kBorder = Color(0xFFE9ECEF);
const _kViewBg = Color(0xFFF8F9FA);

// ── Status tiers ────────────────────────────────────────────────────────────

enum _StatusTier { compliant, atRisk, overdue }

_StatusTier _computeTier(DateTime? quotaUntil, DateTime now) {
  if (quotaUntil == null) return _StatusTier.overdue;
  final diff = quotaUntil.difference(now);
  if (diff.isNegative) return _StatusTier.overdue;
  if (diff.inHours < 24) return _StatusTier.atRisk;
  return _StatusTier.compliant;
}

// ═══════════════════════════════════════════════════════════════════════════
// ── Page widget ────────────────────────────────────────────────────────────
// ═══════════════════════════════════════════════════════════════════════════

class QuotaComplianceQueue extends StatefulWidget {
  const QuotaComplianceQueue({super.key});

  @override
  State<QuotaComplianceQueue> createState() => _QuotaComplianceQueueState();
}

class _QuotaComplianceQueueState extends State<QuotaComplianceQueue> {
  // ── Data state ─────────────────────────────────────────────────────────
  List<Map<String, dynamic>> _rows = [];
  String _totalResellers = '0';
  String _overdueCount = '0';
  String _compliantCount = '0';
  bool _loading = true;
  String? _error;
  late final StreamSubscription<String> _changesSub;

  // ── Desktop sort state ─────────────────────────────────────────────────
  int _sortColumnIndex = 0;
  bool _sortAscending = true;

  // ── Lifecycle ──────────────────────────────────────────────────────────

  @override
  void initState() {
    super.initState();
    _load();
    _changesSub = repository.changes.listen((event) {
      if (event == 'borrow_updated' ||
          event == 'borrows_changed' ||
          event == 'system_alerts_changed') {
        _load();
      }
    });
  }

  @override
  void dispose() {
    _changesSub.cancel();
    super.dispose();
  }

  // ── Data loading ───────────────────────────────────────────────────────

  Future<void> _load() async {
    final isFirstLoad = _rows.isEmpty;
    if (isFirstLoad) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }

    try {
      final results = await Future.wait([
        repository.fetchQuotaComplianceSummary(),
        repository.fetchQuotaDelinquentMembers(),
      ]);
      if (!mounted) return;
      setState(() {
        final summary = results[0] as Map<String, String>;
        _totalResellers = summary['total'] ?? '0';
        _overdueCount = summary['overdue'] ?? '0';
        _compliantCount = summary['compliant'] ?? '0';
        _rows = results[1] as List<Map<String, dynamic>>;
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

  // ── Sorting ────────────────────────────────────────────────────────────

  void _sort(int columnIndex, bool ascending) {
    setState(() {
      _sortColumnIndex = columnIndex;
      _sortAscending = ascending;
    });
  }

  List<Map<String, dynamic>> get _sortedRows {
    final sorted = List<Map<String, dynamic>>.from(_rows);
    final now = DateTime.now();
    sorted.sort((a, b) {
      int cmp;
      switch (_sortColumnIndex) {
        case 0: // Name
          final na = '${a['first_name'] ?? ''} ${a['last_name'] ?? ''}'.trim();
          final nb = '${b['first_name'] ?? ''} ${b['last_name'] ?? ''}'.trim();
          cmp = na.compareTo(nb);
          break;
        case 1: // Deadline
          final da = a['quota_valid_until'];
          final db = b['quota_valid_until'];
          final ta = da != null ? DateTime.tryParse(da.toString()) : null;
          final tb = db != null ? DateTime.tryParse(db.toString()) : null;
          if (ta == null && tb == null) {
            cmp = 0;
          } else if (ta == null) {
            cmp = 1;
          } else if (tb == null) {
            cmp = -1;
          } else {
            cmp = ta.compareTo(tb);
          }
          break;
        case 2: // Days Left
          final qa = a['quota_valid_until'];
          final qb = b['quota_valid_until'];
          final qta = qa != null ? DateTime.tryParse(qa.toString()) : null;
          final qtb = qb != null ? DateTime.tryParse(qb.toString()) : null;
          final dla = qta != null ? qta.difference(now).inDays : -9999;
          final dlb = qtb != null ? qtb.difference(now).inDays : -9999;
          cmp = dla.compareTo(dlb);
          break;
        case 3: // Status
          final ta = _computeTier(
            a['quota_valid_until'] != null
                ? DateTime.tryParse(a['quota_valid_until'].toString())
                : null,
            now,
          );
          final tb = _computeTier(
            b['quota_valid_until'] != null
                ? DateTime.tryParse(b['quota_valid_until'].toString())
                : null,
            now,
          );
          cmp = ta.index.compareTo(tb.index);
          break;
        default:
          cmp = 0;
      }
      return _sortAscending ? cmp : -cmp;
    });
    return sorted;
  }

  // ── Actions ────────────────────────────────────────────────────────────

  Future<void> _pingAlert(int memberId, String name) async {
    final now = DateTime.now();
    final row = _rows.firstWhere((r) => r['id'] == memberId, orElse: () => {});
    final quotaUntil = row['quota_valid_until'] != null
        ? DateTime.tryParse(row['quota_valid_until'].toString())
        : null;
    final daysOverdue = quotaUntil != null
        ? now.difference(quotaUntil).inDays
        : 0;

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: [
            const Icon(Icons.warning_amber_rounded, color: _kOrange, size: 24),
            const SizedBox(width: 8),
            Text(
              'Send Warning',
              style: StockpileFonts.satoshi(fontWeight: FontWeight.w700),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '$name is $daysOverdue day${daysOverdue == 1 ? '' : 's'} past '
              'their remittance deadline.',
              style: StockpileFonts.satoshi(fontSize: 14, height: 1.5),
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: _kOrange.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: _kOrange.withValues(alpha: 0.2)),
              ),
              child: Row(
                children: [
                  Icon(Icons.info_outline, size: 16, color: _kOrange),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'This sends a critical compliance alert visible to the '
                      'reseller on their dashboard and notification badge.',
                      style: StockpileFonts.satoshi(
                        fontSize: 12,
                        color: _kOrange,
                        height: 1.4,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton.icon(
            style: FilledButton.styleFrom(backgroundColor: _kOrange),
            icon: const Icon(Icons.send_rounded, size: 18),
            onPressed: () => Navigator.pop(ctx, true),
            label: Text(
              'Send Warning',
              style: StockpileFonts.satoshi(fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ),
    );
    if (ok == true && mounted) {
      try {
        await repository.sendPingWarning(memberId);
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('⚠️ Compliance warning sent to $name.'),
            behavior: SnackBarBehavior.floating,
            backgroundColor: _kOrange,
            duration: const Duration(seconds: 3),
          ),
        );
      } catch (e) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to send warning: $e'),
            behavior: SnackBarBehavior.floating,
            backgroundColor: _kRed,
            duration: const Duration(seconds: 5),
            showCloseIcon: true,
          ),
        );
      }
      await _load();
    }
  }

  // ── Build ──────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final isDesktop = MediaQuery.sizeOf(context).width >= _kBreakpoint;

    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_error != null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline, size: 48, color: _kRed),
            const SizedBox(height: 16),
            Text(
              _error!,
              style: StockpileFonts.satoshi(fontSize: 16, color: _kRed),
            ),
            const SizedBox(height: 16),
            OutlinedButton(onPressed: _load, child: const Text('Retry')),
          ],
        ),
      );
    }

    return AnimatedOpacity(
      opacity: _loading ? 0 : 1,
      duration: const Duration(milliseconds: 350),
      child: Container(
        color: _kViewBg,
        child: isDesktop ? _buildDesktop() : _buildMobile(),
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════
  // ── Shared: KPI Ribbon ─────────────────────────────────────────────────
  // ═══════════════════════════════════════════════════════════════════════

  Widget _buildKpiRibbon(bool isDesktop) {
    final cards = [
      _KpiCard(
        label: 'Total Verified Resellers',
        value: _totalResellers,
        icon: Icons.people_alt_rounded,
        backgroundColor: Colors.white,
        valueColor: StockpileColors.darkText,
      ),
      _KpiCard(
        label: 'Overdue Accounts',
        value: _overdueCount,
        icon: Icons.warning_amber_rounded,
        backgroundColor: const Color(0xFFFFF4E6),
        valueColor: _kOrange,
      ),
      _KpiCard(
        label: 'Active & Compliant',
        value: _compliantCount,
        icon: Icons.check_circle_rounded,
        backgroundColor: _kGreenBg,
        valueColor: _kGreen,
      ),
    ];

    Widget ribbon = isDesktop
        ? Row(
            children: [
              for (int i = 0; i < cards.length; i++) ...[
                Expanded(child: cards[i]),
                if (i < cards.length - 1) const SizedBox(width: 16),
              ],
            ],
          )
        : Column(
            children: [
              for (int i = 0; i < cards.length; i++) ...[
                cards[i],
                if (i < cards.length - 1) const SizedBox(height: 12),
              ],
            ],
          );

    return Padding(
      padding: EdgeInsets.fromLTRB(
        isDesktop ? 24 : 16,
        isDesktop ? 24 : 16,
        isDesktop ? 24 : 16,
        0,
      ),
      child: ribbon,
    );
  }

  // ═══════════════════════════════════════════════════════════════════════
  // ── Desktop Layout ─────────────────────────────────────────────────────
  // ═══════════════════════════════════════════════════════════════════════

  Widget _buildDesktop() {
    return Column(
      children: [
        _buildKpiRibbon(true),
        const SizedBox(height: 24),
        Expanded(
          child: _rows.isEmpty
              ? _buildEmptyState()
              : Padding(
                  padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
                  child: _buildDesktopTable(),
                ),
        ),
      ],
    );
  }

  Widget _buildDesktopTable() {
    final sorted = _sortedRows;
    return Container(
      decoration: BoxDecoration(
        color: _kCardBg,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _kBorder),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minWidth: 900),
            child: DataTable(
              sortColumnIndex: _sortColumnIndex,
              sortAscending: _sortAscending,
              headingRowColor: WidgetStateProperty.all(const Color(0xFFF8F9FA)),
              headingTextStyle: StockpileFonts.satoshi(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: StockpileColors.mutedText,
                letterSpacing: 0.8,
              ),
              dataTextStyle: StockpileFonts.satoshi(fontSize: 14),
              columnSpacing: 24,
              horizontalMargin: 20,
              dataRowMinHeight: 64,
              dataRowMaxHeight: 72,
              columns: [
                DataColumn(
                  label: const Text('RESELLER'),
                  onSort: (c, _) => _sort(c, !_sortAscending),
                ),
                DataColumn(
                  label: const Text('DEADLINE'),
                  onSort: (c, _) => _sort(c, !_sortAscending),
                ),
                DataColumn(
                  label: const Text('DAYS LEFT'),
                  onSort: (c, _) => _sort(c, !_sortAscending),
                ),
                const DataColumn(label: Text('LAST REMIT')),
                DataColumn(
                  label: const Text('STATUS'),
                  onSort: (c, _) => _sort(c, !_sortAscending),
                ),
                const DataColumn(label: Text('ACTIONS')),
              ],
              rows: sorted.map(_desktopRow).toList(),
            ),
          ),
        ),
      ),
    );
  }

  DataRow _desktopRow(Map<String, dynamic> row) {
    final memberId = row['id'] as int;
    final firstName = row['first_name'] as String? ?? '';
    final lastName = row['last_name'] as String? ?? '';
    final displayName = '$firstName $lastName'.trim().isEmpty
        ? 'Reseller #$memberId'
        : '$firstName $lastName'.trim();

    final now = DateTime.now();
    final quotaUntil = row['quota_valid_until'] != null
        ? DateTime.tryParse(row['quota_valid_until'].toString())
        : null;
    final lastRemit = row['last_remittance_at'] != null
        ? DateTime.tryParse(row['last_remittance_at'].toString())
        : null;

    final tier = _computeTier(quotaUntil, now);
    final daysLeft = quotaUntil != null
        ? quotaUntil.difference(now).inDays
        : -1;
    final daysOverdue = tier == _StatusTier.overdue
        ? now.difference(quotaUntil!).inDays
        : 0;

    final hoverColor = tier == _StatusTier.overdue
        ? _kOrange.withValues(alpha: 0.04)
        : _kBlue.withValues(alpha: 0.03);

    return DataRow(
      color: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.hovered)) return hoverColor;
        return null;
      }),
      cells: [
        DataCell(
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              _Avatar(tier: tier, firstName: firstName),
              const SizedBox(width: 12),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    displayName,
                    style: StockpileFonts.satoshi(fontWeight: FontWeight.w600),
                  ),
                  if (row['contact_no'] is String &&
                      (row['contact_no'] as String).isNotEmpty)
                    Text(
                      row['contact_no'] as String,
                      style: StockpileFonts.satoshi(
                        fontSize: 11,
                        color: StockpileColors.mutedText,
                      ),
                    ),
                ],
              ),
            ],
          ),
        ),
        DataCell(
          Text(
            quotaUntil != null
                ? DateFormat('MMM d, yyyy').format(quotaUntil)
                : '—',
            style: StockpileFonts.satoshi(fontSize: 13),
          ),
        ),
        DataCell(_DaysLeftChip(tier: tier, daysLeft: daysLeft)),
        DataCell(
          Text(
            lastRemit != null
                ? DateFormat('MMM d, yyyy').format(lastRemit)
                : 'Never',
            style: StockpileFonts.satoshi(
              fontSize: 13,
              color: lastRemit == null ? StockpileColors.mutedText : null,
            ),
          ),
        ),
        DataCell(
          _StatusBadge(
            tier: tier,
            daysLeft: daysLeft,
            daysOverdue: daysOverdue,
          ),
        ),
        DataCell(
          _PingButton(onPressed: () => _pingAlert(memberId, displayName)),
        ),
      ],
    );
  }

  // ═══════════════════════════════════════════════════════════════════════
  // ── Mobile Layout ──────────────────────────────────────────────────────
  // ═══════════════════════════════════════════════════════════════════════

  Widget _buildMobile() {
    return Column(
      children: [
        _buildKpiRibbon(false),
        const SizedBox(height: 16),
        Expanded(
          child: _rows.isEmpty
              ? _buildEmptyState()
              : RefreshIndicator(
                  onRefresh: _load,
                  color: _kBlue,
                  child: ListView.separated(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                    itemCount: _rows.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 12),
                    itemBuilder: (_, i) => _mobileCard(_rows[i]),
                  ),
                ),
        ),
      ],
    );
  }

  Widget _mobileCard(Map<String, dynamic> row) {
    final memberId = row['id'] as int;
    final firstName = row['first_name'] as String? ?? '';
    final lastName = row['last_name'] as String? ?? '';
    final displayName = '$firstName $lastName'.trim().isEmpty
        ? 'Reseller #$memberId'
        : '$firstName $lastName'.trim();
    final contactNo = row['contact_no'] as String? ?? '';

    final now = DateTime.now();
    final quotaUntil = row['quota_valid_until'] != null
        ? DateTime.tryParse(row['quota_valid_until'].toString())
        : null;
    final tier = _computeTier(quotaUntil, now);
    final daysLeft = quotaUntil != null
        ? quotaUntil.difference(now).inDays
        : -1;
    final daysOverdue = tier == _StatusTier.overdue
        ? now.difference(quotaUntil!).inDays
        : 0;

    // Progress: fraction of quota period remaining (0.0 = expired, 1.0 = full)
    final progress = tier == _StatusTier.overdue
        ? 0.0
        : (quotaUntil != null
              ? (quotaUntil.difference(now).inHours / (7 * 24)).clamp(0.0, 1.0)
              : 0.0);
    final progressColor = tier == _StatusTier.atRisk ? _kAmber : _kGreen;

    return Container(
      decoration: BoxDecoration(
        color: _kCardBg,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: tier == _StatusTier.overdue
              ? _kOrange.withValues(alpha: 0.4)
              : tier == _StatusTier.atRisk
              ? _kAmber.withValues(alpha: 0.4)
              : _kBorder,
          width: tier == _StatusTier.compliant ? 1 : 2,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header: avatar + name + badge
            Row(
              children: [
                _Avatar(tier: tier, firstName: firstName),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        displayName,
                        style: StockpileFonts.satoshi(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      if (contactNo.isNotEmpty)
                        Text(
                          contactNo,
                          style: StockpileFonts.satoshi(
                            fontSize: 12,
                            color: StockpileColors.mutedText,
                          ),
                        ),
                    ],
                  ),
                ),
                _StatusBadge(
                  tier: tier,
                  daysLeft: daysLeft,
                  daysOverdue: daysOverdue,
                ),
              ],
            ),
            const SizedBox(height: 14),
            // Progress bar
            ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: SizedBox(
                height: 8,
                child: Row(
                  children: [
                    Expanded(
                      flex: (progress * 100).round().clamp(0, 100),
                      child: Container(color: progressColor),
                    ),
                    Expanded(
                      flex: ((1.0 - progress) * 100).round().clamp(0, 100),
                      child: Container(color: _kBorder),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
            // Body: deadline + days-left
            Row(
              children: [
                Icon(
                  Icons.event_rounded,
                  size: 16,
                  color: StockpileColors.mutedText,
                ),
                const SizedBox(width: 6),
                Text(
                  quotaUntil != null
                      ? 'Deadline: ${DateFormat('MMM d, yyyy  h:mm a').format(quotaUntil)}'
                      : 'No deadline set',
                  style: StockpileFonts.satoshi(fontSize: 13),
                ),
                const Spacer(),
                _DaysLeftChip(tier: tier, daysLeft: daysLeft),
              ],
            ),
            const SizedBox(height: 14),
            // Footer: ping button
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  foregroundColor: _kBlue,
                  side: const BorderSide(color: _kBlue, width: 1.5),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
                icon: const Icon(Icons.notifications_active_rounded, size: 20),
                label: Text(
                  'Ping Warning',
                  style: StockpileFonts.satoshi(fontWeight: FontWeight.w700),
                ),
                onPressed: () => _pingAlert(memberId, displayName),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════
  // ── Empty state ────────────────────────────────────────────────────────
  // ═══════════════════════════════════════════════════════════════════════

  Widget _buildEmptyState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(48),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 96,
              height: 96,
              decoration: BoxDecoration(
                color: _kGreenBg,
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: _kGreen.withValues(alpha: 0.15),
                    blurRadius: 24,
                    offset: const Offset(0, 8),
                  ),
                ],
              ),
              child: const Icon(
                Icons.verified_rounded,
                size: 48,
                color: _kGreen,
              ),
            ),
            const SizedBox(height: 24),
            Text(
              'Everyone is Compliant',
              style: StockpileFonts.satoshi(
                fontSize: 22,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'All verified resellers have active quota deadlines. '
              'No overdue or at-risk accounts detected.',
              textAlign: TextAlign.center,
              style: StockpileFonts.satoshi(
                fontSize: 14,
                color: StockpileColors.mutedText,
                height: 1.5,
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
}

// ═══════════════════════════════════════════════════════════════════════════
// ── Sub-widgets ────────────────────────────────────────────────────────────
// ═══════════════════════════════════════════════════════════════════════════

/// Shared avatar with tier-based coloring.
class _Avatar extends StatelessWidget {
  final _StatusTier tier;
  final String firstName;
  const _Avatar({required this.tier, required this.firstName});

  Color get _color => switch (tier) {
    _StatusTier.overdue => _kOrange,
    _StatusTier.atRisk => _kAmber,
    _StatusTier.compliant => _kGreen,
  };

  @override
  Widget build(BuildContext context) {
    return CircleAvatar(
      radius: 18,
      backgroundColor: _color.withValues(alpha: 0.12),
      child: Text(
        (firstName.isNotEmpty ? firstName[0] : 'R').toUpperCase(),
        style: StockpileFonts.satoshi(
          fontSize: 13,
          fontWeight: FontWeight.w700,
          color: _color,
        ),
      ),
    );
  }
}

/// A single summary card for the KPI ribbon with shadow and hover lift.
class _KpiCard extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;
  final Color backgroundColor;
  final Color valueColor;

  const _KpiCard({
    required this.label,
    required this.value,
    required this.icon,
    required this.backgroundColor,
    required this.valueColor,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: _kBorder),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: valueColor.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, size: 22, color: valueColor),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: StockpileFonts.satoshi(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: StockpileColors.mutedText,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  value,
                  style: StockpileFonts.satoshi(
                    fontSize: 28,
                    fontWeight: FontWeight.w800,
                    color: valueColor,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Rounded pill badge with three-tier coloring.
class _StatusBadge extends StatelessWidget {
  final _StatusTier tier;
  final int daysLeft;
  final int daysOverdue;

  const _StatusBadge({
    required this.tier,
    required this.daysLeft,
    required this.daysOverdue,
  });

  @override
  Widget build(BuildContext context) {
    final (color, bg, label, subtitle) = switch (tier) {
      _StatusTier.overdue => (
        _kOrange,
        _kOrange.withValues(alpha: 0.1),
        'OVERDUE',
        '$daysOverdue d',
      ),
      _StatusTier.atRisk => (
        _kAmber,
        _kAmber.withValues(alpha: 0.1),
        'AT RISK',
        '${daysLeft}h',
      ),
      _StatusTier.compliant => (
        _kGreen,
        _kGreen.withValues(alpha: 0.1),
        'COMPLIANT',
        null as String?,
      ),
    };

    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: 12,
        vertical: subtitle != null ? 6 : 8,
      ),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label,
            style: StockpileFonts.satoshi(
              fontSize: 11,
              fontWeight: FontWeight.w800,
              color: color,
            ),
          ),
          if (subtitle != null)
            Text(
              subtitle,
              style: StockpileFonts.satoshi(
                fontSize: 10,
                fontWeight: FontWeight.w600,
                color: color.withValues(alpha: 0.7),
              ),
            ),
        ],
      ),
    );
  }
}

/// Compact chip showing days left with tier-based color.
class _DaysLeftChip extends StatelessWidget {
  final _StatusTier tier;
  final int daysLeft;

  const _DaysLeftChip({required this.tier, required this.daysLeft});

  @override
  Widget build(BuildContext context) {
    final (color, text) = switch (tier) {
      _StatusTier.overdue => (_kOrange, 'Overdue'),
      _StatusTier.atRisk => (_kAmber, '< 24h'),
      _StatusTier.compliant => (
        _kGreen,
        daysLeft == 0 ? 'Today' : '$daysLeft day${daysLeft == 1 ? '' : 's'}',
      ),
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        text,
        style: StockpileFonts.satoshi(
          fontSize: 12,
          fontWeight: FontWeight.w700,
          color: color,
        ),
      ),
    );
  }
}

/// Royal-blue icon button for sending a compliance warning.
class _PingButton extends StatelessWidget {
  final VoidCallback onPressed;
  const _PingButton({required this.onPressed});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onPressed,
      borderRadius: BorderRadius.circular(10),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: _kBlue.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: _kBlue.withValues(alpha: 0.25)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.notifications_active_rounded,
              size: 16,
              color: _kBlue,
            ),
            const SizedBox(width: 6),
            Text(
              'Ping Alert',
              style: StockpileFonts.satoshi(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: _kBlue,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
