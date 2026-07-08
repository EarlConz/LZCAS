// lib/widgets/reseller_alert_banner.dart
// Reseller-facing alert banner — displays active system alerts from
// the admin (ping warnings, compliance notices) with dismiss action.
// Uses a left-accent-card design with shadow, gradient icon panel,
// relative timestamps, and action-required badges.

import 'dart:async';
import 'package:flutter/material.dart';
import '../data/models.dart';
import '../db/db.dart';
import '../theme.dart';
import '../utils/fonts.dart';

class ResellerAlertBanner extends StatefulWidget {
  final int memberId;

  const ResellerAlertBanner({super.key, required this.memberId});

  @override
  State<ResellerAlertBanner> createState() => _ResellerAlertBannerState();
}

class _ResellerAlertBannerState extends State<ResellerAlertBanner> {
  List<SystemAlert> _alerts = [];
  bool _loading = true;
  late final StreamSubscription<String> _sub;

  @override
  void initState() {
    super.initState();
    _load();
    _sub = repository.changes.listen((event) {
      if (event == 'system_alerts_changed') _load();
    });
  }

  @override
  void dispose() {
    _sub.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final alerts = await repository.fetchMemberAlerts(widget.memberId);
      if (!mounted) return;
      setState(() {
        _alerts = alerts;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _loading = false);
    }
  }

  Future<void> _dismiss(int alertId) async {
    await repository.markAlertRead(alertId);
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const SizedBox.shrink();
    if (_alerts.isEmpty) return const SizedBox.shrink();

    return AnimatedSize(
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeOut,
      alignment: Alignment.topCenter,
      child: Column(
        key: ValueKey(_alerts.map((a) => a.id).join(',')),
        children: _alerts.map(_alertCard).toList(),
      ),
    );
  }

  Widget _alertCard(SystemAlert alert) {
    final isCritical = alert.severity == 'critical';
    final accent = isCritical
        ? StockpileColors.danger
        : StockpileColors.primary900;
    final now = DateTime.now();
    final created = alert.createdAt;
    final age = created != null ? _relativeTime(created, now) : '';

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: accent.withValues(alpha: 0.08),
              blurRadius: 16,
              offset: const Offset(0, 4),
            ),
          ],
          border: Border(left: BorderSide(color: accent, width: 4)),
        ),
        clipBehavior: Clip.antiAlias,
        child: IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Left icon panel
              Container(
                width: 72,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      accent.withValues(alpha: 0.12),
                      accent.withValues(alpha: 0.04),
                    ],
                  ),
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        color: accent.withValues(alpha: 0.15),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        isCritical
                            ? Icons.warning_amber_rounded
                            : Icons.notifications_active_rounded,
                        size: 22,
                        color: accent,
                      ),
                    ),
                  ],
                ),
              ),
              // Right content
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Header: label + badge + age
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              isCritical ? 'Compliance Warning' : 'Notice',
                              style: StockpileFonts.satoshi(
                                fontSize: 12,
                                fontWeight: FontWeight.w800,
                                color: accent,
                                letterSpacing: 0.6,
                              ),
                            ),
                          ),
                          if (isCritical)
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 3,
                              ),
                              decoration: BoxDecoration(
                                color: accent,
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Text(
                                'ACTION REQUIRED',
                                style: StockpileFonts.satoshi(
                                  fontSize: 9,
                                  fontWeight: FontWeight.w800,
                                  color: Colors.white,
                                  letterSpacing: 0.4,
                                ),
                              ),
                            ),
                          if (age.isNotEmpty) ...[
                            const SizedBox(width: 8),
                            Text(
                              age,
                              style: StockpileFonts.satoshi(
                                fontSize: 11,
                                color: StockpileColors.mutedText,
                              ),
                            ),
                          ],
                        ],
                      ),
                      const SizedBox(height: 8),
                      // Title
                      Text(
                        alert.title.replaceFirst(
                          '⚠️ Compliance Warning — ',
                          '',
                        ),
                        style: StockpileFonts.satoshi(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                          color: StockpileColors.darkText,
                          height: 1.3,
                        ),
                      ),
                      if (alert.message != null &&
                          alert.message!.isNotEmpty) ...[
                        const SizedBox(height: 6),
                        Text(
                          alert.message!,
                          style: StockpileFonts.satoshi(
                            fontSize: 13,
                            color: StockpileColors.mutedText,
                            height: 1.5,
                          ),
                          maxLines: 3,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                      const SizedBox(height: 10),
                      // Dismiss button
                      Align(
                        alignment: Alignment.centerRight,
                        child: TextButton.icon(
                          style: TextButton.styleFrom(
                            foregroundColor: accent,
                            backgroundColor: accent.withValues(alpha: 0.06),
                            padding: const EdgeInsets.symmetric(
                              horizontal: 14,
                              vertical: 8,
                            ),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10),
                            ),
                          ),
                          icon: const Icon(
                            Icons.check_circle_outline,
                            size: 16,
                          ),
                          label: Text(
                            'Got it',
                            style: StockpileFonts.satoshi(
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          onPressed: () => _dismiss(alert.id!),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _relativeTime(DateTime created, DateTime now) {
    final diff = now.difference(created);
    if (diff.inMinutes < 1) return 'just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    if (diff.inDays < 7) return '${diff.inDays}d ago';
    return '${diff.inDays ~/ 7}w ago';
  }
}
