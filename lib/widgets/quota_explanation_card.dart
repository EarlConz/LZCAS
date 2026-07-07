// lib/widgets/quota_explanation_card.dart
// Educational notice for resellers explaining calendar-month quota rules.

import 'package:flutter/material.dart';
import '../theme.dart';
import '../utils/fonts.dart';

class QuotaExplanationCard extends StatefulWidget {
  const QuotaExplanationCard({super.key});

  @override
  State<QuotaExplanationCard> createState() => _QuotaExplanationCardState();
}

class _QuotaExplanationCardState extends State<QuotaExplanationCard> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final accent = StockpileColors.secondary500;

    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: accent.withAlpha(isDark ? 60 : 40)),
      ),
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          gradient: LinearGradient(
            colors: [
              accent.withAlpha(isDark ? 16 : 10),
              StockpileColors.primary900.withAlpha(isDark ? 8 : 4),
            ],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Tappable header
            InkWell(
              onTap: () => setState(() => _expanded = !_expanded),
              borderRadius: BorderRadius.circular(16),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(18, 16, 14, 16),
                child: Row(
                  children: [
                    Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [accent, accent.withBlue(accent.blue + 30)],
                        ),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Icon(
                        Icons.lightbulb_outline_rounded,
                        color: Colors.white,
                        size: 22,
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'How Your Quota Works',
                            style: StockpileFonts.satoshi(
                              fontSize: 15,
                              fontWeight: FontWeight.w700,
                              color: isDark
                                  ? StockpileColors.darkTextPrimary
                                  : StockpileColors.darkText,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            'Calendar-month tracking explained',
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
                    AnimatedRotation(
                      turns: _expanded ? 0.5 : 0.0,
                      duration: const Duration(milliseconds: 200),
                      child: Icon(
                        Icons.keyboard_arrow_down_rounded,
                        size: 22,
                        color: isDark
                            ? StockpileColors.darkTextMuted
                            : StockpileColors.mutedText,
                      ),
                    ),
                  ],
                ),
              ),
            ),

            // Expandable body
            AnimatedCrossFade(
              firstChild: const SizedBox.shrink(),
              secondChild: Padding(
                padding: const EdgeInsets.fromLTRB(18, 0, 18, 18),
                child: Column(
                  children: [
                    const Divider(height: 1),
                    const SizedBox(height: 14),
                    _Step(
                      index: 1,
                      icon: Icons.refresh_rounded,
                      title: 'Monthly Reset',
                      body:
                          'Your quota resets to 7 days on the 1st of every '
                          'month — no exceptions.',
                      accent: accent,
                      isDark: isDark,
                    ),
                    const SizedBox(height: 12),
                    _Step(
                      index: 2,
                      icon: Icons.sync_disabled_rounded,
                      title: 'No Carry-Over',
                      body:
                          'Extensions earned this month do not roll into '
                          'the next. Use them or lose them.',
                      accent: StockpileColors.primary900,
                      isDark: isDark,
                    ),
                    const SizedBox(height: 12),
                    _Step(
                      index: 3,
                      icon: Icons.trending_up_rounded,
                      title: 'Stack Extensions',
                      body:
                          '1 box = +1 week • 2 = +2wk • 3 = +3wk • 4+ = '
                          '+4wk. Capped at end of month.',
                      accent: StockpileColors.success,
                      isDark: isDark,
                    ),
                    const SizedBox(height: 12),
                    _Step(
                      index: 4,
                      icon: Icons.warning_amber_rounded,
                      title: 'Stay Compliant',
                      body:
                          'Remit early each month. If your quota expires, '
                          'an alert is sent to the admin.',
                      accent: StockpileColors.danger,
                      isDark: isDark,
                    ),
                  ],
                ),
              ),
              crossFadeState: _expanded
                  ? CrossFadeState.showSecond
                  : CrossFadeState.showFirst,
              duration: const Duration(milliseconds: 250),
            ),
          ],
        ),
      ),
    );
  }
}

class _Step extends StatelessWidget {
  final int index;
  final IconData icon;
  final String title;
  final String body;
  final Color accent;
  final bool isDark;

  const _Step({
    required this.index,
    required this.icon,
    required this.title,
    required this.body,
    required this.accent,
    required this.isDark,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Numbered circle
        Container(
          width: 28,
          height: 28,
          margin: const EdgeInsets.only(top: 1),
          decoration: BoxDecoration(
            color: accent.withAlpha(isDark ? 30 : 20),
            shape: BoxShape.circle,
          ),
          alignment: Alignment.center,
          child: Text(
            '$index',
            style: StockpileFonts.satoshi(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: accent,
            ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(icon, size: 15, color: accent),
                  const SizedBox(width: 6),
                  Text(
                    title,
                    style: StockpileFonts.satoshi(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: isDark
                          ? StockpileColors.darkTextPrimary
                          : StockpileColors.darkText,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 3),
              Text(
                body,
                style: StockpileFonts.satoshi(
                  fontSize: 12,
                  height: 1.4,
                  color: isDark
                      ? StockpileColors.darkTextMuted
                      : StockpileColors.bodyText,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
