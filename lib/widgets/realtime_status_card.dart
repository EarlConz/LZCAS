// lib/widgets/realtime_status_card.dart
//
// Settings → Live updates: whether this device is connected for the
// changes other devices make, table by table, and, when it isn't, the
// server's own reason. Part 6 found every "updates by itself" test failing
// with no subscriptions on staging at all; release builds print nothing,
// so this is where a tester reads what is wrong, and can reconnect.

import 'package:flutter/material.dart';

import 'package:lzcas/data/supabase_repository.dart' show RealtimeStatus;
import 'package:lzcas/db/db.dart';
import 'package:lzcas/theme.dart';
import 'package:lzcas/utils/fonts.dart';
import 'package:lzcas/utils/formatters.dart' show formatAgo;

class RealtimeStatusCard extends StatelessWidget {
  const RealtimeStatusCard({super.key});

  /// The screens each table keeps current, so the list reads in the
  /// app's terms.
  static const _what = {
    'items': 'Products and stock',
    'members': 'Members',
    'sales': 'Sales',
    'pending_requests': 'Requests',
    'withdrawal_requests': 'Withdrawals',
    'member_transactions': 'Earnings',
    'announcements': 'Announcements',
    'branch_stock': 'Branch stock',
    'orders': 'Delivery orders',
  };

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final text = isDark ? StockpileColors.darkTextPrimary : StockpileColors.darkText;
    final muted = isDark ? StockpileColors.darkTextMuted : const Color(0xFF6E6E7A);
    final line = isDark ? StockpileColors.darkDivider : StockpileColors.divider;
    const ok = Color(0xFF15803D);
    const bad = Color(0xFFB91C1C);

    return ValueListenableBuilder<RealtimeStatus>(
      valueListenable: repository.realtimeStatus,
      builder: (context, st, _) {
        final headline = st.channels.isEmpty
            ? st.note
            : st.allConnected
            ? 'Connected: changes from other devices show by themselves'
            : '${st.connected} of ${st.channels.length} connected';
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Live updates',
              style: StockpileFonts.satoshi(fontSize: 16, fontWeight: FontWeight.w700, color: text),
            ),
            const SizedBox(height: 4),
            Text(
              'Whether this device hears what other devices change. Screens also '
              'refresh every 30 seconds, so a problem here makes updates slower, '
              'not lost.',
              style: StockpileFonts.satoshi(fontSize: 13, color: muted),
            ),
            const SizedBox(height: 12),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                border: Border.all(color: line),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(
                        st.allConnected ? Icons.check_circle_rounded : Icons.error_outline_rounded,
                        size: 20,
                        color: st.allConnected ? ok : bad,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          headline,
                          style: StockpileFonts.satoshi(fontSize: 14, fontWeight: FontWeight.w700, color: text),
                        ),
                      ),
                    ],
                  ),
                  if (st.at != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 2, left: 28),
                      child: Text(
                        'Last change ${formatAgo(st.at)}',
                        style: StockpileFonts.satoshi(fontSize: 12, color: muted),
                      ),
                    ),
                  if (st.channels.isNotEmpty) ...[
                    const SizedBox(height: 10),
                    for (final e in st.channels.entries)
                      Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            SizedBox(
                              width: 150,
                              child: Text(
                                _what[e.key] ?? e.key,
                                style: StockpileFonts.satoshi(fontSize: 13, color: text),
                              ),
                            ),
                            Expanded(
                              child: SelectableText(
                                e.value,
                                style: StockpileFonts.satoshi(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                  color: e.value == 'connected' ? ok : (e.value == 'joining' ? muted : bad),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                  ],
                  const SizedBox(height: 12),
                  OutlinedButton.icon(
                    onPressed: repository.reconnectRealtime,
                    icon: const Icon(Icons.refresh_rounded, size: 18),
                    label: const Text('Reconnect'),
                  ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }
}
