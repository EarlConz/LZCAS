import 'package:flutter/material.dart';
import 'package:lzcas/data/supabase_config.dart';
import 'package:lzcas/data/supabase_sync_service.dart';
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

  void _onToggle(bool val) {
    setState(() => _dark = val);
    widget.onToggle?.call(_dark);
  }

  Future<void> _syncToCloud() async {
    if (!SupabaseConfig.isConfigured) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Supabase is not configured for this run')),
      );
      return;
    }

    setState(() => _syncing = true);
    try {
      final syncService = SupabaseSyncService(
        db: repository.db,
        client: supabaseClient,
      );
      await syncService.uploadLocalSnapshot();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Local data synced to Supabase')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to sync to Supabase: $e')),
      );
    } finally {
      if (mounted) {
        setState(() => _syncing = false);
      }
    }
  }

  @override
  void initState() {
    super.initState();
    _dark = widget.initialDark;
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
    return Padding(
      padding: const EdgeInsets.all(20.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 8),
          const SizedBox(height: 20),
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
              onPressed: _syncing ? null : _syncToCloud,
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
          // Clear Database button
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: Theme.of(context).colorScheme.error,
                foregroundColor: Colors.white,
                textStyle: const TextStyle(inherit: false, fontWeight: FontWeight.bold),
              ),
              onPressed: () async {
                final confirmed = await showDialog<bool>(
                  context: context,
                  builder: (ctx) => AlertDialog(
                    title: const Text('Clear database'),
                    content: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: const [
                        Text('This will permanently delete all records from the local database.'),
                        SizedBox(height: 8),
                        Text(
                          'Please export your data before proceeding.',
                          style: TextStyle(fontStyle: FontStyle.italic),
                        ),
                      ],
                    ),
                    actions: [
                      TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
                      ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Theme.of(context).colorScheme.error,
                          foregroundColor: Colors.white,
                          textStyle: const TextStyle(inherit: false, fontWeight: FontWeight.bold),
                        ),
                        onPressed: () => Navigator.pop(ctx, true),
                        child: const Text('Clear'),
                      ),
                    ],
                  ),
                );

                if (confirmed == true) {
                  // perform clear
                  try {
                    await repository.clearAllData();
                    if (!context.mounted) return;
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Database cleared')),
                    );
                  } catch (e) {
                    if (!context.mounted) return;
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('Failed to clear database: $e')),
                    );
                  }
                }
              },
              child: const Padding(
                padding: EdgeInsets.symmetric(vertical: 14.0),
                child: Text('Clear Database', style: TextStyle(fontWeight: FontWeight.bold)),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
