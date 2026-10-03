// lib/dialogs/edit_stock_dialog.dart
//
// Edit Product: rename, recategorise, and add or reduce stock, from the
// "Staff Modals Redesign" canvas. Built on widgets/modal_kit.dart, so it is
// a dialog on desktop and a full screen on a phone.
//
// Stock is checked as it is typed (a reduction can't exceed the stock) and
// again by the database (reduce_item_stock, v60). Inventory users don't
// reduce directly: their reduction goes to an admin for approval.

import 'package:flutter/material.dart';
import 'package:bot_toast/bot_toast.dart';
import 'package:provider/provider.dart';
import 'package:lzcas/auth/auth_state.dart';
import 'package:lzcas/db/db.dart';
import 'package:lzcas/services/config_service.dart';
import 'package:lzcas/services/poster_service.dart' show PreparedPoster;
import 'package:lzcas/theme.dart';
import 'package:lzcas/utils/fonts.dart';
import 'package:lzcas/widgets/modal_kit.dart';
import 'package:lzcas/widgets/poster_picker_field.dart';
import 'package:lzcas/widgets/product_tile.dart';

class EditProductDialog extends StatefulWidget {
  final Map<String, dynamic> item;
  final VoidCallback onUpdated;

  const EditProductDialog({
    super.key,
    required this.item,
    required this.onUpdated,
  });

  @override
  State<EditProductDialog> createState() => _EditProductDialogState();
}

enum _StockMode { none, add, reduce }

class _EditProductDialogState extends State<EditProductDialog> {
  late final TextEditingController _name;
  final _amount = TextEditingController();
  final _details = TextEditingController();
  List<String> _categories = [];
  String? _category;

  _StockMode _mode = _StockMode.none;
  String? _reason;

  /// The stock the database reported when it refused a reduction: newer
  /// than the list row this dialog opened with. Null until that happens.
  int? _stockNow;

  /// Shown under the amount after such a refusal, until the amount changes.
  String? _staleError;

  bool _saving = false;

  /// A newly chosen picture, not uploaded yet (v63, admins only).
  PreparedPoster? _photo;

  /// The stored picture was removed and nothing chosen in its place.
  bool _photoCleared = false;

  static const _reasons = [
    'Damaged',
    'Expired',
    'Transferred',
    'Count correction',
    'Other',
  ];

  String get _originalName => (widget.item['name'] as String? ?? '').trim();
  String? get _originalCategory => (widget.item['category'] as String?)?.trim();
  int get _currentStock => _stockNow ?? (widget.item['stock'] as int? ?? 0);
  int get _amountValue => int.tryParse(_amount.text.trim()) ?? 0;
  bool get _isReduce => _mode == _StockMode.reduce;

  bool get _needsApproval =>
      context.read<AuthState>().userRole == UserRole.inventory;

  bool get _detailsChanged =>
      _name.text.trim() != _originalName || (_category ?? '') != (_originalCategory ?? '');

  bool get _stockChanged => _mode != _StockMode.none && _amountValue > 0;

  String? get _storedPhoto => widget.item['imagePath'] as String?;

  bool get _photoChanged =>
      _photo != null || (_photoCleared && (_storedPhoto ?? '').isNotEmpty);

  /// Only admins may write to the picture bucket (v63).
  bool get _canEditPhoto =>
      context.read<AuthState>().userRole == UserRole.admin;

  /// Checked as the amount is typed, so an amount over the stock can never
  /// reach Save. Before this, it was skipped silently: the dialog closed as
  /// if it had worked and the stock never moved.
  String? get _amountError {
    if (!_isReduce) return null;
    if (_staleError != null) return _staleError;
    if (_amountValue > _currentStock) {
      return _currentStock <= 0
          ? 'Nothing to reduce: the stock is 0'
          : 'At most $_currentStock, the current stock';
    }
    return null;
  }

  /// Why Save is off, in words; null when it can save.
  String? get _blocker {
    if (_name.text.trim().isEmpty) return 'A product name is required.';
    if (_amountError != null) return 'Lower the amount to save.';
    if (_isReduce && _amountValue > 0 && _reason == null) {
      return 'Pick a reason for the reduction.';
    }
    if (!_detailsChanged && !_stockChanged && !_photoChanged) {
      return 'Nothing changed yet.';
    }
    return null;
  }

  /// "Damaged" or "Damaged — water damage in storeroom".
  String get _reasonText {
    final d = _details.text.trim();
    return d.isEmpty ? _reason! : '${_reason!} — $d';
  }

  @override
  void initState() {
    super.initState();
    _name = TextEditingController(text: _originalName);
    _category = (_originalCategory?.isNotEmpty ?? false) ? _originalCategory : null;
    _loadCategories();
  }

  Future<void> _loadCategories() async {
    try {
      // Categories come from the Settings-managed category list, not from
      // whatever categories existing products happen to use.
      final cats = await repository.fetchProductCategories();
      final set = <String>{
        for (final c in cats)
          if (c.name.trim().isNotEmpty) c.name.trim(),
      };
      // Keep the product's current category selectable even if it was
      // later removed from Settings, so editing never silently drops it.
      final existing = _originalCategory;
      if (existing != null && existing.isNotEmpty) set.add(existing);
      if (!mounted) return;
      setState(() => _categories = set.toList()..sort());
    } catch (e) {
      debugPrint('Failed to load categories: $e');
    }
  }

  @override
  void dispose() {
    _name.dispose();
    _amount.dispose();
    _details.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_saving || _blocker != null) return;
    setState(() => _saving = true);
    try {
      await _apply();
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  /// The database's stock is lower than the amount: say what it is now and
  /// keep the dialog open so the amount can be corrected.
  void _showStale(int stockNow) {
    setState(() {
      _stockNow = stockNow;
      _staleError =
          'Stock is now $stockNow (it changed since you opened this). '
          'Reduce by at most $stockNow.';
    });
    widget.onUpdated();
  }

  Future<void> _apply() async {
    final amount = _stockChanged ? _amountValue : 0;
    final newName = _name.text.trim();
    final newCategory = _category?.trim();
    final id = widget.item['id'] as int?;

    if (id == null) {
      // In-memory (no database row yet).
      final delta = _mode == _StockMode.add ? amount : -amount;
      widget.item['stock'] = _currentStock + delta;
      widget.item['name'] = newName;
      widget.item['category'] = newCategory;
      widget.item['lastUpdated'] = "${DateTime.now().toLocal()}".split('.')[0];
      widget.onUpdated();
      Navigator.pop(context);
      return;
    }

    // Read before the await: needed for the approval decision below.
    final needsApproval = _needsApproval;
    var sentForApproval = false;

    // The picture first: if it fails, nothing else has changed yet. Once
    // saved it is cleared from the form, so saving again after a refused
    // reduction does not upload it twice.
    if (_photoChanged && !await _savePhoto(id)) return;

    final row = await repository.getItemById(id);
    if (row == null) {
      if (!mounted) return;
      BotToast.showText(text: 'Item not found');
      return;
    }

    // Stock first, so a refused reduction leaves the product exactly as it
    // was: no half-save of the name with the stock untouched.
    if (_mode == _StockMode.add && amount > 0) {
      final ok = await repository.addStock(
        itemId: id,
        itemName: row.name,
        quantity: amount,
      );
      if (!ok) {
        if (!mounted) return;
        BotToast.showText(text: 'Failed to add stock');
        return;
      }
    }

    if (_isReduce && amount > 0) {
      // The list this dialog opened from may be out of date: a sale or
      // another edit since. Check against the stock just read.
      if (row.stock < amount) {
        if (!mounted) return;
        _showStale(row.stock);
        return;
      }

      if (needsApproval) {
        await repository.submitPendingRequest(
          itemId: id,
          itemName: row.name,
          requestType: 'reduce_stock',
          quantity: amount,
          reason: _reasonText,
        );
        sentForApproval = true;
      } else {
        // Checked again by the database (v60), which also stops two
        // reductions at the same moment from both going through.
        final r = await repository.reduceStock(
          itemId: id,
          quantity: amount,
          reason: _reasonText,
        );
        if (!mounted) return;
        if (r.stockNow != null) {
          _showStale(r.stockNow!);
          return;
        }
        if (r.error != null) {
          BotToast.showText(text: 'Could not reduce stock: ${r.error}');
          return;
        }
      }
    }

    if (_detailsChanged) {
      await repository.updateItem(
        // Re-read: a stock change just rewrote this row's stock and status,
        // and writing the old copy back would undo it.
        ((await repository.getItemById(id)) ?? row).copyWith(
          name: newName,
          category: newCategory,
        ),
      );
    }

    if (!mounted) return;
    if (sentForApproval) {
      BotToast.showText(text: 'Stock reduction sent to an admin for approval');
    }
    widget.onUpdated();
    Navigator.pop(context);
  }

  /// Upload the chosen picture (or none), point the product at it, then
  /// delete the file it replaced. False, with a toast, when it failed.
  Future<bool> _savePhoto(int id) async {
    final old = _storedPhoto;
    final photo = _photo;
    String? path;
    try {
      if (photo != null) {
        path = await repository.uploadProductImage(
          photo.bytes,
          extension: photo.extension,
          contentType: photo.contentType,
        );
      }
      await repository.setItemImage(id, path);
    } catch (e) {
      debugPrint('Saving product picture failed: $e');
      // Uploaded but not linked: don't leave the file behind.
      await repository.deleteProductImage(path);
      if (mounted) {
        BotToast.showText(
          text: 'Could not save the picture. Nothing was changed.',
        );
      }
      return false;
    }
    await repository.deleteProductImage(old);
    widget.item['imagePath'] = path;
    if (mounted) {
      setState(() {
        _photo = null;
        _photoCleared = false;
      });
    }
    return true;
  }

  // ── UI ─────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final text = dark ? StockpileColors.darkTextPrimary : StockpileColors.darkText;
    final muted = dark ? StockpileColors.darkTextMuted : const Color(0xFF6E6E7A);
    final blocker = _blocker;
    final approval = _isReduce && _needsApproval;
    final subtitle = [
      _originalName.isEmpty ? 'Unnamed product' : _originalName,
      if ((_originalCategory ?? '').isNotEmpty) _originalCategory!,
    ].join(' · ');

    return AppModal(
      title: 'Edit product',
      subtitle: subtitle,
      leading: const ModalIconTile(Icons.inventory_2_outlined),
      body: [
        _stockSummary(dark, text, muted),
        ModalSection(
          title: 'Details',
          children: [
            FieldPair(
              LabeledField(
                label: 'Name',
                required: true,
                child: TextField(
                  controller: _name,
                  textInputAction: TextInputAction.next,
                  onChanged: (_) => setState(() {}),
                ),
              ),
              LabeledField(
                label: 'Category',
                child: DropdownButtonFormField<String>(
                  isExpanded: true,
                  initialValue: _categories.contains(_category) ? _category : null,
                  hint: const Text('Select category'),
                  items: [
                    for (final c in _categories)
                      DropdownMenuItem(value: c, child: Text(c, overflow: TextOverflow.ellipsis)),
                  ],
                  onChanged: (v) => setState(() => _category = v),
                ),
              ),
            ),
          ],
        ),
        if (_canEditPhoto && widget.item['id'] != null)
          ModalSection(
            title: 'Picture',
            children: [
              PosterPickerField(
                storedPath: _storedPhoto,
                pending: _photo,
                cleared: _photoCleared,
                enabled: !_saving,
                isDark: dark,
                label: 'Shown in the Marketplace',
                addLabel: 'Add picture',
                emptyLabel: 'No picture: members see its letter instead',
                helper: 'JPG or PNG. It is resized for you. A square photo '
                    'fits best.',
                maxEdge: 1200,
                storedPreview: ProductTile(
                  _originalName,
                  imagePath: _storedPhoto,
                  height: 180,
                ),
                onPicked: (p) => setState(() {
                  _photo = p;
                  _photoCleared = false;
                }),
                onCleared: () => setState(() {
                  _photo = null;
                  _photoCleared = true;
                }),
              ),
            ],
          ),
        ModalSection(
          title: 'Change stock',
          children: [
            SegmentedChoice<_StockMode>(
              options: const [
                (_StockMode.none, 'No change'),
                (_StockMode.add, 'Add'),
                (_StockMode.reduce, 'Reduce'),
              ],
              value: _mode,
              onChanged: (m) => setState(() {
                _mode = m;
                _staleError = null;
              }),
            ),
            if (_mode != _StockMode.none) _amountRow(dark, text, muted),
            if (_isReduce) ...[
              LabeledField(
                label: 'Reason',
                required: true,
                child: ChoicePills(
                  options: _reasons,
                  value: _reason,
                  onChanged: (r) => setState(() => _reason = r),
                ),
              ),
              TextField(
                controller: _details,
                decoration: const InputDecoration(
                  hintText: 'Details (optional) — e.g. water damage in storeroom',
                ),
              ),
              if (approval)
                ModalNote(
                  tone: ModalTone.info,
                  icon: Icons.verified_user_outlined,
                  title: 'An admin approves reductions first.',
                  body: 'The stock stays at $_currentStock until they do. '
                      'The request appears under My Requests.',
                ),
            ],
          ],
        ),
      ],
      footerNote: Text(
        blocker ?? (_stockChanged ? 'Recorded in stock history under your name.' : ''),
        style: StockpileFonts.satoshi(
          fontSize: 12,
          fontWeight: _amountError != null ? FontWeight.w600 : FontWeight.w400,
          color: _amountError != null ? const Color(0xFFB91C1C) : muted,
        ),
      ),
      primaryAction: FilledButton(
        onPressed: _saving || blocker != null ? null : _save,
        child: _saving
            ? const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : Text(approval ? 'Send for approval' : 'Save changes'),
      ),
    );
  }

  Widget _stockSummary(bool dark, Color text, Color muted) {
    final stock = _currentStock;
    final threshold = context.read<ConfigService>().thresholdForCategory(_category);
    final (label, tone) = stock <= 0
        ? ('Out of stock', ModalTone.danger)
        : stock < threshold
        ? ('Low stock', ModalTone.warn)
        : ('In good supply', ModalTone.neutral);
    final (bg, fg) = tone.colors(dark);
    final updated = widget.item['lastUpdated']?.toString();
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: dark ? StockpileColors.darkInputBg : StockpileColors.inputBg,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('In stock now', style: StockpileFonts.satoshi(fontSize: 12, color: muted)),
                Text(
                  '$stock',
                  style: StockpileFonts.satoshi(fontSize: 28, fontWeight: FontWeight.w700, color: text),
                ),
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(8)),
                child: Text(label, style: StockpileFonts.satoshi(fontSize: 12, fontWeight: FontWeight.w700, color: fg)),
              ),
              if (updated != null && updated.isNotEmpty) ...[
                const SizedBox(height: 4),
                Text('Updated $updated', style: StockpileFonts.satoshi(fontSize: 12, color: muted)),
              ],
            ],
          ),
        ],
      ),
    );
  }

  /// The stepper, and what the stock becomes.
  Widget _amountRow(bool dark, Color text, Color muted) {
    final stock = _currentStock;
    final n = _amountValue;
    final after = _isReduce ? stock - n : stock + n;
    final bad = _amountError != null;

    final preview = n <= 0
        ? null
        : Container(
            height: 48,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            decoration: BoxDecoration(
              color: bad ? (dark ? const Color(0x33B91C1C) : const Color(0xFFFEF2F2)) : null,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: bad
                    ? const Color(0xFFF5B4B4)
                    : (dark ? StockpileColors.darkDivider : StockpileColors.divider),
              ),
            ),
            alignment: Alignment.center,
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text('$stock', style: StockpileFonts.satoshi(fontSize: 16, fontWeight: FontWeight.w600, color: muted)),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    child: Icon(Icons.arrow_forward_rounded, size: 18, color: muted),
                  ),
                  Text(
                    bad ? '$after' : '$after in stock',
                    style: StockpileFonts.satoshi(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      color: bad ? const Color(0xFFB91C1C) : text,
                      decoration: bad ? TextDecoration.lineThrough : null,
                    ),
                  ),
                  if (bad) ...[
                    const SizedBox(width: 8),
                    Text(
                      "can't go below 0",
                      style: StockpileFonts.satoshi(fontSize: 13, fontWeight: FontWeight.w600, color: const Color(0xFFB91C1C)),
                    ),
                  ],
                ],
              ),
            ),
          );

    return LabeledField(
      label: _isReduce ? 'Amount to reduce' : 'Amount to add',
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          NumberStepper(
            controller: _amount,
            semanticLabel: _isReduce ? 'Amount to reduce' : 'Amount to add',
            min: 0,
            max: _isReduce ? stock : null,
            errorText: _amountError,
            helperText: _isReduce ? 'Up to $stock' : null,
            onChanged: (_) => setState(() => _staleError = null),
          ),
          if (preview != null) ...[
            const SizedBox(width: 12),
            Expanded(child: preview),
          ],
        ],
      ),
    );
  }
}
