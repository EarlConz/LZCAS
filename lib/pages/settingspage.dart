import 'package:flutter/material.dart';
import 'package:bot_toast/bot_toast.dart';
import 'package:lzcas/data/supabase_config.dart';
import 'package:lzcas/db/db.dart';

class SettingsPage extends StatefulWidget {
  final ValueChanged<bool>? onToggle;
  final bool initialDark;

  const SettingsPage({super.key, this.onToggle, this.initialDark = false});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  late bool _dark;
  bool _syncing = false;
  bool _restoring = false;
  List<ResellerLevel> _levels = [];
  bool _levelsLoading = true;
  final Map<int, TextEditingController> _remMinCtls = {};
  final Map<int, TextEditingController> _remMaxCtls = {};
  final Map<int, TextEditingController> _cashAdvCtls = {};

  void _onToggle(bool val) {
    setState(() => _dark = val);
    widget.onToggle?.call(_dark);
  }

  Future<void> _syncToCloud() async {
    if (!SupabaseConfig.isConfigured) {
      BotToast.showText(text: 'Supabase is not configured for this run');
      return;
    }

    // ── Confirmation dialog with record counts ──────────────────
    final items = await repository.fetchItems();
    final members = await repository.fetchMembers();
    final sales = await repository.fetchSales();

    final isEmpty = items.isEmpty && members.isEmpty && sales.isEmpty;

    if (!mounted) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Sync to Cloud'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'This will overwrite the cloud snapshot with your local data.',
            ),
            const SizedBox(height: 12),
            Text('• ${items.length} items'),
            Text('• ${members.length} members'),
            Text('• ${sales.length} sales'),
            if (isEmpty) ...[
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.error.withAlpha(30),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: Theme.of(context).colorScheme.error.withAlpha(80),
                  ),
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.warning_amber_rounded,
                      color: Theme.of(context).colorScheme.error,
                      size: 20,
                    ),
                    const SizedBox(width: 8),
                    const Expanded(
                      child: Text(
                        'Your local database is empty. Syncing now '
                        'will DELETE all cloud data.',
                        style: TextStyle(fontWeight: FontWeight.w600),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            style: isEmpty
                ? ElevatedButton.styleFrom(
                    backgroundColor: Theme.of(context).colorScheme.error,
                    foregroundColor: Colors.white,
                  )
                : null,
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(isEmpty ? 'Sync Anyway' : 'Sync'),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;

    setState(() => _syncing = true);
    try {
      // Data is already in the cloud — no sync needed.
      if (!mounted) return;
      BotToast.showText(text: 'All data is already stored in Supabase.');
    } catch (e) {
      if (!mounted) return;
      BotToast.showText(text: 'Failed to sync to Supabase: $e');
    } finally {
      if (mounted) {
        setState(() => _syncing = false);
      }
    }
  }

  Future<void> _restoreFromCloud() async {
    if (!SupabaseConfig.isConfigured) {
      BotToast.showText(text: 'Supabase is not configured for this run');
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Restore from cloud'),
        content: const Text(
          'This will replace your local inventory, members, and transactions with the current Supabase snapshot.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Restore'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    setState(() => _restoring = true);
    try {
      // Data is already cloud-based — no restore needed.
      if (!mounted) return;
      BotToast.showText(
        text: 'Data is already cloud-based. No restore needed.',
      );
    } catch (e) {
      if (!mounted) return;
      BotToast.showText(text: 'Failed to restore from Supabase: $e');
    } finally {
      if (mounted) {
        setState(() => _restoring = false);
      }
    }
  }

  @override
  void initState() {
    super.initState();
    _dark = widget.initialDark;
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
  void didUpdateWidget(covariant SettingsPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.initialDark != widget.initialDark) {
      setState(() {
        _dark = widget.initialDark;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return DefaultTabController(
      length: 2,
      child: Column(
        children: [
          TabBar(
            labelColor: colorScheme.primary,
            unselectedLabelColor: colorScheme.onSurfaceVariant,
            indicatorColor: colorScheme.primary,
            tabs: const [
              Tab(text: 'General'),
              Tab(text: 'Reseller Levels'),
            ],
          ),
          Expanded(
            child: TabBarView(
              children: [
                _buildGeneralTab(theme, colorScheme),
                _buildResellerLevelsTab(theme, colorScheme),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildGeneralTab(ThemeData theme, ColorScheme colorScheme) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Expanded(child: Text('Dark mode')),
              Switch(value: _dark, onChanged: _onToggle),
            ],
          ),
          const SizedBox(height: 24),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: _syncing || _restoring ? null : _syncToCloud,
              icon: _syncing
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.cloud_upload_outlined),
              label: Padding(
                padding: const EdgeInsets.symmetric(vertical: 14.0),
                child: Text(_syncing ? 'Syncing...' : 'Sync to Cloud'),
              ),
            ),
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: _syncing || _restoring ? null : _restoreFromCloud,
              icon: _restoring
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.cloud_download_outlined),
              label: Padding(
                padding: const EdgeInsets.symmetric(vertical: 14.0),
                child: Text(_restoring ? 'Restoring...' : 'Restore from Cloud'),
              ),
            ),
          ),
          const SizedBox(height: 12),
          // Clear Database button
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: colorScheme.error,
                foregroundColor: Colors.white,
                textStyle: const TextStyle(
                  inherit: false,
                  fontWeight: FontWeight.bold,
                ),
              ),
              onPressed: () async {
                final confirmed = await showDialog<bool>(
                  context: context,
                  builder: (ctx) => AlertDialog(
                    title: const Text('Clear database'),
                    content: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'This will permanently delete all records from '
                          'the local database.',
                        ),
                        const SizedBox(height: 12),
                        Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: Theme.of(
                              ctx,
                            ).colorScheme.error.withAlpha(30),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(
                              color: Theme.of(
                                ctx,
                              ).colorScheme.error.withAlpha(80),
                            ),
                          ),
                          child: const Row(
                            children: [
                              Icon(
                                Icons.warning_amber_rounded,
                                color: Colors.red,
                                size: 20,
                              ),
                              SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  'Do NOT sync to cloud after clearing — '
                                  'it will wipe your cloud data too.',
                                  style: TextStyle(fontWeight: FontWeight.w600),
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 8),
                        const Text(
                          'Please export your data before proceeding.',
                          style: TextStyle(fontStyle: FontStyle.italic),
                        ),
                      ],
                    ),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.pop(ctx, false),
                        child: const Text('Cancel'),
                      ),
                      ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: colorScheme.error,
                          foregroundColor: Colors.white,
                          textStyle: const TextStyle(
                            inherit: false,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        onPressed: () => Navigator.pop(ctx, true),
                        child: const Text('Clear'),
                      ),
                    ],
                  ),
                );

                if (confirmed == true) {
                  try {
                    await repository.clearAllData();
                    if (!context.mounted) return;
                    BotToast.showText(
                      text:
                          '⚠ Database cleared. Do NOT sync to cloud or cloud data will be lost.',
                      duration: const Duration(seconds: 4),
                    );
                  } catch (e) {
                    if (!context.mounted) return;
                    BotToast.showText(text: 'Failed to clear database: $e');
                  }
                }
              },
              child: const Padding(
                padding: EdgeInsets.symmetric(vertical: 14.0),
                child: Text(
                  'Clear Database',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
              ),
            ),
          ),
        ],
      ),
    );
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
