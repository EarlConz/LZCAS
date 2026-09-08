// lib/widgets/poster_picker_field.dart
//
// The admin-side control for attaching a poster — used by the announcement
// editor and by the birthday greeting settings, which need exactly the same
// thing and had no business growing two versions of it.
//
// Controlled, not self-managing: the parent owns the choice, because the
// parent is what has to upload it on save and clean up the replaced file.
// This widget only picks and previews.

import 'package:flutter/material.dart';

import 'package:lzcas/services/poster_service.dart';
import 'package:lzcas/theme.dart';
import 'package:lzcas/utils/fonts.dart';
import 'package:lzcas/utils/toast_utils.dart';
import 'package:lzcas/widgets/poster_image.dart';

class PosterPickerField extends StatefulWidget {
  /// The poster already stored on the row, if any.
  final String? storedPath;

  /// A newly chosen image, not yet uploaded. Takes precedence over
  /// [storedPath] in the preview — it is what will be saved.
  final PreparedPoster? pending;

  /// True when the admin removed the stored poster and picked nothing to
  /// replace it. Distinct from "never had one", because saving has to write
  /// a null rather than leave the old path alone.
  final bool cleared;

  final bool enabled;
  final bool isDark;

  final ValueChanged<PreparedPoster> onPicked;
  final VoidCallback onCleared;

  final String label;
  final String helper;

  const PosterPickerField({
    super.key,
    required this.storedPath,
    required this.pending,
    required this.cleared,
    required this.enabled,
    required this.isDark,
    required this.onPicked,
    required this.onCleared,
    this.label = 'Poster',
    this.helper = 'Optional. JPG or PNG — it is resized for you.',
  });

  /// Whether anything is currently attached, from either source.
  bool get _hasPoster =>
      pending != null || (!cleared && (storedPath ?? '').trim().isNotEmpty);

  @override
  State<PosterPickerField> createState() => _PosterPickerFieldState();
}

class _PosterPickerFieldState extends State<PosterPickerField> {
  bool _picking = false;

  Future<void> _pick() async {
    if (_picking || !widget.enabled) return;
    setState(() => _picking = true);
    try {
      final poster = await pickPoster();
      if (poster != null) widget.onPicked(poster);
    } on PosterException catch (e) {
      // Written to be shown as-is: "That image is 41.2 MB. Pick one under…"
      showErrorToast(e.message);
    } catch (e) {
      showErrorToast('That image could not be opened.');
    } finally {
      if (mounted) setState(() => _picking = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = widget.isDark;
    final muted = isDark
        ? StockpileColors.darkTextMuted
        : StockpileColors.mutedText;
    final border = isDark
        ? StockpileColors.darkDivider
        : StockpileColors.divider;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: isDark ? StockpileColors.darkInputBg : StockpileColors.inputBg,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Icon(Icons.image_outlined, size: 18, color: muted),
              const SizedBox(width: 8),
              Text(
                widget.label,
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
          const SizedBox(height: 10),
          if (widget._hasPoster) _preview(isDark) else _empty(muted),
          const SizedBox(height: 10),
          // Wrap, not Row: "Replace" and "Remove" side by side with their
          // icons need ~210px, and this field sits inside a dialog that goes
          // down to phone width.
          Wrap(
            spacing: 4,
            runSpacing: 4,
            children: [
              TextButton.icon(
                onPressed: widget.enabled && !_picking ? _pick : null,
                icon: _picking
                    ? const SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.upload_rounded, size: 18),
                label: Text(widget._hasPoster ? 'Replace' : 'Add poster'),
              ),
              if (widget._hasPoster)
                TextButton.icon(
                  onPressed: widget.enabled && !_picking
                      ? widget.onCleared
                      : null,
                  icon: const Icon(Icons.delete_outline_rounded, size: 18),
                  label: const Text('Remove'),
                  style: TextButton.styleFrom(
                    foregroundColor: StockpileColors.danger,
                  ),
                ),
            ],
          ),
          Text(
            widget.helper,
            style: StockpileFonts.satoshi(fontSize: 11, color: muted),
          ),
        ],
      ),
    );
  }

  /// A newly picked image is drawn from memory — it has not been uploaded
  /// yet, so there is no path to sign. A stored one goes through the normal
  /// signed-URL path.
  Widget _preview(bool isDark) {
    final pending = widget.pending;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(10),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 200),
            child: SizedBox(
              width: double.infinity,
              child: pending != null
                  ? Image.memory(pending.bytes, fit: BoxFit.contain)
                  : PosterImage(
                      path: widget.storedPath,
                      isDark: isDark,
                      fit: BoxFit.contain,
                      borderRadius: 10,
                      openOnTap: true,
                    ),
            ),
          ),
        ),
        if (pending != null) ...[
          const SizedBox(height: 6),
          Text(
            // Says what was actually done to their file — an admin who
            // uploaded a 6 MB photo should see that it shrank, not wonder.
            '${pending.width}×${pending.height} · ${pending.sizeLabel} · '
            'ready to upload',
            style: StockpileFonts.satoshi(
              fontSize: 11,
              color: isDark
                  ? StockpileColors.darkTextMuted
                  : StockpileColors.mutedText,
            ),
          ),
        ],
      ],
    );
  }

  Widget _empty(Color muted) {
    return Container(
      width: double.infinity,
      height: 76,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: muted.withValues(alpha: 0.35)),
      ),
      alignment: Alignment.center,
      child: Text(
        'No poster — text only',
        style: StockpileFonts.satoshi(fontSize: 12, color: muted),
      ),
    );
  }
}
