import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../utils/fonts.dart';
import '../theme.dart';
import '../data/models.dart';
import '../db/db.dart';
import '../services/notification_service.dart';
import '../services/config_service.dart';

class StockpileTopBar extends StatelessWidget {
  final String pageTitle;
  final VoidCallback? onMenuTap;
  final bool showMenu;

  /// Called when a notification item is tapped, passing the target tab index.
  /// 2 = Inventory, 6 = Requests, 7 = Borrow Stock.
  final ValueChanged<int>? onNavigateToTab;

  const StockpileTopBar({
    super.key,
    required this.pageTitle,
    this.onMenuTap,
    this.showMenu = false,
    this.onNavigateToTab,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final surface = isDark
        ? StockpileColors.darkSurface
        : StockpileColors.surface;

    final notificationService = context.watch<NotificationService>();
    final badgeCount = notificationService.totalCount;

    return Container(
      decoration: BoxDecoration(
        color: surface,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withAlpha((0.03 * 255).round()),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
      child: Row(
        children: [
          // Hamburger (mobile only)
          if (showMenu) ...[
            IconButton(
              icon: Icon(
                Icons.menu_rounded,
                color: isDark
                    ? StockpileColors.darkTextPrimary
                    : StockpileColors.darkText,
              ),
              onPressed: onMenuTap,
              tooltip: 'Menu',
            ),
            const SizedBox(width: 12),
          ],

          // Page title
          Text(
            pageTitle,
            style: StockpileFonts.satoshi(
              fontSize: 22,
              fontWeight: FontWeight.w700,
              color: isDark
                  ? StockpileColors.darkTextPrimary
                  : StockpileColors.darkText,
              height: 1.2,
            ),
          ),

          const Spacer(),

          // Notification bell
          IconButton(
            icon: Badge(
              isLabelVisible: badgeCount > 0,
              backgroundColor: StockpileColors.primary900,
              label: Text(
                '$badgeCount',
                style: const TextStyle(color: Colors.white, fontSize: 10),
              ),
              child: Icon(
                badgeCount > 0
                    ? Icons.notifications_rounded
                    : Icons.notifications_outlined,
                color: isDark
                    ? StockpileColors.darkTextPrimary
                    : StockpileColors.darkText,
              ),
            ),
            onPressed: () => _showNotificationPopover(context),
            tooltip: badgeCount > 0
                ? '${notificationService.pendingCount} pending · ${notificationService.lowStockCount} low stock · ${notificationService.overdueCount} overdue'
                : 'Notifications',
          ),
        ],
      ),
    );
  }

  void _showNotificationPopover(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final notificationService = context.read<NotificationService>();

    showDialog(
      context: context,
      builder: (ctx) => _NotificationPopover(
        isDark: isDark,
        notificationService: notificationService,
        lastSeenAt: notificationService.lastSeenAt,
        onNavigateToTab: onNavigateToTab,
      ),
    );
  }
}

class _NotificationPopover extends StatefulWidget {
  final bool isDark;
  final NotificationService notificationService;
  final DateTime? lastSeenAt;
  final ValueChanged<int>? onNavigateToTab;

  const _NotificationPopover({
    required this.isDark,
    required this.notificationService,
    this.lastSeenAt,
    this.onNavigateToTab,
  });

  @override
  State<_NotificationPopover> createState() => _NotificationPopoverState();
}

class _NotificationPopoverState extends State<_NotificationPopover> {
  List<PendingRequest> _requests = [];
  List<Item> _lowStockItems = [];
  List<Borrow> _overdueBorrows = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final threshold = context.read<ConfigService>().lowStockThreshold;
      final results = await Future.wait([
        repository.fetchPendingRequests(),
        repository.fetchLowStockItems(threshold),
        repository.fetchOverdueBorrows(),
      ]);
      if (!mounted) return;
      setState(() {
        _requests = results[0] as List<PendingRequest>;
        _lowStockItems = results[1] as List<Item>;
        _overdueBorrows = results[2] as List<Borrow>;
        _loading = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  IconData _requestIcon(String type) {
    switch (type) {
      case 'delete':
        return Icons.delete_outline;
      case 'reduce_stock':
        return Icons.remove_shopping_cart_outlined;
      case 'delete_member':
        return Icons.person_remove_rounded;
      case 'borrow':
        return Icons.add_box_outlined;
      default:
        return Icons.help_outline;
    }
  }

  Color _requestColor(String type) {
    switch (type) {
      case 'delete':
        return Colors.red;
      case 'reduce_stock':
        return Colors.orange;
      case 'delete_member':
        return Colors.purple;
      case 'borrow':
        return Colors.blue;
      default:
        return Colors.grey;
    }
  }

  String _timeAgo(DateTime? dt) {
    if (dt == null) return '';
    final diff = DateTime.now().difference(dt);
    if (diff.inSeconds < 60) return 'Just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    return '${diff.inDays}d ago';
  }

  /// Whether an item timestamp makes it \"new\" (after last seen).
  bool _isNew(DateTime? dt) {
    if (dt == null || widget.lastSeenAt == null) return true;
    return dt.isAfter(widget.lastSeenAt!);
  }

  /// Opacity for read items.
  double _readOpacity(DateTime? dt) => _isNew(dt) ? 1.0 : 0.55;

  Widget _sectionHeader(
    String title,
    int count,
    IconData icon,
    Color color,
    bool isDark,
  ) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 4),
      child: Row(
        children: [
          Icon(icon, size: 16, color: color),
          const SizedBox(width: 6),
          Text(
            title,
            style: StockpileFonts.satoshi(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: color,
            ),
          ),
          const SizedBox(width: 6),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
            decoration: BoxDecoration(
              color: color.withAlpha(isDark ? 25 : 15),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              '$count',
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w700,
                color: color,
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _navigate(int tabIndex) {
    Navigator.pop(context);
    widget.onNavigateToTab?.call(tabIndex);
  }

  @override
  Widget build(BuildContext context) {
    final isDark = widget.isDark;
    final notif = widget.notificationService;
    final total = notif.totalCount;

    final isMobile = MediaQuery.of(context).size.width < 750;

    return Dialog(
      alignment: isMobile ? Alignment.center : Alignment.topRight,
      insetPadding: isMobile
          ? const EdgeInsets.symmetric(horizontal: 16)
          : const EdgeInsets.only(top: 76, right: 24),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 400, maxHeight: 520),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Header
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 16, 18, 8),
              child: Row(
                children: [
                  Icon(
                    Icons.notifications_rounded,
                    size: 20,
                    color: isDark
                        ? StockpileColors.darkTextPrimary
                        : StockpileColors.darkText,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    'Notifications',
                    style: StockpileFonts.satoshi(
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                      color: isDark
                          ? StockpileColors.darkTextPrimary
                          : StockpileColors.darkText,
                    ),
                  ),
                  if (total > 0) ...[
                    const SizedBox(width: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 7,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: StockpileColors.primary900,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text(
                        '$total',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ],
                  const Spacer(),
                  if (widget.onNavigateToTab != null && _requests.isNotEmpty)
                    TextButton.icon(
                      icon: const Icon(Icons.open_in_new_rounded, size: 16),
                      label: const Text('View All'),
                      onPressed: () {
                        Navigator.pop(context);
                        widget.notificationService.markAllSeen();
                        widget.onNavigateToTab!(6);
                      },
                    ),
                  IconButton(
                    icon: const Icon(Icons.close, size: 18),
                    onPressed: () => Navigator.pop(context),
                    visualDensity: VisualDensity.compact,
                  ),
                ],
              ),
            ),
            const Divider(height: 1),

            // Content
            Flexible(
              child: _loading
                  ? const Padding(
                      padding: EdgeInsets.all(32),
                      child: Center(child: CircularProgressIndicator()),
                    )
                  : total == 0
                  ? Padding(
                      padding: const EdgeInsets.all(32),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.check_circle_outline_rounded,
                            size: 40,
                            color: isDark
                                ? Colors.white24
                                : Colors.grey.shade300,
                          ),
                          const SizedBox(height: 12),
                          Text(
                            'All clear!',
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                              color: isDark
                                  ? Colors.white38
                                  : Colors.grey.shade500,
                            ),
                          ),
                        ],
                      ),
                    )
                  : ListView(
                      shrinkWrap: true,
                      padding: const EdgeInsets.only(bottom: 8),
                      children: [
                        // ── Low Stock ──────────────────────────
                        if (_lowStockItems.isNotEmpty) ...[
                          _sectionHeader(
                            'Low Stock',
                            _lowStockItems.length,
                            Icons.inventory_2_rounded,
                            Colors.red,
                            isDark,
                          ),
                          ..._lowStockItems
                              .take(5)
                              .map(
                                (item) => Opacity(
                                  opacity: _readOpacity(item.lastUpdated),
                                  child: ListTile(
                                    dense: true,
                                    onTap: () => _navigate(2),
                                    leading: Container(
                                      width: 32,
                                      height: 32,
                                      decoration: BoxDecoration(
                                        color: Colors.red.withAlpha(
                                          isDark ? 25 : 15,
                                        ),
                                        borderRadius: BorderRadius.circular(8),
                                      ),
                                      child: Center(
                                        child: Text(
                                          '${item.stock}',
                                          style: const TextStyle(
                                            fontSize: 12,
                                            fontWeight: FontWeight.w800,
                                            color: Colors.red,
                                          ),
                                        ),
                                      ),
                                    ),
                                    title: Text(
                                      item.name,
                                      style: TextStyle(
                                        fontSize: 13,
                                        fontWeight: FontWeight.w600,
                                        color: isDark
                                            ? StockpileColors.darkTextPrimary
                                            : StockpileColors.darkText,
                                      ),
                                    ),
                                    subtitle: Text(
                                      '${item.stock} left',
                                      style: TextStyle(
                                        fontSize: 11,
                                        color: Colors.red.shade300,
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                          if (_lowStockItems.length > 5)
                            Padding(
                              padding: const EdgeInsets.only(
                                left: 56,
                                bottom: 4,
                              ),
                              child: Text(
                                '+${_lowStockItems.length - 5} more',
                                style: TextStyle(
                                  fontSize: 11,
                                  color: isDark ? Colors.white24 : Colors.grey,
                                ),
                              ),
                            ),
                          const Divider(height: 1, indent: 16, endIndent: 16),
                        ],

                        // ── Overdue Borrows ────────────────────
                        if (_overdueBorrows.isNotEmpty) ...[
                          _sectionHeader(
                            'Overdue Borrows',
                            _overdueBorrows.length,
                            Icons.warning_amber_rounded,
                            Colors.orange,
                            isDark,
                          ),
                          ..._overdueBorrows
                              .take(5)
                              .map(
                                (b) => Opacity(
                                  opacity: _readOpacity(b.borrowedAt),
                                  child: ListTile(
                                    dense: true,
                                    onTap: () => _navigate(7),
                                    leading: Container(
                                      width: 32,
                                      height: 32,
                                      decoration: BoxDecoration(
                                        color: Colors.orange.withAlpha(
                                          isDark ? 25 : 15,
                                        ),
                                        borderRadius: BorderRadius.circular(8),
                                      ),
                                      child: const Icon(
                                        Icons.swap_horiz_rounded,
                                        size: 16,
                                        color: Colors.orange,
                                      ),
                                    ),
                                    title: Text(
                                      b.itemName,
                                      style: TextStyle(
                                        fontSize: 13,
                                        fontWeight: FontWeight.w600,
                                        color: isDark
                                            ? StockpileColors.darkTextPrimary
                                            : StockpileColors.darkText,
                                      ),
                                    ),
                                    subtitle: Text(
                                      '${b.outstandingQuantity} outstanding · Due ${b.dueDate.day}/${b.dueDate.month}',
                                      style: TextStyle(
                                        fontSize: 11,
                                        color: isDark
                                            ? Colors.white38
                                            : Colors.grey.shade600,
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                          if (_overdueBorrows.length > 5)
                            Padding(
                              padding: const EdgeInsets.only(
                                left: 56,
                                bottom: 4,
                              ),
                              child: Text(
                                '+${_overdueBorrows.length - 5} more',
                                style: TextStyle(
                                  fontSize: 11,
                                  color: isDark ? Colors.white24 : Colors.grey,
                                ),
                              ),
                            ),
                          const Divider(height: 1, indent: 16, endIndent: 16),
                        ],

                        // ── Pending Requests ──────────────────
                        if (_requests.isNotEmpty) ...[
                          _sectionHeader(
                            'Pending Requests',
                            _requests.length,
                            Icons.person_remove_rounded,
                            StockpileColors.primary900,
                            isDark,
                          ),
                          ..._requests.take(10).map((req) {
                            final color = _requestColor(req.requestType);
                            return Opacity(
                              opacity: _readOpacity(req.createdAt),
                              child: ListTile(
                                dense: true,
                                onTap: () => _navigate(6),
                                leading: Container(
                                  width: 32,
                                  height: 32,
                                  decoration: BoxDecoration(
                                    color: color.withAlpha(isDark ? 25 : 15),
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: Icon(
                                    _requestIcon(req.requestType),
                                    size: 16,
                                    color: color,
                                  ),
                                ),
                                title: Text(
                                  req.summary,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w600,
                                    color: isDark
                                        ? StockpileColors.darkTextPrimary
                                        : StockpileColors.darkText,
                                  ),
                                ),
                                subtitle: Text(
                                  _timeAgo(req.createdAt),
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: isDark
                                        ? Colors.white38
                                        : Colors.grey.shade500,
                                  ),
                                ),
                              ),
                            );
                          }),
                        ],
                      ],
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
