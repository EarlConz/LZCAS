// lib/widgets/delivery_eta_settings.dart
//
// Admin Settings → General → "Delivery time estimate": the traffic factor
// and hand-over minutes behind the riders' automatic arrival time
// (eta_estimator.dart), with a check of how the estimate has done against
// real deliveries.

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:lzcas/db/db.dart';
import 'package:lzcas/services/config_service.dart';
import 'package:lzcas/services/eta_estimator.dart';
import 'package:lzcas/theme.dart';
import 'package:lzcas/utils/fonts.dart';
import 'package:lzcas/utils/toast_utils.dart';

class DeliveryEtaSettings extends StatefulWidget {
  const DeliveryEtaSettings({super.key});

  @override
  State<DeliveryEtaSettings> createState() => _DeliveryEtaSettingsState();
}

class _DeliveryEtaSettingsState extends State<DeliveryEtaSettings> {
  /// Tenths, so the stepper never drifts (1.2 is 12).
  late int _factor10;
  late int _handover;
  bool _saving = false;
  EtaCalibration? _calibration;

  @override
  void initState() {
    super.initState();
    final t = context.read<ConfigService>().etaTuning;
    _factor10 = (t.factor * 10).round();
    _handover = t.handoverMinutes;
    _loadCalibration();
  }

  Future<void> _loadCalibration() async {
    try {
      final c = EtaCalibration(await repository.fetchRiderTripTimes());
      if (mounted) setState(() => _calibration = c);
    } catch (_) {
      // Only the "how it has done" line is missing.
    }
  }

  EtaTuning get _tuning =>
      EtaTuning(factor: _factor10 / 10, handoverMinutes: _handover);

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      await repository.updateAppConfig(EtaTuning.factorKey, (_factor10 / 10).toStringAsFixed(1));
      await repository.updateAppConfig(EtaTuning.handoverKey, '$_handover');
      if (!mounted) return;
      await context.read<ConfigService>().refresh();
      showSuccessToast('Delivery time estimate saved');
    } catch (_) {
      showErrorToast('Could not save. Please try again.');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final text = isDark ? StockpileColors.darkTextPrimary : StockpileColors.darkText;
    final muted = isDark ? StockpileColors.darkTextMuted : const Color(0xFF6E6E7A);
    final line = isDark ? StockpileColors.darkDivider : StockpileColors.divider;
    final example = _tuning.apply(const Duration(minutes: 15)).inMinutes;

    Widget stepper({
      required String title,
      required String help,
      required String value,
      required VoidCallback? onMinus,
      required VoidCallback? onPlus,
      required String minusLabel,
      required String plusLabel,
    }) {
      return Container(
        constraints: const BoxConstraints(minWidth: 240, maxWidth: 360),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          border: Border.all(color: line),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(title, style: StockpileFonts.satoshi(fontSize: 15, fontWeight: FontWeight.w700, color: text)),
            const SizedBox(height: 4),
            Text(help, style: StockpileFonts.satoshi(fontSize: 13, height: 1.35, color: muted)),
            const SizedBox(height: 10),
            Row(
              children: [
                IconButton.outlined(
                  tooltip: minusLabel,
                  onPressed: onMinus,
                  icon: const Icon(Icons.remove_rounded),
                ),
                SizedBox(
                  width: 88,
                  child: Text(
                    value,
                    textAlign: TextAlign.center,
                    style: StockpileFonts.satoshi(fontSize: 24, fontWeight: FontWeight.w800, color: text),
                  ),
                ),
                IconButton.outlined(
                  tooltip: plusLabel,
                  onPressed: onPlus,
                  icon: const Icon(Icons.add_rounded),
                ),
              ],
            ),
          ],
        ),
      );
    }

    final cal = _calibration;
    final String calLine;
    String? suggestion;
    if (cal == null || cal.samples < 10) {
      calLine = 'Shown once there are 10 or more rider deliveries with a route '
          '(${cal?.samples ?? 0} so far).';
    } else {
      final diff = cal.averageLateMinutes(_tuning);
      calLine = diff.abs() < 1
          ? 'Riders arrived on average within a minute of this estimate.'
          : 'Riders arrived on average ${diff.abs().round()} min '
                '${diff > 0 ? 'later' : 'earlier'} than this estimate.';
      final s = cal.suggestedFactor(_handover);
      if (s != null && (s * 10).round() != _factor10) {
        suggestion = s.toStringAsFixed(1);
      }
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Delivery time estimate',
          style: StockpileFonts.satoshi(fontSize: 16, fontWeight: FontWeight.w700, color: text),
        ),
        const SizedBox(height: 4),
        Text(
          'How the app turns a route into the arrival time riders and members see.',
          style: StockpileFonts.satoshi(fontSize: 13, color: muted),
        ),
        const SizedBox(height: 14),
        Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            stepper(
              title: 'Traffic factor',
              help: 'The map times car trips. Above 1 means slower than the map says.',
              value: '×${(_factor10 / 10).toStringAsFixed(1)}',
              minusLabel: 'Lower the factor',
              plusLabel: 'Raise the factor',
              onMinus: _factor10 > 8 ? () => setState(() => _factor10--) : null,
              onPlus: _factor10 < 25 ? () => setState(() => _factor10++) : null,
            ),
            stepper(
              title: 'Handover time',
              help: 'Parking, calling the customer, the hand-over itself.',
              value: '$_handover min',
              minusLabel: 'Less handover time',
              plusLabel: 'More handover time',
              onMinus: _handover > 0 ? () => setState(() => _handover--) : null,
              onPlus: _handover < 15 ? () => setState(() => _handover++) : null,
            ),
          ],
        ),
        const SizedBox(height: 12),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            color: isDark ? StockpileColors.darkInputBg : StockpileColors.inputBg,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Text(
            'A route the map times at 15 min is shown as $example min.',
            style: StockpileFonts.satoshi(fontSize: 14, color: text),
          ),
        ),
        const SizedBox(height: 12),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            border: Border.all(color: line),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'HOW IT HAS DONE · LAST ${cal?.samples ?? 0} RIDER DELIVERIES',
                style: StockpileFonts.satoshi(fontSize: 11, fontWeight: FontWeight.w800, letterSpacing: 0.6, color: muted),
              ),
              const SizedBox(height: 6),
              Text(calLine, style: StockpileFonts.satoshi(fontSize: 14, color: text)),
              if (suggestion != null) ...[
                const SizedBox(height: 8),
                OutlinedButton(
                  onPressed: () => setState(() => _factor10 = (double.parse(suggestion!) * 10).round()),
                  child: Text('Use the suggested factor ×$suggestion'),
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: 14),
        Wrap(
          spacing: 10,
          runSpacing: 10,
          alignment: WrapAlignment.end,
          children: [
            OutlinedButton(
              onPressed: _saving
                  ? null
                  : () => setState(() {
                      _factor10 = (EtaTuning.defaults.factor * 10).round();
                      _handover = EtaTuning.defaults.handoverMinutes;
                    }),
              child: const Text('Reset to ×1.2 and 3 min'),
            ),
            FilledButton(
              onPressed: _saving ? null : _save,
              child: Text(_saving ? 'Saving…' : 'Save'),
            ),
          ],
        ),
      ],
    );
  }
}
