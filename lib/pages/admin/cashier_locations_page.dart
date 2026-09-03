// lib/pages/admin/cashier_locations_page.dart
//
// Admin: see where every cashier and branch cashier has placed themselves on
// the members' Nearest Cashiers map, and remove a location that is wrong.
//
// The point of this page is oversight, and oversight needs two things the
// member map does not show:
//
//   • The cashiers who have set NO location. They are invisible to members
//     and, because only the cashier can set their own, nobody would ever find
//     out from the map itself. They are listed here explicitly.
//   • A way to undo. A mis-tapped search result or an IP-derived point in the
//     wrong province is otherwise permanent — the cashier may not even know
//     it is wrong, and the admin previously had no recourse short of SQL.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import 'package:lzcas/db/db.dart';
import 'package:lzcas/theme.dart';
import 'package:lzcas/utils/fonts.dart';
import 'package:lzcas/utils/formatters.dart' show formatRelativeDate;
import 'package:lzcas/utils/toast_utils.dart';

/// Which slice of the roster is showing.
enum _RoleFilter {
  all('All'),
  cashier('Cashiers', 'cashier'),
  branchCashier('Branch Cashiers', 'branch_cashier');

  const _RoleFilter(this.label, [this.dbValue]);

  final String label;

  /// The exact `profiles.role` string, or null for [all].
  final String? dbValue;

  bool matches(UserProfile p) => dbValue == null || p.role == dbValue;
}

class AdminCashierLocationsPage extends StatefulWidget {
  const AdminCashierLocationsPage({super.key});

  @override
  State<AdminCashierLocationsPage> createState() =>
      _AdminCashierLocationsPageState();
}

class _AdminCashierLocationsPageState extends State<AdminCashierLocationsPage> {
  List<UserProfile> _profiles = const [];
  bool _loading = true;
  _RoleFilter _filter = _RoleFilter.all;
  StreamSubscription<String>? _sub;

  @override
  void initState() {
    super.initState();
    _load();
    // A cashier saving or clearing their own location while this page is open
    // should be reflected without a manual refresh.
    _sub = repository.changes.listen((e) {
      if (e == 'cashier_location_updated' && mounted) _load();
    });
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final rows = await repository.fetchCashierProfiles();
      if (!mounted) return;
      setState(() {
        _profiles = rows;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
      showErrorToast('Could not load cashier locations: $e');
    }
  }

  // ── Derived lists ─────────────────────────────────────────────────────────

  List<UserProfile> get _visible =>
      _profiles.where(_filter.matches).toList(growable: false);

  List<UserProfile> get _located =>
      _visible.where(_hasLocation).toList(growable: false);

  List<UserProfile> get _unlocated =>
      _visible.where((p) => !_hasLocation(p)).toList(growable: false);

  static bool _hasLocation(UserProfile p) =>
      p.latitude != null && p.longitude != null;

  // ── Actions ───────────────────────────────────────────────────────────────

  Future<void> _clear(UserProfile profile) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        title: const Text('Remove this location?'),
        content: Text(
          '${profile.username} will disappear from the members’ Nearest '
          'Cashiers map until they set a location again from their own '
          'dashboard. You cannot set it for them.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: StockpileColors.danger,
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Remove'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    try {
      await repository.clearCashierLocation(userId: profile.id);
      if (!mounted) return;
      showSuccessToast('Location removed for ${profile.username}');
      await _load();
    } catch (e) {
      if (!mounted) return;
      showErrorToast('Could not remove location: $e');
    }
  }

  /// Copy to the clipboard in the order Google Maps and every mapping tool
  /// expects, so an admin can paste it straight in to check a suspect point.
  Future<void> _copyCoordinates(UserProfile profile) async {
    final text = '${profile.latitude}, ${profile.longitude}';
    await Clipboard.setData(ClipboardData(text: text));
    if (!mounted) return;
    showSuccessToast('Copied $text');
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textColor = isDark
        ? StockpileColors.darkTextPrimary
        : StockpileColors.darkText;
    final muted = isDark
        ? StockpileColors.darkTextMuted
        : StockpileColors.mutedText;

    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(
                Icons.pin_drop_rounded,
                color: StockpileColors.primary900,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Cashier Locations',
                  style: StockpileFonts.satoshi(
                    fontSize: 22,
                    fontWeight: FontWeight.w700,
                    color: textColor,
                  ),
                ),
              ),
              IconButton(
                tooltip: 'Refresh',
                icon: const Icon(Icons.refresh_rounded),
                onPressed: _load,
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            'Where each cashier appears on the members’ Nearest Cashiers '
            'map. Cashiers set their own location — you can review it and '
            'remove one that is wrong.',
            style: StockpileFonts.satoshi(fontSize: 13, color: muted),
          ),
          const SizedBox(height: 16),
          _CoverageBanner(
            located: _located.length,
            total: _visible.length,
            isDark: isDark,
          ),
          const SizedBox(height: 16),
          _buildFilterChips(isDark, muted),
          const SizedBox(height: 16),
          if (_located.isNotEmpty) ...[_buildMap(), const SizedBox(height: 16)],
          _buildRoster(isDark, textColor, muted),
        ],
      ),
    );
  }

  Widget _buildFilterChips(bool isDark, Color muted) {
    return Wrap(
      spacing: 8,
      children: [
        for (final f in _RoleFilter.values)
          ChoiceChip(
            label: Text('${f.label} (${_countFor(f)})'),
            selected: _filter == f,
            onSelected: (_) => setState(() => _filter = f),
            labelStyle: StockpileFonts.satoshi(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: _filter == f ? StockpileColors.primary900 : muted,
            ),
            selectedColor: StockpileColors.primary900.withAlpha(30),
            backgroundColor: isDark
                ? StockpileColors.darkInputBg
                : StockpileColors.inputBg,
            side: BorderSide(
              color: _filter == f
                  ? StockpileColors.primary900
                  : (isDark
                        ? StockpileColors.darkDivider
                        : StockpileColors.divider),
            ),
          ),
      ],
    );
  }

  int _countFor(_RoleFilter f) => _profiles.where(f.matches).length;

  /// The same OpenStreetMap view members see, framed so every pin fits.
  Widget _buildMap() {
    final points = [
      for (final p in _located) LatLng(p.latitude!, p.longitude!),
    ];

    return ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: SizedBox(
        height: 320,
        child: FlutterMap(
          // Rebuild the map when the marker set changes, otherwise the camera
          // fit is computed once and a filter switch leaves it framing the
          // previous selection.
          key: ValueKey(
            points.map((p) => '${p.latitude},${p.longitude}').join(),
          ),
          options: MapOptions(
            initialCenter: points.first,
            initialZoom: 13,
            initialCameraFit: points.length < 2
                ? null
                : CameraFit.bounds(
                    bounds: LatLngBounds.fromPoints(points),
                    padding: const EdgeInsets.all(48),
                    maxZoom: 16,
                  ),
          ),
          children: [
            TileLayer(
              urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
              userAgentPackageName: 'com.lzcas.app',
            ),
            MarkerLayer(
              markers: [
                for (final p in _located)
                  Marker(
                    point: LatLng(p.latitude!, p.longitude!),
                    width: 44,
                    height: 44,
                    child: Tooltip(
                      message: p.username,
                      child: Icon(
                        p.role == 'branch_cashier'
                            ? Icons.storefront_rounded
                            : Icons.point_of_sale_rounded,
                        size: 34,
                        color: StockpileColors.primary900,
                        shadows: const [
                          Shadow(color: Colors.white, blurRadius: 4),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildRoster(bool isDark, Color textColor, Color muted) {
    final divider = isDark
        ? StockpileColors.darkDivider
        : StockpileColors.divider;

    // Located first: the unset rows are the exceptions and read better as a
    // tail than scattered alphabetically through the list.
    final rows = [..._located, ..._unlocated];

    return Card(
      elevation: 0,
      color: isDark ? StockpileColors.darkSurface : StockpileColors.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: divider),
      ),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: rows.isEmpty
            ? Padding(
                padding: const EdgeInsets.symmetric(vertical: 24),
                child: Center(
                  child: Text(
                    'No ${_filter.label.toLowerCase()} accounts exist yet.',
                    style: StockpileFonts.satoshi(fontSize: 13, color: muted),
                  ),
                ),
              )
            : Column(
                children: [
                  for (var i = 0; i < rows.length; i++) ...[
                    if (i > 0) ...[
                      const SizedBox(height: 14),
                      Divider(height: 1, color: divider.withAlpha(120)),
                      const SizedBox(height: 14),
                    ],
                    _CashierRow(
                      profile: rows[i],
                      isDark: isDark,
                      textColor: textColor,
                      muted: muted,
                      onClear: _hasLocation(rows[i])
                          ? () => _clear(rows[i])
                          : null,
                      onCopy: _hasLocation(rows[i])
                          ? () => _copyCoordinates(rows[i])
                          : null,
                    ),
                  ],
                ],
              ),
      ),
    );
  }
}

// ─── Coverage banner ────────────────────────────────────────────────────────

/// States plainly how many cashiers members can actually find.
///
/// Same reasoning as the birthday-greeting coverage line: a feature that
/// quietly does nothing for part of the list is worse than one that says so.
class _CoverageBanner extends StatelessWidget {
  final int located;
  final int total;
  final bool isDark;

  const _CoverageBanner({
    required this.located,
    required this.total,
    required this.isDark,
  });

  @override
  Widget build(BuildContext context) {
    final missing = total - located;
    final allSet = missing == 0 && total > 0;

    final color = allSet ? StockpileColors.success : StockpileColors.primary900;
    final bg = allSet
        ? StockpileColors.successBg
        : StockpileColors.primary900.withAlpha(20);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDark ? color.withAlpha(28) : bg,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withAlpha(70)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            allSet ? Icons.check_circle_rounded : Icons.info_outline_rounded,
            size: 20,
            color: color,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              total == 0
                  ? 'No cashier accounts in this view.'
                  : allSet
                  ? 'All $total have set a location — every one of them is '
                        'findable by members.'
                  : '$located of $total have set a location. '
                        '$missing ${missing == 1 ? 'is' : 'are'} invisible on '
                        'the members’ map until they set one themselves.',
              style: StockpileFonts.satoshi(
                fontSize: 13,
                height: 1.4,
                color: isDark ? StockpileColors.darkTextPrimary : color,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ─── One roster row ─────────────────────────────────────────────────────────

class _CashierRow extends StatelessWidget {
  final UserProfile profile;
  final bool isDark;
  final Color textColor;
  final Color muted;

  /// Null when there is no location, which also greys the row out.
  final VoidCallback? onClear;
  final VoidCallback? onCopy;

  const _CashierRow({
    required this.profile,
    required this.isDark,
    required this.textColor,
    required this.muted,
    required this.onClear,
    required this.onCopy,
  });

  bool get _hasLocation => onClear != null;
  bool get _isBranch => profile.role == 'branch_cashier';

  @override
  Widget build(BuildContext context) {
    final address = profile.address?.trim() ?? '';

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        CircleAvatar(
          radius: 20,
          backgroundColor: _hasLocation
              ? StockpileColors.primary900.withAlpha(25)
              : (isDark
                    ? StockpileColors.darkInputBg
                    : StockpileColors.inputBg),
          child: Icon(
            _hasLocation
                ? (_isBranch
                      ? Icons.storefront_rounded
                      : Icons.point_of_sale_rounded)
                : Icons.location_off_rounded,
            size: 20,
            color: _hasLocation ? StockpileColors.primary900 : muted,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Flexible(
                    child: Text(
                      profile.username,
                      overflow: TextOverflow.ellipsis,
                      style: StockpileFonts.satoshi(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: textColor,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  _RoleChip(isBranch: _isBranch, isDark: isDark),
                ],
              ),
              const SizedBox(height: 4),
              if (!_hasLocation)
                Text(
                  'No location set — not shown to members.',
                  style: StockpileFonts.satoshi(
                    fontSize: 13,
                    height: 1.4,
                    color: muted,
                  ),
                )
              else ...[
                Text(
                  address.isEmpty ? 'Address unavailable' : address,
                  style: StockpileFonts.satoshi(
                    fontSize: 13,
                    height: 1.4,
                    color: textColor,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  '${profile.latitude!.toStringAsFixed(5)}, '
                  '${profile.longitude!.toStringAsFixed(5)}'
                  '${profile.locationUpdatedAt != null ? ' · set ${formatRelativeDate(profile.locationUpdatedAt).toLowerCase()}' : ''}',
                  style: StockpileFonts.satoshi(fontSize: 11, color: muted),
                ),
              ],
            ],
          ),
        ),
        if (_hasLocation) ...[
          const SizedBox(width: 8),
          IconButton(
            tooltip: 'Copy coordinates',
            icon: const Icon(Icons.content_copy_rounded, size: 18),
            color: muted,
            onPressed: onCopy,
          ),
          IconButton(
            tooltip: 'Remove location',
            icon: const Icon(Icons.location_off_rounded, size: 18),
            color: StockpileColors.danger,
            onPressed: onClear,
          ),
        ],
      ],
    );
  }
}

class _RoleChip extends StatelessWidget {
  final bool isBranch;
  final bool isDark;

  const _RoleChip({required this.isBranch, required this.isDark});

  @override
  Widget build(BuildContext context) {
    final bg = isBranch
        ? StockpileColors.secondary50
        : (isDark ? StockpileColors.darkInputBg : StockpileColors.inputBg);
    final fg = isBranch
        ? StockpileColors.secondary500
        : StockpileColors.mutedText;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: isDark && !isBranch ? StockpileColors.darkInputBg : bg,
        borderRadius: BorderRadius.circular(100),
      ),
      child: Text(
        isBranch ? 'Branch Cashier' : 'Cashier',
        style: StockpileFonts.satoshi(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          color: fg,
        ),
      ),
    );
  }
}
