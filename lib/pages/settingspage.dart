import 'package:flutter/material.dart';
import 'package:bot_toast/bot_toast.dart';
import 'package:lzcas/db/db.dart';

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  List<ResellerLevel> _levels = [];
  bool _levelsLoading = true;
  final Map<int, TextEditingController> _remMinCtls = {};
  final Map<int, TextEditingController> _remMaxCtls = {};
  final Map<int, TextEditingController> _cashAdvCtls = {};

  @override
  void initState() {
    super.initState();
    _loadLevels();
  }

  @override
  void dispose() {
    for (final c in [
      ..._remMinCtls.values,
      ..._remMaxCtls.values,
      ..._cashAdvCtls.values,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _loadLevels() async {
    final rows = await repository.fetchResellerLevels();
    for (final c in [
      ..._remMinCtls.values,
      ..._remMaxCtls.values,
      ..._cashAdvCtls.values,
    ]) {
      c.dispose();
    }
    _remMinCtls.clear();
    _remMaxCtls.clear();
    _cashAdvCtls.clear();
    for (final r in rows) {
      _remMinCtls[r.level] = TextEditingController(
        text: r.remittanceMin.toString(),
      );
      _remMaxCtls[r.level] = TextEditingController(
        text: r.remittanceMax.toString(),
      );
      _cashAdvCtls[r.level] = TextEditingController(
        text: r.cashAdvance.toString(),
      );
    }
    setState(() {
      _levels = rows;
      _levelsLoading = false;
    });
  }

  Future<void> _saveLevels() async {
    for (final lvl in _levels) {
      await repository.upsertResellerLevel(
        level: lvl.level,
        remittanceMin: int.tryParse(_remMinCtls[lvl.level]?.text ?? '0') ?? 0,
        remittanceMax: int.tryParse(_remMaxCtls[lvl.level]?.text ?? '0') ?? 0,
        cashAdvance: int.tryParse(_cashAdvCtls[lvl.level]?.text ?? '0') ?? 0,
      );
    }
    if (!mounted) return;
    BotToast.showText(text: 'Reseller levels saved');
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return _buildResellerLevelsTab(theme, colorScheme);
  }

  Widget _buildResellerLevelsTab(ThemeData theme, ColorScheme colorScheme) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'Reseller Levels',
                  style: theme.textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              ElevatedButton.icon(
                onPressed: _saveLevels,
                icon: const Icon(Icons.save, size: 18),
                label: const Text('Save'),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            'Configure remittance range and cash advance per level.',
            style: theme.textTheme.bodySmall?.copyWith(
              color: colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 12),
          if (_levelsLoading)
            const Center(child: CircularProgressIndicator())
          else ...[
            for (final lvl in _levels)
              Card(
                margin: const EdgeInsets.only(bottom: 8),
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Level ${lvl.level}',
                        style: theme.textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Expanded(
                            child: TextField(
                              controller: _remMinCtls[lvl.level],
                              keyboardType: TextInputType.number,
                              decoration: const InputDecoration(
                                labelText: 'Remittance Min',
                                isDense: true,
                                border: OutlineInputBorder(),
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: TextField(
                              controller: _remMaxCtls[lvl.level],
                              keyboardType: TextInputType.number,
                              decoration: const InputDecoration(
                                labelText: 'Remittance Max',
                                isDense: true,
                                border: OutlineInputBorder(),
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: TextField(
                              controller: _cashAdvCtls[lvl.level],
                              keyboardType: TextInputType.number,
                              decoration: const InputDecoration(
                                labelText: 'Cash Advance',
                                isDense: true,
                                border: OutlineInputBorder(),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ],
      ),
    );
  }
}
