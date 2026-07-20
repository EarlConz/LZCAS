// lib/widgets/my_requests_tab.dart
// Shared "My Requests" tab used by both the Cashier and Inventory dashboards.
// Shows pending / approved / rejected requests submitted by the current user
// with status pills, type filters, and card-based request display.
//
// Usage:
//   MyRequestsTab(
//     isDark: isDark,
//     typeFilters: const [
//       _FilterSegment('All', 'all', Icons.layers_rounded),
//       _FilterSegment('Delete', 'delete', Icons.delete_rounded),
//       _FilterSegment('Reduce', 'reduce_stock', Icons.remove_circle_rounded),
//     ],
//     emptyMessage: 'Submitted deletion & reduction requests\nwill appear here',
//   )

import 'package:flutter/material.dart';
import 'package:lzcas/data/models.dart';
import 'package:lzcas/db/db.dart';
import 'package:lzcas/utils/fonts.dart';

// ─── Public config types ────────────────────────────────────────────────────

class FilterSegment {
  final String label;
  final String value;
  final IconData icon;
  const FilterSegment(this.label, this.value, this.icon);
}

// ─── The shared tab widget ──────────────────────────────────────────────────

class MyRequestsTab extends StatefulWidget {
  final bool isDark;

  /// Type filter segments shown below the status pills.
  /// Inventory: 'delete' + 'reduce_stock'.  Cashier: 'delete_member' + 'borrow'.
  final List<FilterSegment> typeFilters;

  /// Shown when the user has no requests at all (no filters active).
  final String emptyMessage;

  const MyRequestsTab({
    super.key,
    required this.isDark,
    this.typeFilters = const [
      FilterSegment('All', 'all', Icons.layers_rounded),
    ],
    this.emptyMessage = 'Your requests will appear here',
  });

  @override
  State<MyRequestsTab> createState() => _MyRequestsTabState();
}

class _MyRequestsTabState extends State<MyRequestsTab> {
  List<PendingRequest> _requests = [];
  bool _isLoading = false;
  bool _isLoadingMore = false;
  String _statusFilter = 'all';
  String _typeFilter = 'all';
  bool _newestFirst = true;

  static const _pageSize = 25;
  int _currentPage = 0;
  bool _hasMore = true;

  static const _orange = Color(0xFFF59E0B);
  static const _emerald = Color(0xFF10B981);
  static const _rose = Color(0xFFEF4444);
  static const _slate = Color(0xFF64748B);
  static const _indigo = Color(0xFF6366F1);

  @override
  void initState() {
    super.initState();
    _loadRequests();
  }

  Future<void> _loadRequests() async {
    if (_isLoading) return;
    _isLoading = true;
    if (mounted) setState(() {});
    try {
      final page = await repository.fetchRequestsPaginated(
        page: 1,
        pageSize: _pageSize,
        userIdFilter: repository.supabase.auth.currentUser?.id,
      );
      if (!mounted) return;
      setState(() {
        _requests = page.rows;
        _currentPage = 1;
        _hasMore = page.hasMore;
        _isLoading = false;
      });
    } catch (_) {
      if (mounted)
        setState(() {
          _requests = [];
          _isLoading = false;
        });
    }
  }

  Future<void> _loadNextPage() async {
    if (_isLoadingMore || !_hasMore) return;
    _isLoadingMore = true;
    setState(() {});
    try {
      final page = await repository.fetchRequestsPaginated(
        page: _currentPage + 1,
        pageSize: _pageSize,
        userIdFilter: repository.supabase.auth.currentUser?.id,
      );
      if (!mounted) return;
      setState(() {
        _requests.addAll(page.rows);
        _currentPage = page.page;
        _hasMore = page.hasMore;
        _isLoadingMore = false;
      });
    } catch (_) {
      if (mounted) setState(() => _isLoadingMore = false);
    }
  }

  List<PendingRequest> get _filteredRequests {
    return _requests.where((r) {
      if (_statusFilter != 'all' && r.status != _statusFilter) return false;
      if (_typeFilter != 'all' && r.requestType != _typeFilter) return false;
      return true;
    }).toList()..sort((a, b) {
      final aTime = a.createdAt ?? DateTime(2000);
      final bTime = b.createdAt ?? DateTime(2000);
      return _newestFirst ? bTime.compareTo(aTime) : aTime.compareTo(bTime);
    });
  }

  int _countBy(String status) =>
      _requests.where((r) => r.status == status).length;

  String _formatDate(DateTime dt) {
    final now = DateTime.now();
    final diff = now.difference(dt);
    if (diff.inMinutes < 1) return 'just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    if (diff.inDays < 7) return '${diff.inDays}d ago';
    final d = dt.toLocal();
    return '${d.year}-${d.month.toString().padLeft(2, '0')}-'
        '${d.day.toString().padLeft(2, '0')}';
  }

  String _requestTypeLabel(String type) {
    switch (type) {
      case 'delete':
        return 'Delete product';
      case 'reduce_stock':
        return 'Reduce stock';
      case 'delete_member':
        return 'Delete member';
      case 'borrow':
        return 'Borrow';
      default:
        return type;
    }
  }

  IconData _requestTypeIcon(String type) {
    switch (type) {
      case 'delete':
        return Icons.delete_rounded;
      case 'reduce_stock':
        return Icons.remove_circle_rounded;
      case 'delete_member':
        return Icons.person_remove_rounded;
      case 'borrow':
        return Icons.swap_horiz_rounded;
      default:
        return Icons.help_outline_rounded;
    }
  }

  Color _requestTypeColor(String type) {
    switch (type) {
      case 'delete':
        return _rose;
      case 'reduce_stock':
        return _orange;
      case 'delete_member':
        return _rose;
      case 'borrow':
        return _orange;
      default:
        return _slate;
    }
  }

  void _showReasonDialog(BuildContext context, String reason) {
    final isDark = widget.isDark;
    final primaryColor = Theme.of(context).colorScheme.primary;
    showDialog(
      context: context,
      builder: (ctx) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header
              Row(
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: primaryColor.withAlpha(25),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(
                      Icons.info_outline_rounded,
                      color: primaryColor,
                      size: 22,
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Text(
                      'Request Reason',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                        color: isDark ? Colors.white : const Color(0xFF1E293B),
                        letterSpacing: -0.3,
                      ),
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.pop(ctx),
                    icon: Icon(
                      Icons.close_rounded,
                      color: isDark ? Colors.white38 : Colors.grey.shade400,
                      size: 20,
                    ),
                    visualDensity: VisualDensity.compact,
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              Divider(
                color: isDark ? Colors.white10 : Colors.grey.shade200,
                height: 1,
              ),
              const SizedBox(height: 20),
              // Quote-style content
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(
                  color: isDark
                      ? Colors.white.withAlpha(8)
                      : Colors.grey.shade50,
                  borderRadius: BorderRadius.circular(14),
                  border: Border(
                    left: BorderSide(
                      color: primaryColor.withAlpha(120),
                      width: 3,
                    ),
                  ),
                ),
                child: Text(
                  reason,
                  style: TextStyle(
                    fontSize: 14,
                    color: isDark ? Colors.white70 : const Color(0xFF475569),
                    height: 1.6,
                    fontStyle: FontStyle.italic,
                  ),
                ),
              ),
              const SizedBox(height: 20),
              // Close button
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: () => Navigator.pop(ctx),
                  style: FilledButton.styleFrom(
                    backgroundColor: isDark
                        ? Colors.white.withAlpha(20)
                        : Colors.grey.shade100,
                    foregroundColor: isDark
                        ? Colors.white70
                        : const Color(0xFF475569),
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                  child: const Text(
                    'Close',
                    style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ── Stat pill ─────────────────────────────────────────────────────
  Widget _statPill(String label, int count, Color color, IconData icon) {
    final selected = _statusFilter == label.toLowerCase();
    final isDark = widget.isDark;
    final bg = selected
        ? color
        : (isDark ? Colors.white10 : Colors.grey.shade50);
    final fg = selected ? Colors.white : (isDark ? Colors.white70 : _slate);
    final borderColor = selected
        ? color
        : (isDark ? Colors.white12 : Colors.grey.shade200);

    return GestureDetector(
      onTap: () => setState(() => _statusFilter = label.toLowerCase()),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: borderColor, width: 1),
          boxShadow: selected
              ? [
                  BoxShadow(
                    color: color.withAlpha(40),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
                ]
              : null,
        ),
        child: Column(
          children: [
            Icon(icon, size: 18, color: fg),
            const SizedBox(height: 4),
            Text(
              '$count',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w800,
                color: fg,
              ),
            ),
            Text(
              label,
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w600,
                color: fg.withAlpha(200),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Type filter row ───────────────────────────────────────────────
  Widget _typeFilterRow() {
    final isDark = widget.isDark;

    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: widget.typeFilters.map((item) {
        final selected = _typeFilter == item.value;
        return GestureDetector(
          onTap: () => setState(() => _typeFilter = item.value),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
            decoration: BoxDecoration(
              color: selected
                  ? (isDark ? _indigo.withAlpha(40) : _indigo.withAlpha(20))
                  : Colors.transparent,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: selected
                    ? _indigo
                    : (isDark ? Colors.white12 : Colors.grey.shade200),
                width: 1,
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(item.icon, size: 15, color: selected ? _indigo : _slate),
                const SizedBox(width: 5),
                Text(
                  item.label,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                    color: selected ? _indigo : _slate,
                  ),
                ),
              ],
            ),
          ),
        );
      }).toList(),
    );
  }

  // ── Card builder ──────────────────────────────────────────────────
  Widget _buildCard(PendingRequest req) {
    final isDark = widget.isDark;
    final isPending = req.status == 'pending';
    final isApproved = req.status == 'approved';

    final statusColor = isPending ? _orange : (isApproved ? _emerald : _rose);
    final statusLabel = isPending
        ? 'Pending'
        : (isApproved ? 'Approved' : 'Rejected');
    final statusIcon = isPending
        ? Icons.hourglass_empty_rounded
        : (isApproved ? Icons.check_circle_rounded : Icons.cancel_rounded);
    final statusBg = isPending
        ? _orange.withAlpha(20)
        : (isApproved ? _emerald.withAlpha(20) : _rose.withAlpha(20));

    final type = req.requestType;
    final typeColor = _requestTypeColor(type);
    final typeIcon = _requestTypeIcon(type);
    final typeLabel = _requestTypeLabel(type);

    // Build title + subtitle based on request type
    String title;
    String subtitle;
    if (type == 'delete' || type == 'reduce_stock') {
      title = req.itemName ?? 'Unknown item';
      subtitle = type == 'reduce_stock' && req.quantity != null
          ? 'Requested reduce by ${req.quantity}'
          : 'Requested deletion';
    } else if (type == 'borrow') {
      title = req.itemName ?? 'Unknown';
      subtitle =
          'For ${req.memberName ?? 'Unknown'}  ·  ×${req.quantity ?? 0}${req.price != null && req.price! > 0 ? '  ·  ₱${req.price} each' : ''}';
    } else {
      // delete_member
      title = req.memberName ?? 'Unknown';
      subtitle = 'Requested deletion';
    }

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(
          color: isDark ? Colors.white10 : Colors.grey.shade200,
          width: 1,
        ),
      ),
      color: isDark ? Colors.grey.shade900 : Colors.white,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Row 1: Avatar + title + status
            Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: typeColor.withAlpha(isDark ? 30 : 20),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(typeIcon, size: 20, color: typeColor),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                          color: isDark
                              ? Colors.white
                              : const Color(0xFF1E293B),
                          height: 1.2,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        subtitle,
                        style: TextStyle(
                          fontSize: 12,
                          color: isDark ? Colors.white54 : _slate,
                          height: 1.3,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                // Status chip
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 5,
                  ),
                  decoration: BoxDecoration(
                    color: statusBg,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color: statusColor.withAlpha(60),
                      width: 1,
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(statusIcon, size: 13, color: statusColor),
                      const SizedBox(width: 4),
                      Text(
                        statusLabel,
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: statusColor,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),

            // Type label row
            const SizedBox(height: 8),
            Row(
              children: [
                Icon(Icons.label_outline_rounded, size: 13, color: typeColor),
                const SizedBox(width: 4),
                Text(
                  typeLabel,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: typeColor,
                  ),
                ),
              ],
            ),

            // Reason — shown as an info icon button
            if (req.reason != null && req.reason!.isNotEmpty) ...[
              const SizedBox(height: 8),
              GestureDetector(
                onTap: () => _showReasonDialog(context, req.reason!),
                child: Container(
                  width: 24,
                  height: 24,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: _slate.withAlpha(isDark ? 30 : 15),
                  ),
                  child: const Icon(
                    Icons.info_outline_rounded,
                    size: 14,
                    color: _slate,
                  ),
                ),
              ),
            ],

            // Rejection reason
            if (req.status == 'rejected' &&
                req.rejectionReason != null &&
                req.rejectionReason!.isNotEmpty) ...[
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: _rose.withAlpha(isDark ? 20 : 15),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: _rose.withAlpha(40), width: 1),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(Icons.block_rounded, size: 15, color: _rose),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        req.rejectionReason!,
                        style: const TextStyle(
                          fontSize: 12,
                          color: _rose,
                          height: 1.4,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],

            // Timestamp
            const SizedBox(height: 10),
            Row(
              children: [
                Icon(
                  Icons.schedule_rounded,
                  size: 12,
                  color: isDark ? Colors.white24 : Colors.grey.shade400,
                ),
                const SizedBox(width: 4),
                Text(
                  req.createdAt != null ? _formatDate(req.createdAt!) : '',
                  style: TextStyle(
                    fontSize: 11,
                    color: isDark ? Colors.white24 : Colors.grey.shade400,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = widget.isDark;
    final filtered = _filteredRequests;

    return RefreshIndicator(
      onRefresh: _loadRequests,
      child: _isLoading && _requests.isEmpty
          ? const Center(child: CircularProgressIndicator())
          : NotificationListener<ScrollNotification>(
              onNotification: (notification) {
                if (notification is ScrollEndNotification &&
                    notification.metrics.pixels >=
                        notification.metrics.maxScrollExtent - 200 &&
                    _hasMore &&
                    !_isLoadingMore) {
                  _loadNextPage();
                  return true;
                }
                return false;
              },
              child: CustomScrollView(
                slivers: [
                  // ── Header ──────────────────────────────────────────
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(16, 20, 16, 4),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // Title row
                          Row(
                            children: [
                              Expanded(
                                child: Text(
                                  'My Requests',
                                  style: StockpileFonts.satoshi(
                                    fontSize: 22,
                                    fontWeight: FontWeight.w800,
                                    color: isDark
                                        ? Colors.white
                                        : const Color(0xFF1E293B),
                                  ),
                                ),
                              ),
                              // Sort toggle
                              GestureDetector(
                                onTap: () => setState(
                                  () => _newestFirst = !_newestFirst,
                                ),
                                child: AnimatedContainer(
                                  duration: const Duration(milliseconds: 200),
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 12,
                                    vertical: 7,
                                  ),
                                  decoration: BoxDecoration(
                                    color: isDark
                                        ? Colors.white10
                                        : Colors.grey.shade100,
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      AnimatedRotation(
                                        turns: _newestFirst ? 0 : 0.5,
                                        duration: const Duration(
                                          milliseconds: 300,
                                        ),
                                        child: Icon(
                                          Icons.arrow_downward_rounded,
                                          size: 15,
                                          color: _slate,
                                        ),
                                      ),
                                      const SizedBox(width: 4),
                                      Text(
                                        _newestFirst ? 'Newest' : 'Oldest',
                                        style: const TextStyle(
                                          fontSize: 11,
                                          fontWeight: FontWeight.w600,
                                          color: _slate,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 16),
                          // Stats row
                          Row(
                            children: [
                              Expanded(
                                child: _statPill(
                                  'All',
                                  _requests.length,
                                  _indigo,
                                  Icons.inbox_rounded,
                                ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: _statPill(
                                  'Pending',
                                  _countBy('pending'),
                                  _orange,
                                  Icons.hourglass_empty_rounded,
                                ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: _statPill(
                                  'Approved',
                                  _countBy('approved'),
                                  _emerald,
                                  Icons.check_circle_rounded,
                                ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: _statPill(
                                  'Rejected',
                                  _countBy('rejected'),
                                  _rose,
                                  Icons.cancel_rounded,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 16),
                          // Type filter
                          _typeFilterRow(),
                          const SizedBox(height: 8),
                          // Result count
                          Text(
                            'Showing ${filtered.length} of ${_requests.length} request${_requests.length == 1 ? '' : 's'}',
                            style: TextStyle(
                              fontSize: 11,
                              color: isDark
                                  ? Colors.white24
                                  : Colors.grey.shade400,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),

                  // ── Content ─────────────────────────────────────────
                  if (filtered.isEmpty)
                    SliverFillRemaining(
                      hasScrollBody: false,
                      child: Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Container(
                              padding: const EdgeInsets.all(20),
                              decoration: BoxDecoration(
                                color: isDark
                                    ? Colors.white.withAlpha(15)
                                    : Colors.grey.shade100,
                                shape: BoxShape.circle,
                              ),
                              child: Icon(
                                _statusFilter != 'all' || _typeFilter != 'all'
                                    ? Icons.filter_list_off_rounded
                                    : Icons.inbox_rounded,
                                size: 40,
                                color: isDark
                                    ? Colors.white24
                                    : Colors.grey.shade300,
                              ),
                            ),
                            const SizedBox(height: 16),
                            Text(
                              _statusFilter != 'all' || _typeFilter != 'all'
                                  ? 'No matching requests'
                                  : 'No requests yet',
                              style: TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.w600,
                                color: isDark
                                    ? Colors.white38
                                    : Colors.grey.shade500,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              _statusFilter != 'all' || _typeFilter != 'all'
                                  ? 'Try adjusting the filters above'
                                  : widget.emptyMessage,
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                fontSize: 12,
                                color: isDark
                                    ? Colors.white.withAlpha(51)
                                    : Colors.grey.shade400,
                                height: 1.4,
                              ),
                            ),
                          ],
                        ),
                      ),
                    )
                  else
                    SliverPadding(
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                      sliver: SliverList(
                        delegate: SliverChildBuilderDelegate(
                          (_, i) => _buildCard(filtered[i]),
                          childCount: filtered.length,
                        ),
                      ),
                    ),
                  // Loading indicator at bottom
                  if (_isLoadingMore)
                    const SliverToBoxAdapter(
                      child: Padding(
                        padding: EdgeInsets.all(16),
                        child: Center(child: CircularProgressIndicator()),
                      ),
                    ),
                ],
              ),
            ),
    );
  }
}
