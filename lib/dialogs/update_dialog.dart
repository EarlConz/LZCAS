// lib/dialogs/update_dialog.dart
// Mihon-style update dialog — shows release notes, download progress,
// and post-download install action. Matches the GUTVita design system.

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/updater_service.dart';
import '../theme.dart';
import '../utils/fonts.dart';

class UpdateDialog extends StatefulWidget {
  const UpdateDialog({super.key});

  /// Show the update dialog if an update is available. Does nothing if
  /// the UpdaterService is not in the [UpdateStatus.updateAvailable] state.
  static Future<void> showIfAvailable(BuildContext context) async {
    final updater = context.read<UpdaterService>();
    if (updater.status != UpdateStatus.updateAvailable) return;

    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => const UpdateDialog(),
    );
    // Reset after dialog closes so a re-check can fire again later.
    updater.reset();
  }

  @override
  State<UpdateDialog> createState() => _UpdateDialogState();
}

class _UpdateDialogState extends State<UpdateDialog> {
  bool _downloading = false;
  bool _opening = false;
  late final UpdaterService _updater;

  @override
  void initState() {
    super.initState();
    // Capture the service here (context.read is safe in initState) so dispose()
    // can detach the listener without looking up a deactivated ancestor.
    _updater = context.read<UpdaterService>();
    // Rebuild when the service notifies (progress / status changes).
    _updater.addListener(_onServiceChanged);
  }

  @override
  void dispose() {
    _updater.removeListener(_onServiceChanged);
    super.dispose();
  }

  void _onServiceChanged() {
    if (!mounted) return;
    setState(() {});
  }

  Future<void> _startDownload() async {
    if (_downloading) return;
    setState(() => _downloading = true);
    final updater = context.read<UpdaterService>();
    final ok = await updater.downloadUpdate();
    if (!mounted) return;
    setState(() => _downloading = false);
    if (ok) {
      // Auto-open after download completes.
      await _openInstaller();
    }
  }

  Future<void> _openInstaller() async {
    if (_opening) return;
    setState(() => _opening = true);
    final updater = context.read<UpdaterService>();
    await updater.openDownloadedFile();
    if (!mounted) return;
    setState(() => _opening = false);
    // Close the dialog regardless — the installer/APK will take over.
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final updater = context.watch<UpdaterService>();
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final info = updater.updateInfo;
    final mandatory = info?.mandatory ?? false;

    return PopScope(
      // A mandatory update cannot be dismissed with the back button / Esc.
      canPop: !mandatory,
      child: AlertDialog(
        insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 60),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(24),
          side: BorderSide(
            color:
                isDark ? StockpileColors.darkDivider : StockpileColors.divider,
          ),
        ),
        backgroundColor:
            isDark ? StockpileColors.darkSurface : StockpileColors.surface,
        surfaceTintColor: Colors.transparent,
        titlePadding: EdgeInsets.zero,
        contentPadding: const EdgeInsets.fromLTRB(24, 0, 24, 8),
        actionsPadding: const EdgeInsets.fromLTRB(24, 4, 24, 20),
        title: _buildHeader(isDark, mandatory),
        content: _buildContent(updater, info, isDark),
        actions: _buildActions(updater, isDark, mandatory),
      ),
    );
  }

  Widget _buildHeader(bool isDark, bool mandatory) {
    return Container(
      padding: const EdgeInsets.fromLTRB(24, 22, 24, 16),
      decoration: BoxDecoration(
        color: StockpileColors.primary900.withAlpha(isDark ? 30 : 18),
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: StockpileColors.primary900.withAlpha(isDark ? 50 : 30),
              borderRadius: BorderRadius.circular(14),
            ),
            child: const Icon(
              Icons.system_update_rounded,
              color: StockpileColors.primary900,
              size: 24,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  mandatory ? 'Required Update' : 'Update Available',
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: StockpileColors.primary900,
                    letterSpacing: 0.5,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  mandatory
                      ? 'You must update to continue'
                      : 'A new version is ready',
                  style: StockpileFonts.satoshi(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    color: isDark
                        ? StockpileColors.darkTextPrimary
                        : StockpileColors.darkText,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildContent(UpdaterService updater, UpdateInfo? info, bool isDark) {
    return SizedBox(
      width: 440,
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            // ── Version info ──────────────────────────────────────
            if (info != null) ...[
              const SizedBox(height: 20),
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: StockpileColors.primary900,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      'v${info.version}',
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w700,
                        fontSize: 13,
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Text(
                    _formatSize(info.fileSize),
                    style: TextStyle(
                      fontSize: 12,
                      color: isDark
                          ? StockpileColors.darkTextMuted
                          : StockpileColors.mutedText,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),

              // ── Changelog ──────────────────────────────────────
              Text(
                "What's New",
                style: StockpileFonts.satoshi(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: isDark
                      ? StockpileColors.darkTextPrimary
                      : StockpileColors.darkText,
                ),
              ),
              const SizedBox(height: 8),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: isDark
                      ? StockpileColors.darkInputBg
                      : StockpileColors.inputBg,
                  borderRadius: BorderRadius.circular(12),
                ),
                constraints: const BoxConstraints(maxHeight: 160),
                child: SingleChildScrollView(
                  child: Text(
                    info.changelog,
                    style: TextStyle(
                      fontSize: 13,
                      height: 1.5,
                      color: isDark
                          ? StockpileColors.darkTextBody
                          : StockpileColors.bodyText,
                    ),
                  ),
                ),
              ),
            ],

            // ── Download progress ────────────────────────────────
            if (updater.status == UpdateStatus.downloading) ...[
              const SizedBox(height: 20),
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: LinearProgressIndicator(
                  value: updater.downloadProgress > 0
                      ? updater.downloadProgress
                      : null,
                  minHeight: 8,
                  backgroundColor: isDark
                      ? StockpileColors.darkDivider
                      : StockpileColors.divider,
                  valueColor: const AlwaysStoppedAnimation<Color>(
                    StockpileColors.primary900,
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Center(
                child: Text(
                  '${(updater.downloadProgress * 100).toStringAsFixed(0)}%',
                  style: StockpileFonts.satoshi(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: StockpileColors.primary900,
                  ),
                ),
              ),
            ],

            // ── Ready state ──────────────────────────────────────
            if (updater.status == UpdateStatus.ready) ...[
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: StockpileColors.successBg,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  children: [
                    const Icon(
                      Icons.check_circle_rounded,
                      color: StockpileColors.success,
                      size: 22,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'Download complete — ready to install.',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: isDark
                              ? StockpileColors.darkTextPrimary
                              : StockpileColors.darkText,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],

            // ── Error state ──────────────────────────────────────
            if (updater.status == UpdateStatus.error &&
                updater.errorMessage != null) ...[
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: StockpileColors.dangerBg,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(
                      Icons.error_outline_rounded,
                      color: StockpileColors.danger,
                      size: 20,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        updater.errorMessage!,
                        style: const TextStyle(
                          fontSize: 12,
                          color: StockpileColors.danger,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  List<Widget> _buildActions(
      UpdaterService updater, bool isDark, bool mandatory) {
    final status = updater.status;

    switch (status) {
      case UpdateStatus.updateAvailable:
        return [
          // "Later" is hidden for a mandatory update — it must be installed.
          if (!mandatory) ...[
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: Text(
                'Later',
                style: TextStyle(
                  fontWeight: FontWeight.w600,
                  color: isDark
                      ? StockpileColors.darkTextMuted
                      : StockpileColors.mutedText,
                ),
              ),
            ),
            const SizedBox(width: 8),
          ],
          FilledButton.icon(
            style: FilledButton.styleFrom(
              backgroundColor: StockpileColors.primary900,
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            icon: const Icon(Icons.download_rounded, size: 18),
            label: const Text('Update Now'),
            onPressed: _startDownload,
          ),
        ];

      case UpdateStatus.downloading:
        return [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text(
              'Cancel',
              style: TextStyle(
                fontWeight: FontWeight.w600,
                color: isDark
                    ? StockpileColors.darkTextMuted
                    : StockpileColors.mutedText,
              ),
            ),
          ),
        ];

      case UpdateStatus.ready:
        return [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text(
              'Close',
              style: TextStyle(
                fontWeight: FontWeight.w600,
                color: isDark
                    ? StockpileColors.darkTextMuted
                    : StockpileColors.mutedText,
              ),
            ),
          ),
          const SizedBox(width: 8),
          FilledButton.icon(
            style: FilledButton.styleFrom(
              backgroundColor: StockpileColors.success,
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            icon: _opening
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : const Icon(Icons.install_mobile_rounded, size: 18),
            label: Text(_opening ? 'Opening…' : 'Install'),
            onPressed: _opening ? null : _openInstaller,
          ),
        ];

      case UpdateStatus.error:
        return [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text(
              'Close',
              style: TextStyle(
                fontWeight: FontWeight.w600,
                color: isDark
                    ? StockpileColors.darkTextMuted
                    : StockpileColors.mutedText,
              ),
            ),
          ),
          const SizedBox(width: 8),
          FilledButton.icon(
            style: FilledButton.styleFrom(
              backgroundColor: StockpileColors.primary900,
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            icon: const Icon(Icons.refresh_rounded, size: 18),
            label: const Text('Retry'),
            onPressed: () {
              updater.reset();
              // Re-check will fire from the caller; just pop and let
              // the auto-check or manual button re-trigger.
              Navigator.of(context).pop();
            },
          ),
        ];

      default:
        return [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Close'),
          ),
        ];
    }
  }

  String _formatSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    if (bytes < 1024 * 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';
  }
}
