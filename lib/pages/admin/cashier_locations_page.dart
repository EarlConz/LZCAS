// lib/pages/admin/cashier_locations_page.dart
//
// Admin: see where every cashier, branch cashier and rider has placed
// themselves on the members' map, and remove a location that is wrong.
//
// The point of this page is oversight, and oversight is about what is
// WRONG, not what is set. So beyond listing who has a location it flags:
//
//   • No location   — invisible to members; nobody would find out from the
//                     map itself because only the cashier can set their own.
//   • Outside PH    — the classic IP-geolocation miss that lands a branch in
//                     Singapore. Caught without anyone opening a map.
//   • Shared point  — two accounts within 25 m. Two real branches don't
//                     share a pin; two IP-derived defaults do.
//   • Live          — riders only: a position ping in the last 5 minutes
//                     means they are on a delivery right now.
//
// Flags advise, never act. Removing a location is still a deliberate
// click behind the same confirm dialog, and the admin can only remove —
// they cannot set a location for someone else.
//
// The map and the roster are one thing: a pin selects its row, a row pans
// to its pin.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart' show Geolocator;
import 'package:latlong2/latlong.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:lzcas/config/feature_flags.dart';
import 'package:lzcas/db/db.dart';
import 'package:lzcas/theme.dart';
import 'package:lzcas/utils/fonts.dart';
import 'package:lzcas/utils/formatters.dart' show formatAgo, formatRelativeDate;
import 'package:lzcas/utils/toast_utils.dart';
import 'package:lzcas/widgets/map_kit.dart';

// ─── Filters ────────────────────────────────────────────────────────────────

enum _RoleFilter {
  all('All'),
  cashier('Cashiers', 'cashier'),
  branchCashier('Branch Cashiers', 'branch_cashier'),
  rider('Riders', 'delivery');

  const _RoleFilter(this.label, [this.dbValue]);

  final String label;

  /// The exact `profiles.role` string, or null for [all].
  final String? dbValue;

  bool matches(UserProfile p) => dbValue == null || p.role == dbValue;
}

/// The stat tiles double as filters. [all] is "no tile pressed".
enum _StatusFilter { all, located, missing, attention, live }

enum _Sort {
  attention('Needs attention first'),
  name('Name A–Z'),
  recent('Recently set');

  const _Sort(this.label);
  final String label;
}

// ─── A profile plus everything the page computes about it ───────────────────

class _Entry {
  final UserProfile profile;

  /// Username of another located account within 25 m, if any.
  final String? sharedWith;

  const _Entry(this.profile, {this.sharedWith});

  bool get hasLocation => profile.latitude != null && profile.longitude != null;
  LatLng get point => LatLng(profile.latitude!, profile.longitude!);
  bool get isRider => profile.role == 'delivery';

  bool get outsidePh =>
      hasLocation && !isInPhilippines(profile.latitude!, profile.longitude!);

  /// Riders write their position every 60 s while on a delivery (v50), so
  /// a stamp in the last 5 minutes means "on the road right now".
  bool get isLive {
    if (!isRider || !hasLocation) return false;
    final at = profile.locationUpdatedAt;
    return at != null &&
        DateTime.now().difference(at.toLocal()) < const Duration(minutes: 5);
  }

  bool get needsAttention => !hasLocation || outsidePh || sharedWith != null;

  MapPinKind get kind => MapPinKind.forRole(profile.role);
}

// ─── Page ───────────────────────────────────────────────────────────────────

class AdminCashierLocationsPage extends StatefulWidget {
  const AdminCashierLocationsPage({super.key});

  @override
  State<AdminCashierLocationsPage> createState() =>
      _AdminCashierLocationsPageState();
}

class _AdminCashierLocationsPageState extends State<AdminCashierLocationsPage> {
  List<_Entry> _entries = const [];
  bool _loading = true;
  DateTime? _loadedAt;

  _RoleFilter _role = _RoleFilter.all;
  _StatusFilter _status = _StatusFilter.all;
  _Sort _sort = _Sort.attention;
  String _query = '';
  String? _selectedId;

  StreamSubscription<String>? _sub;
  Timer? _clock;
  final _mapController = MapController();
  final _searchCtrl = TextEditingController();
  final Map<String, GlobalKey> _rowKeys = {};

  /// Same-pin threshold. GPS jitter is a few metres; two accounts this
  /// close are either the same shop or the same IP default.
  static const double _sharedMeters = 25;

  @override
  void initState() {
    super.initState();
    _load();
    // A cashier saving or clearing their own location, or a rider pinging,
    // shows up without a manual refresh.
    _sub = repository.changes.listen((e) {
      if (e == 'cashier_location_updated' && mounted) _load();
    });
    // Keeps "Updated 12 s ago" and the riders' live state honest.
    _clock = Timer.periodic(const Duration(seconds: 10), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _sub?.cancel();
    _clock?.cancel();
    _mapController.dispose();
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      // Cashiers and riders come from two queries because the cashier one
      // predates riders and other screens depend on its exact filter.
      final results = await Future.wait([
        repository.fetchCashierProfiles(),
        if (enableDeliverySystem)
          repository.fetchRiders()
        else
          Future.value(const <UserProfile>[]),
      ]);
      if (!mounted) return;
      setState(() {
        _entries = _analyse([...results[0], ...results[1]]);
        _loading = false;
        _loadedAt = DateTime.now();
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
      showErrorToast('Could not load cashier locations: $e');
    }
  }

  /// Computes the shared-point flag once per load — O(n²) over a roster
  /// that is tens of rows, not thousands.
  static List<_Entry> _analyse(List<UserProfile> profiles) {
    final located = profiles
        .where((p) => p.latitude != null && p.longitude != null)
        .toList();
    return [
      for (final p in profiles)
        _Entry(
          p,
          sharedWith: (p.latitude == null || p.longitude == null)
              ? null
              : located
                    .where(
                      (o) =>
                          o.id != p.id &&
                          Geolocator.distanceBetween(
                                p.latitude!,
                                p.longitude!,
                                o.latitude!,
                                o.longitude!,
                              ) <=
                              _sharedMeters,
                    )
                    .map((o) => o.username)
                    .firstOrNull,
        ),
    ];
  }

  // ── Derived lists ─────────────────────────────────────────────────────────

  /// Role + search applied; status not. The stat tiles count from here so
  /// they describe the roster you are looking at.
  List<_Entry> get _inRole {
    final q = _query.trim().toLowerCase();
    return _entries
        .where((e) => _role.matches(e.profile))
        .where((e) => q.isEmpty || e.profile.username.toLowerCase().contains(q))
        .toList(growable: false);
  }

  List<_Entry> get _visible {
    final rows = _inRole
        .where(
          (e) => switch (_status) {
            _StatusFilter.all => true,
            _StatusFilter.located => e.hasLocation,
            _StatusFilter.missing => !e.hasLocation,
            _StatusFilter.attention => e.needsAttention,
            _StatusFilter.live => e.isLive,
          },
        )
        .toList();

    int byName(_Entry a, _Entry b) => a.profile.username
        .toLowerCase()
        .compareTo(b.profile.username.toLowerCase());
    switch (_sort) {
      case _Sort.name:
        rows.sort(byName);
      case _Sort.recent:
        rows.sort((a, b) {
          final ta = a.profile.locationUpdatedAt,
              tb = b.profile.locationUpdatedAt;
          if (ta == null && tb == null) return byName(a, b);
          if (ta == null) return 1;
          if (tb == null) return -1;
          return tb.compareTo(ta);
        });
      case _Sort.attention:
        // Flagged, then located, then unset — each group alphabetical.
        int rank(_Entry e) => !e.hasLocation
            ? 2
            : e.needsAttention
            ? 0
            : 1;
        rows.sort((a, b) {
          final r = rank(a).compareTo(rank(b));
          return r != 0 ? r : byName(a, b);
        });
    }
    return rows;
  }

  List<_Entry> get _located =>
      _visible.where((e) => e.hasLocation).toList(growable: false);

  _Entry? get _selected =>
      _entries.where((e) => e.profile.id == _selectedId).firstOrNull;

  int get _riderTotal => _inRole.where((e) => e.isRider).length;

  // ── Selection: pin ⇄ row ──────────────────────────────────────────────────

  void _selectFromPin(_Entry e) {
    setState(() => _selectedId = e.profile.id);
    final key = _rowKeys[e.profile.id];
    final ctx = key?.currentContext;
    if (ctx != null) {
      Scrollable.ensureVisible(
        ctx,
        alignment: 0.2,
        duration: const Duration(milliseconds: 250),
      );
    }
  }

  void _selectFromRow(_Entry e) {
    setState(
      () => _selectedId = _selectedId == e.profile.id ? null : e.profile.id,
    );
    if (_selectedId != null && e.hasLocation) {
      try {
        _mapController.move(e.point, 15);
      } catch (_) {}
    }
  }

  void _fitAll() =>
      fitCameraTo(_mapController, [for (final e in _located) e.point]);

  // ── Actions ───────────────────────────────────────────────────────────────

  Future<void> _clear(_Entry e) async {
    final p = e.profile;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        title: const Text('Remove this location?'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // What is being removed, so a mis-click on the wrong row is
            // caught here rather than discovered by a member.
            _RemovePreview(entry: e),
            const SizedBox(height: 14),
            Text(
              '${p.username} will disappear from the members’ Nearest '
              'Cashiers map until they set a location again from their own '
              'dashboard. You cannot set it for them.',
              style: Theme.of(ctx).textTheme.bodyMedium,
            ),
          ],
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
      await repository.clearCashierLocation(userId: p.id);
      if (!mounted) return;
      showSuccessToast('Location removed for ${p.username}');
      if (_selectedId == p.id) _selectedId = null;
      await _load();
    } catch (err) {
      if (!mounted) return;
      showErrorToast('Could not remove location: $err');
    }
  }

  /// Copy in the order Google Maps and every mapping tool expects.
  Future<void> _copyCoordinates(_Entry e) async {
    final text = '${e.profile.latitude}, ${e.profile.longitude}';
    await Clipboard.setData(ClipboardData(text: text));
    if (!mounted) return;
    showSuccessToast('Copied $text');
  }

  Future<void> _openInMaps(_Entry e) async {
    final uri = Uri.parse(
      'https://www.google.com/maps/search/?api=1&query='
      '${e.profile.latitude},${e.profile.longitude}',
    );
    if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
      if (mounted) showErrorToast('Could not open a maps app.');
    }
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    return LayoutBuilder(
      builder: (context, constraints) =>
          constraints.maxWidth >= 900 ? _buildWide() : _buildStacked(),
    );
  }

  /// Desktop: header, tiles and toolbar above; map fixed on the left, the
  /// roster scrolling on the right.
  Widget _buildWide() {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _header(wide: true),
          const SizedBox(height: 16),
          _statTiles(),
          const SizedBox(height: 16),
          _toolbar(wide: true),
          const SizedBox(height: 16),
          Expanded(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(flex: 3, child: MapFrame(child: _map())),
                const SizedBox(width: 20),
                Expanded(flex: 2, child: _roster(scrollable: true)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// Phone: one scroll; the map collapses to 200 px with an expand button
  /// and the row actions collapse into the selected row.
  Widget _buildStacked() {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _header(wide: false),
        const SizedBox(height: 12),
        _statTiles(scrollable: true),
        const SizedBox(height: 12),
        _toolbar(wide: false),
        const SizedBox(height: 12),
        MapFrame(height: 200, child: _map(compact: true)),
        const SizedBox(height: 14),
        _roster(scrollable: false),
      ],
    );
  }

  Widget _header({required bool wide}) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final text = isDark
        ? StockpileColors.darkTextPrimary
        : StockpileColors.darkText;
    final muted = isDark
        ? StockpileColors.darkTextMuted
        : StockpileColors.mutedText;
    final freshness = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 7,
          height: 7,
          decoration: const BoxDecoration(
            color: StockpileColors.success,
            shape: BoxShape.circle,
          ),
        ),
        const SizedBox(width: 6),
        Text(
          'Updated ${formatAgo(_loadedAt)}',
          style: StockpileFonts.satoshi(fontSize: 12, color: muted),
        ),
      ],
    );
    final refresh = IconButton(
      tooltip: 'Refresh',
      icon: const Icon(Icons.refresh_rounded),
      onPressed: _load,
    );
    final description = Text(
      'Where each cashier and rider appears on the members’ map. '
      'They set their own location — you can review it and remove '
      'one that is wrong.',
      style: StockpileFonts.satoshi(fontSize: 13, height: 1.4, color: muted),
    );
    final title = Text(
      'Cashier Locations',
      style: StockpileFonts.satoshi(
        fontSize: 22,
        fontWeight: FontWeight.w700,
        color: text,
      ),
    );
    const glyph = Padding(
      padding: EdgeInsets.only(top: 3),
      child: Icon(Icons.pin_drop_rounded, color: StockpileColors.primary900),
    );

    // Phone: the title owns the row, the description gets the full width,
    // and the freshness stamp drops under it. Side by side they were
    // squeezing the title onto two lines and the copy into a column.
    if (!wide) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              glyph,
              const SizedBox(width: 10),
              Expanded(child: title),
              refresh,
            ],
          ),
          const SizedBox(height: 2),
          description,
          const SizedBox(height: 6),
          freshness,
        ],
      );
    }
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        glyph,
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [title, const SizedBox(height: 4), description],
          ),
        ),
        const SizedBox(width: 12),
        freshness,
        refresh,
      ],
    );
  }

  Widget _statTiles({bool scrollable = false}) {
    final rows = _inRole;
    final located = rows.where((e) => e.hasLocation).length;
    final missing = rows.length - located;
    final attention = rows.where((e) => e.needsAttention).length;
    final live = rows.where((e) => e.isLive).length;

    final tiles = [
      _StatTile(
        value: '$located',
        suffix: 'of ${rows.length}',
        label: 'LOCATED',
        active: _status == _StatusFilter.located,
        onTap: () => _toggleStatus(_StatusFilter.located),
      ),
      _StatTile(
        value: '$missing',
        label: 'NO LOCATION',
        active: _status == _StatusFilter.missing,
        onTap: () => _toggleStatus(_StatusFilter.missing),
      ),
      _StatTile(
        value: '$attention',
        label: 'NEEDS ATTENTION',
        warn: attention > 0,
        active: _status == _StatusFilter.attention,
        onTap: () => _toggleStatus(_StatusFilter.attention),
      ),
      if (enableDeliverySystem)
        _StatTile(
          value: '$live',
          suffix: 'of $_riderTotal',
          label: 'RIDERS LIVE NOW',
          liveDot: true,
          active: _status == _StatusFilter.live,
          onTap: () => _toggleStatus(_StatusFilter.live),
        ),
    ];

    if (scrollable) {
      return SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        clipBehavior: Clip.none,
        child: Row(
          children: [
            for (var i = 0; i < tiles.length; i++) ...[
              if (i > 0) const SizedBox(width: 8),
              SizedBox(width: 132, child: tiles[i]),
            ],
          ],
        ),
      );
    }
    return Row(
      children: [
        for (var i = 0; i < tiles.length; i++) ...[
          if (i > 0) const SizedBox(width: 12),
          Expanded(child: tiles[i]),
        ],
      ],
    );
  }

  void _toggleStatus(_StatusFilter f) =>
      setState(() => _status = _status == f ? _StatusFilter.all : f);

  Widget _toolbar({required bool wide}) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final muted = isDark
        ? StockpileColors.darkTextMuted
        : StockpileColors.mutedText;

    final search = SizedBox(
      width: wide ? 280 : null,
      height: 40,
      child: TextField(
        controller: _searchCtrl,
        onChanged: (v) => setState(() => _query = v),
        decoration: InputDecoration(
          isDense: true,
          hintText: 'Search by username',
          prefixIcon: const Icon(Icons.search_rounded, size: 18),
          suffixIcon: _query.isEmpty
              ? null
              : IconButton(
                  icon: const Icon(Icons.close_rounded, size: 16),
                  onPressed: () {
                    _searchCtrl.clear();
                    setState(() => _query = '');
                  },
                ),
          filled: true,
          fillColor: isDark
              ? StockpileColors.darkInputBg
              : StockpileColors.inputBg,
          contentPadding: const EdgeInsets.symmetric(horizontal: 12),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: BorderSide(
              color: isDark
                  ? StockpileColors.darkDivider
                  : StockpileColors.divider,
            ),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: BorderSide(
              color: isDark
                  ? StockpileColors.darkDivider
                  : StockpileColors.divider,
            ),
          ),
        ),
      ),
    );

    final chips = [
      for (final f in _RoleFilter.values)
        if (f != _RoleFilter.rider || enableDeliverySystem)
          ChoiceChip(
            label: Text(
              '${f.label} · ${_entries.where((e) => f.matches(e.profile)).length}',
            ),
            selected: _role == f,
            onSelected: (_) => setState(() => _role = f),
            showCheckmark: false,
            labelStyle: StockpileFonts.satoshi(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: _role == f ? StockpileColors.primary900 : muted,
            ),
            selectedColor: StockpileColors.primary900.withAlpha(30),
            backgroundColor: isDark
                ? StockpileColors.darkInputBg
                : StockpileColors.inputBg,
            side: BorderSide(
              color: _role == f
                  ? StockpileColors.primary900
                  : (isDark
                        ? StockpileColors.darkDivider
                        : StockpileColors.divider),
            ),
          ),
    ];

    final sort = PopupMenuButton<_Sort>(
      tooltip: 'Sort',
      initialValue: _sort,
      onSelected: (s) => setState(() => _sort = s),
      itemBuilder: (_) => [
        for (final s in _Sort.values)
          PopupMenuItem(value: s, child: Text(s.label)),
      ],
      child: Container(
        height: 36,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        decoration: BoxDecoration(
          color: isDark ? StockpileColors.darkSurface : Colors.white,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: isDark
                ? StockpileColors.darkDivider
                : StockpileColors.divider,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.sort_rounded, size: 16, color: muted),
            const SizedBox(width: 6),
            Text(
              _sort.label,
              style: StockpileFonts.satoshi(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: isDark
                    ? StockpileColors.darkTextBody
                    : StockpileColors.bodyText,
              ),
            ),
            const SizedBox(width: 4),
            Icon(Icons.expand_more_rounded, size: 16, color: muted),
          ],
        ),
      ),
    );

    if (wide) {
      return Row(
        children: [
          search,
          const SizedBox(width: 12),
          Wrap(spacing: 8, children: chips),
          const Spacer(),
          sort,
        ],
      );
    }
    // Phone: sort collapses to an icon beside the search box, and the chip
    // row gets the whole width, scrolling edge to edge. (Sharing a row with
    // the full sort button left the chips painting underneath it.)
    final sortIcon = PopupMenuButton<_Sort>(
      tooltip: 'Sort · ${_sort.label}',
      initialValue: _sort,
      onSelected: (s) => setState(() => _sort = s),
      itemBuilder: (_) => [
        for (final s in _Sort.values)
          PopupMenuItem(value: s, child: Text(s.label)),
      ],
      child: Container(
        width: 44,
        height: 40,
        decoration: BoxDecoration(
          color: isDark ? StockpileColors.darkSurface : Colors.white,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: isDark
                ? StockpileColors.darkDivider
                : StockpileColors.divider,
          ),
        ),
        child: Icon(Icons.sort_rounded, size: 20, color: muted),
      ),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(child: search),
            const SizedBox(width: 8),
            sortIcon,
          ],
        ),
        const SizedBox(height: 10),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              for (var i = 0; i < chips.length; i++) ...[
                if (i > 0) const SizedBox(width: 8),
                chips[i],
              ],
            ],
          ),
        ),
      ],
    );
  }

  // ── Map ───────────────────────────────────────────────────────────────────

  List<Marker> _markers() {
    final sel = _selectedId;
    return [
      for (final e in _located)
        if (e.profile.id != sel)
          mapMarker(
            key: ValueKey(e.profile.id),
            point: e.point,
            kind: e.kind,
            live: e.isLive,
            // A rider who has not pinged in a while is still on the map,
            // just not shouting about it.
            muted: e.isRider && !e.isLive,
            onTap: () => _selectFromPin(e),
          ),
      // Selected last so it paints on top.
      if (_selected case final s? when s.hasLocation && _located.contains(s))
        mapMarker(
          key: ValueKey('sel-${s.profile.id}'),
          point: s.point,
          kind: s.kind,
          selected: true,
          live: s.isLive,
          onTap: () => _selectFromPin(s),
        ),
      if (_selected case final s? when s.hasLocation && _located.contains(s))
        _callout(s),
    ];
  }

  /// The name card floating above the selected pin.
  Marker _callout(_Entry e) {
    const w = 190.0, h = 46.0;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Marker(
      point: e.point,
      width: w,
      height: h,
      // The point sits 30 px below the card's bottom edge — clear of the
      // 38 px selected disc.
      alignment: Marker.computePixelAlignment(
        width: w,
        height: h,
        left: w / 2,
        top: h + 30,
      ),
      child: IgnorePointer(
        child: Center(
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 6),
            decoration: BoxDecoration(
              color: isDark ? StockpileColors.darkSurface : Colors.white,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: isDark
                    ? StockpileColors.darkDivider
                    : StockpileColors.divider,
              ),
              boxShadow: [
                BoxShadow(color: Colors.black.withAlpha(30), blurRadius: 12),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  e.profile.username,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: StockpileFonts.satoshi(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: isDark
                        ? StockpileColors.darkTextPrimary
                        : StockpileColors.darkText,
                  ),
                ),
                Text(
                  '${_roleLabel(e.profile.role)} · ${_whenLine(e)}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: StockpileFonts.satoshi(
                    fontSize: 10,
                    color: StockpileColors.mutedText,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _map({bool compact = false}) {
    final located = _located;
    if (located.isEmpty) {
      return _EmptyMap(
        text: _inRole.isEmpty
            ? 'No accounts in this view.'
            : 'Nobody in this view has a location.',
      );
    }
    final points = [for (final e in located) e.point];
    final hasRiders = located.any((e) => e.isRider);
    final kinds = located.map((e) => e.kind).toSet();

    return MapOverlay(
      map: FlutterMap(
        mapController: _mapController,
        options: MapOptions(
          initialCenter: points.first,
          initialZoom: 13,
          initialCameraFit: fitPoints(points),
          onTap: (_, _) => setState(() => _selectedId = null),
        ),
        children: [
          osmTileLayer(),
          MarkerLayer(markers: _markers()),
        ],
      ),
      topRight: [
        if (compact)
          MapControlButton(
            icon: Icons.open_in_full_rounded,
            tooltip: 'Expand map',
            onTap: _expandMap,
          )
        else
          MapControlButton(
            icon: Icons.fit_screen_rounded,
            label: 'Fit all',
            tooltip: 'Frame every pin',
            onTap: _fitAll,
          ),
      ],
      // Only when the colours need explaining.
      bottomLeft: kinds.length > 1 || hasRiders
          ? MapLegend(
              items: [
                if (kinds.contains(MapPinKind.cashier))
                  const MapLegendItem(StockpileColors.primary900, 'Cashier'),
                if (kinds.contains(MapPinKind.branch))
                  const MapLegendItem(StockpileColors.secondary500, 'Branch'),
                if (hasRiders) ...[
                  MapLegendItem(MapPinKind.rider.color, 'Rider'),
                  const MapLegendItem(StockpileColors.success, 'Live'),
                ],
              ],
            )
          : null,
    );
  }

  Future<void> _expandMap() => Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (_) => FullscreenMapPage(
        title: 'Cashier Locations',
        markers: [
          for (final e in _located)
            mapMarker(
              point: e.point,
              kind: e.kind,
              live: e.isLive,
              muted: e.isRider && !e.isLive,
              label: e.profile.username,
            ),
        ],
        fitTo: [for (final e in _located) e.point],
      ),
    ),
  );

  // ── Roster ────────────────────────────────────────────────────────────────

  Widget _roster({required bool scrollable}) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final muted = isDark
        ? StockpileColors.darkTextMuted
        : StockpileColors.mutedText;
    final rows = _visible;
    final inRole = _inRole;
    final attention = inRole.where((e) => e.needsAttention).length;
    final unset = inRole.where((e) => !e.hasLocation).length;

    final header = Padding(
      padding: const EdgeInsets.fromLTRB(2, 0, 2, 8),
      child: Row(
        children: [
          Text(
            '${inRole.length} ${inRole.length == 1 ? 'ACCOUNT' : 'ACCOUNTS'}'
            '${_status == _StatusFilter.all ? '' : ' · ${rows.length} SHOWN'}',
            style: StockpileFonts.satoshi(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.9,
              color: muted,
            ),
          ),
          const Spacer(),
          Text(
            attention == 0 && unset == 0 && inRole.isNotEmpty
                ? 'all set, none look wrong'
                : '$attention need attention · $unset unset',
            style: StockpileFonts.satoshi(fontSize: 11, color: muted),
          ),
        ],
      ),
    );

    Widget body;
    if (rows.isEmpty) {
      body = _EmptyRoster(
        query: _query,
        filtered: _status != _StatusFilter.all || _role != _RoleFilter.all,
        onClear: () {
          _searchCtrl.clear();
          setState(() {
            _query = '';
            _status = _StatusFilter.all;
            _role = _RoleFilter.all;
          });
        },
      );
    } else {
      body = Column(
        children: [
          for (var i = 0; i < rows.length; i++) ...[
            if (i > 0) const SizedBox(height: 8),
            _RosterRow(
              key: _rowKeys.putIfAbsent(rows[i].profile.id, GlobalKey.new),
              entry: rows[i],
              selected: rows[i].profile.id == _selectedId,
              hoverActions: scrollable,
              onTap: () => _selectFromRow(rows[i]),
              onOpen: () => _openInMaps(rows[i]),
              onCopy: () => _copyCoordinates(rows[i]),
              onClear: () => _clear(rows[i]),
            ),
          ],
        ],
      );
    }

    if (!scrollable) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [header, body],
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        header,
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.only(bottom: 8),
            child: body,
          ),
        ),
      ],
    );
  }
}

// ─── Small helpers ──────────────────────────────────────────────────────────

String _roleLabel(String role) => switch (role) {
  'branch_cashier' => 'Branch Cashier',
  'delivery' => 'Rider',
  _ => 'Cashier',
};

/// "set 3 days ago" for a cashier, "last seen 40 s ago" for a rider — a
/// cashier's point is a place, a rider's is a heartbeat.
String _whenLine(_Entry e) {
  final at = e.profile.locationUpdatedAt;
  if (at == null) return e.isRider ? 'never seen' : 'set date unknown';
  return e.isRider
      ? 'last seen ${formatAgo(at)}'
      : 'set ${formatRelativeDate(at).toLowerCase()}';
}

// ─── Stat tile ──────────────────────────────────────────────────────────────

class _StatTile extends StatelessWidget {
  final String value;
  final String? suffix;
  final String label;
  final bool active;
  final bool warn;
  final bool liveDot;
  final VoidCallback onTap;

  const _StatTile({
    required this.value,
    required this.label,
    required this.active,
    required this.onTap,
    this.suffix,
    this.warn = false,
    this.liveDot = false,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final text = isDark
        ? StockpileColors.darkTextPrimary
        : StockpileColors.darkText;
    final muted = isDark
        ? StockpileColors.darkTextMuted
        : StockpileColors.mutedText;
    final warnColor = isDark
        ? StockpileColors.primary400
        : const Color(0xFFB45309);

    final highlighted = active || warn;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: EdgeInsets.symmetric(
            horizontal: highlighted ? 15 : 16,
            vertical: highlighted ? 13 : 14,
          ),
          decoration: BoxDecoration(
            color: highlighted
                ? (isDark
                      ? StockpileColors.primary900.withAlpha(30)
                      : StockpileColors.primary50)
                : (isDark ? StockpileColors.darkSurface : Colors.white),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: active
                  ? StockpileColors.primary900
                  : warn
                  ? StockpileColors.primary900.withAlpha(120)
                  : (isDark
                        ? StockpileColors.darkDivider
                        : StockpileColors.divider),
              width: highlighted ? 2 : 1,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Text(
                    value,
                    style: StockpileFonts.satoshi(
                      fontSize: 22,
                      fontWeight: FontWeight.w700,
                      height: 1.2,
                      color: text,
                    ),
                  ),
                  if (suffix != null) ...[
                    const SizedBox(width: 5),
                    Text(
                      suffix!,
                      style: StockpileFonts.satoshi(
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                        color: muted,
                      ),
                    ),
                  ],
                  if (warn) ...[
                    const SizedBox(width: 8),
                    Icon(
                      Icons.warning_amber_rounded,
                      size: 16,
                      color: warnColor,
                    ),
                  ],
                  if (liveDot) ...[
                    const SizedBox(width: 8),
                    Container(
                      width: 8,
                      height: 8,
                      decoration: const BoxDecoration(
                        color: StockpileColors.success,
                        shape: BoxShape.circle,
                      ),
                    ),
                  ],
                ],
              ),
              const SizedBox(height: 2),
              Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: StockpileFonts.satoshi(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.7,
                  color: warn ? warnColor : muted,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─── Roster row ─────────────────────────────────────────────────────────────

class _RosterRow extends StatefulWidget {
  final _Entry entry;
  final bool selected;

  /// Desktop: actions appear on hover or selection. Phone: the selected
  /// row expands into a button strip instead (hover does not exist).
  final bool hoverActions;
  final VoidCallback onTap;
  final VoidCallback onOpen;
  final VoidCallback onCopy;
  final VoidCallback onClear;

  const _RosterRow({
    super.key,
    required this.entry,
    required this.selected,
    required this.hoverActions,
    required this.onTap,
    required this.onOpen,
    required this.onCopy,
    required this.onClear,
  });

  @override
  State<_RosterRow> createState() => _RosterRowState();
}

class _RosterRowState extends State<_RosterRow> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final e = widget.entry;
    final p = e.profile;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final text = isDark
        ? StockpileColors.darkTextPrimary
        : StockpileColors.darkText;
    final muted = isDark
        ? StockpileColors.darkTextMuted
        : StockpileColors.mutedText;
    final divider = isDark
        ? StockpileColors.darkDivider
        : StockpileColors.divider;
    final has = e.hasLocation;
    final address = p.address?.trim() ?? '';

    final showInline =
        has && widget.hoverActions && (_hover || widget.selected);
    final showStrip = has && !widget.hoverActions && widget.selected;

    final meta = [
      if (has)
        '${p.latitude!.toStringAsFixed(5)}, ${p.longitude!.toStringAsFixed(5)}',
      if (has) _whenLine(e),
      if (e.isLive) 'on a delivery',
      if (e.sharedWith != null) 'same point as ${e.sharedWith}',
      if (e.outsidePh) 'not in the Philippines',
    ].join(' · ');

    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: widget.onTap,
          borderRadius: BorderRadius.circular(12),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            padding: EdgeInsets.all(widget.selected ? 11 : 12),
            decoration: BoxDecoration(
              color: widget.selected
                  ? (isDark
                        ? StockpileColors.primary900.withAlpha(30)
                        : StockpileColors.primary50)
                  : (isDark ? StockpileColors.darkSurface : Colors.white),
              borderRadius: BorderRadius.circular(12),
              border: widget.selected
                  ? Border.all(color: StockpileColors.primary900, width: 2)
                  : Border.all(color: divider),
            ),
            child: Column(
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _Avatar(entry: e),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Wrap(
                            spacing: 8,
                            runSpacing: 4,
                            crossAxisAlignment: WrapCrossAlignment.center,
                            children: [
                              Text(
                                p.username,
                                style: StockpileFonts.satoshi(
                                  fontSize: 15,
                                  fontWeight: FontWeight.w700,
                                  color: has ? text : muted,
                                ),
                              ),
                              _RoleChip(role: p.role, isDark: isDark),
                              if (e.isLive) const _FlagChip.live(),
                              if (e.outsidePh) const _FlagChip.outsidePh(),
                              if (e.sharedWith != null)
                                const _FlagChip.sharedPoint(),
                            ],
                          ),
                          const SizedBox(height: 4),
                          if (!has)
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
                                color: address.isEmpty ? muted : text,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              meta,
                              style: StockpileFonts.satoshi(
                                fontSize: 11,
                                height: 1.4,
                                color: muted,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                    if (showInline) ...[
                      const SizedBox(width: 4),
                      _IconAction(
                        icon: Icons.open_in_new_rounded,
                        tooltip: 'Open in Maps',
                        onTap: widget.onOpen,
                      ),
                      _IconAction(
                        icon: Icons.content_copy_rounded,
                        tooltip: 'Copy coordinates',
                        onTap: widget.onCopy,
                      ),
                      _IconAction(
                        icon: Icons.location_off_rounded,
                        tooltip: 'Remove location',
                        color: StockpileColors.danger,
                        onTap: widget.onClear,
                      ),
                    ],
                  ],
                ),
                if (showStrip) ...[
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(
                        child: _StripAction(
                          icon: Icons.open_in_new_rounded,
                          label: 'Maps',
                          onTap: widget.onOpen,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: _StripAction(
                          icon: Icons.content_copy_rounded,
                          label: 'Copy',
                          onTap: widget.onCopy,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: _StripAction(
                          icon: Icons.location_off_rounded,
                          label: 'Remove',
                          danger: true,
                          onTap: widget.onClear,
                        ),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Avatar extends StatelessWidget {
  final _Entry entry;

  const _Avatar({required this.entry});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final has = entry.hasLocation;
    final kind = entry.kind;
    final bg = !has
        ? (isDark ? StockpileColors.darkInputBg : StockpileColors.inputBg)
        : kind == MapPinKind.branch
        ? StockpileColors.secondary50
        : kind == MapPinKind.rider
        ? StockpileColors.primary50
        : const Color(0xFFFFE8D6);
    return SizedBox(
      width: 40,
      height: 40,
      child: Stack(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: isDark && has ? kind.color.withAlpha(40) : bg,
              shape: BoxShape.circle,
            ),
            child: Icon(
              has ? kind.glyph : Icons.location_off_rounded,
              size: 20,
              color: has ? kind.color : StockpileColors.mutedText,
            ),
          ),
          if (entry.isLive)
            Positioned(
              right: 0,
              bottom: 0,
              child: Container(
                width: 11,
                height: 11,
                decoration: BoxDecoration(
                  color: StockpileColors.success,
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: isDark ? StockpileColors.darkSurface : Colors.white,
                    width: 2,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _IconAction extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;
  final Color? color;

  const _IconAction({
    required this.icon,
    required this.tooltip,
    required this.onTap,
    this.color,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return IconButton(
      tooltip: tooltip,
      icon: Icon(icon, size: 18),
      color:
          color ??
          (isDark ? StockpileColors.darkTextBody : StockpileColors.bodyText),
      constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
      padding: EdgeInsets.zero,
      onPressed: onTap,
    );
  }
}

/// Phone: a 44 px button in the selected row's strip.
class _StripAction extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool danger;

  const _StripAction({
    required this.icon,
    required this.label,
    required this.onTap,
    this.danger = false,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final fg = danger
        ? StockpileColors.danger
        : (isDark ? StockpileColors.darkTextPrimary : StockpileColors.darkText);
    return Material(
      color: isDark ? StockpileColors.darkSurface : Colors.white,
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: Container(
          height: 44,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: danger
                  ? StockpileColors.dangerBg
                  : (isDark
                        ? StockpileColors.darkDivider
                        : StockpileColors.divider),
            ),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 16, color: fg),
              const SizedBox(width: 6),
              Text(
                label,
                style: StockpileFonts.satoshi(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: fg,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─── Chips ──────────────────────────────────────────────────────────────────

class _RoleChip extends StatelessWidget {
  final String role;
  final bool isDark;

  const _RoleChip({required this.role, required this.isDark});

  @override
  Widget build(BuildContext context) {
    final neutralBg = isDark
        ? StockpileColors.darkInputBg
        : StockpileColors.inputBg;
    final (bg, fg) = switch (role) {
      'branch_cashier' => (
        StockpileColors.secondary50,
        StockpileColors.secondary500,
      ),
      'delivery' => (StockpileColors.primary50, MapPinKind.rider.color),
      _ => (neutralBg, StockpileColors.mutedText),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(100),
      ),
      child: Text(
        _roleLabel(role),
        style: StockpileFonts.satoshi(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          color: fg,
        ),
      ),
    );
  }
}

class _FlagChip extends StatelessWidget {
  final String label;
  final Color bg;
  final Color fg;
  final bool dot;

  const _FlagChip.live()
    : label = 'Live',
      bg = StockpileColors.successBg,
      fg = const Color(0xFF15803D),
      dot = true;

  const _FlagChip.outsidePh()
    : label = 'Outside PH',
      bg = StockpileColors.dangerBg,
      fg = const Color(0xFFB91C1C),
      dot = false;

  const _FlagChip.sharedPoint()
    : label = 'Shared point',
      bg = const Color(0xFFFEF3C7),
      fg = const Color(0xFF92400E),
      dot = false;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(100),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (dot)
            Container(
              width: 6,
              height: 6,
              margin: const EdgeInsets.only(right: 5),
              decoration: const BoxDecoration(
                color: StockpileColors.success,
                shape: BoxShape.circle,
              ),
            )
          else
            Padding(
              padding: const EdgeInsets.only(right: 4),
              child: Icon(Icons.warning_amber_rounded, size: 11, color: fg),
            ),
          Text(
            label,
            style: StockpileFonts.satoshi(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: fg,
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Dialog preview & empty states ──────────────────────────────────────────

class _RemovePreview extends StatelessWidget {
  final _Entry entry;

  const _RemovePreview({required this.entry});

  @override
  Widget build(BuildContext context) {
    final p = entry.profile;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final address = p.address?.trim() ?? '';
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: isDark ? StockpileColors.darkInputBg : StockpileColors.inputBg,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Text(
                p.username,
                style: StockpileFonts.satoshi(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: isDark
                      ? StockpileColors.darkTextPrimary
                      : StockpileColors.darkText,
                ),
              ),
              _RoleChip(role: p.role, isDark: isDark),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            address.isEmpty ? 'Address unavailable' : address,
            style: StockpileFonts.satoshi(
              fontSize: 13,
              color: isDark
                  ? StockpileColors.darkTextBody
                  : StockpileColors.darkText,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            '${p.latitude!.toStringAsFixed(5)}, ${p.longitude!.toStringAsFixed(5)}'
            ' · ${_whenLine(entry)}'
            '${entry.sharedWith != null ? ' · same point as ${entry.sharedWith}' : ''}',
            style: StockpileFonts.satoshi(
              fontSize: 11,
              color: StockpileColors.mutedText,
            ),
          ),
        ],
      ),
    );
  }
}

class _EmptyMap extends StatelessWidget {
  final String text;

  const _EmptyMap({required this.text});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      color: isDark ? StockpileColors.darkInputBg : StockpileColors.inputBg,
      alignment: Alignment.center,
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(
            Icons.map_outlined,
            size: 32,
            color: StockpileColors.mutedText,
          ),
          const SizedBox(height: 8),
          Text(
            text,
            textAlign: TextAlign.center,
            style: StockpileFonts.satoshi(
              fontSize: 13,
              color: StockpileColors.mutedText,
            ),
          ),
        ],
      ),
    );
  }
}

class _EmptyRoster extends StatelessWidget {
  final String query;
  final bool filtered;
  final VoidCallback onClear;

  const _EmptyRoster({
    required this.query,
    required this.filtered,
    required this.onClear,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final searching = query.trim().isNotEmpty;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 28),
      decoration: BoxDecoration(
        color: isDark ? StockpileColors.darkSurface : Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isDark ? StockpileColors.darkDivider : StockpileColors.divider,
        ),
      ),
      child: Column(
        children: [
          Icon(
            searching ? Icons.search_off_rounded : Icons.people_outline_rounded,
            size: 28,
            color: StockpileColors.mutedText,
          ),
          const SizedBox(height: 8),
          Text(
            searching
                ? 'No one matches “${query.trim()}”'
                : filtered
                ? 'Nothing matches these filters'
                : 'No cashier accounts exist yet.',
            style: StockpileFonts.satoshi(
              fontSize: 14,
              fontWeight: FontWeight.w700,
              color: isDark
                  ? StockpileColors.darkTextPrimary
                  : StockpileColors.darkText,
            ),
          ),
          if (searching || filtered) ...[
            const SizedBox(height: 4),
            Text(
              searching
                  ? 'Try fewer letters, or clear the filters.'
                  : 'Clear them to see everyone.',
              style: StockpileFonts.satoshi(
                fontSize: 13,
                color: StockpileColors.mutedText,
              ),
            ),
            const SizedBox(height: 10),
            OutlinedButton(
              onPressed: onClear,
              child: const Text('Clear filters'),
            ),
          ],
        ],
      ),
    );
  }
}
