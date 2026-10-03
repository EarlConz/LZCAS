// lib/widgets/member_screen.dart
//
// One member, full screen, on a phone ("Members · Phone Rework" design).
// Admin and cashier each open it from their own members page and pass the
// actions their role has; an action left null is not shown. On wide
// screens both keep their detail dialog.

import 'package:flutter/material.dart';
import 'package:lzcas/utils/phone_formatter.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:lzcas/db/db.dart';
import 'package:lzcas/theme.dart';
import 'package:lzcas/utils/fonts.dart';
import 'package:lzcas/widgets/memberstable.dart' show showMemberQrDialog;

/// An action on the member. [refresh] redraws the screen after it changed
/// the member map in place (an upgrade, say).
typedef MemberAction = void Function(BuildContext context, VoidCallback refresh);

/// Below this width the members page opens a member as this screen.
const double kMemberScreenBreakpoint = 900;

class MemberScreen extends StatefulWidget {
  final Map<String, dynamic> member;
  final MemberAction onHistory;
  final MemberAction onEdit;
  final MemberAction onUpgrade;
  final MemberAction? onCreateAccount;
  final MemberAction? onViewPassword;
  final MemberAction? onAdjustFunds;
  final MemberAction? onDelete;

  const MemberScreen({
    super.key,
    required this.member,
    required this.onHistory,
    required this.onEdit,
    required this.onUpgrade,
    this.onCreateAccount,
    this.onViewPassword,
    this.onAdjustFunds,
    this.onDelete,
  });

  @override
  State<MemberScreen> createState() => _MemberScreenState();
}

class _MemberScreenState extends State<MemberScreen> {
  ({String referrerName, List<Member> direct, List<Member> indirect})? _refs;
  bool _refsFailed = false;

  Map<String, dynamic> get _m => widget.member;
  String _s(String key) => (_m[key]?.toString() ?? '').trim();

  String get _fullName => [_s('firstName'), _s('middleName'), _s('lastName')]
      .where((p) => p.isNotEmpty)
      .join(' ');

  bool get _isReseller => _s('role') == 'Verified Reseller';
  bool get _hasAccount => _s('email').isNotEmpty;

  @override
  void initState() {
    super.initState();
    _loadReferrals();
  }

  Future<void> _loadReferrals() async {
    final id = _m['id'] as int?;
    if (id == null) return;
    try {
      final r = await repository.fetchReferralSummary(
        memberId: id,
        referrerId: _m['referrerId'] as int?,
        referrerText: _s('referrer'),
        fullName: '${_s('firstName')} ${_s('lastName')}'.trim(),
      );
      if (mounted) setState(() => _refs = r);
    } catch (e) {
      debugPrint('[MemberScreen] referrals: $e');
      if (mounted) setState(() => _refsFailed = true);
    }
  }

  void _refresh() {
    if (mounted) setState(() {});
  }

  // ── Colours ────────────────────────────────────────────────────────

  bool get _dark => Theme.of(context).brightness == Brightness.dark;
  Color get _text => _dark ? StockpileColors.darkTextPrimary : StockpileColors.darkText;
  Color get _muted => _dark ? StockpileColors.darkTextMuted : const Color(0xFF6E6E7A);
  Color get _line => _dark ? StockpileColors.darkDivider : const Color(0xFFE8E8EC);
  Color get _surface => _dark ? StockpileColors.darkSurface : Colors.white;
  Color get _ground => _dark ? StockpileColors.darkBg : const Color(0xFFFAFAFA);
  Color get _soft => _dark ? StockpileColors.darkInputBg : const Color(0xFFF5F5F8);
  static const _orange = Color(0xFFCC4900);
  static const _orangeText = Color(0xFFB24800);
  static const _cream = Color(0xFFFFF7DF);

  @override
  Widget build(BuildContext context) {
    final name = _fullName.isEmpty ? 'Unnamed member' : _fullName;
    final initials = [_s('firstName'), _s('lastName')]
        .where((p) => p.isNotEmpty)
        .map((p) => p[0].toUpperCase())
        .join();
    final package = _s('packageName');
    final contact = formatPhilippinePhone(_s('contactNo'));
    final menu = [
      if (widget.onAdjustFunds != null) ('funds', 'Adjust funds'),
      if (widget.onDelete != null) ('delete', 'Delete member'),
    ];

    return Scaffold(
      backgroundColor: _ground,
      appBar: AppBar(
        title: const Text('Member'),
        backgroundColor: _surface,
        surfaceTintColor: Colors.transparent,
        actions: [
          if (menu.isNotEmpty)
            PopupMenuButton<String>(
              tooltip: 'More',
              onSelected: (v) => switch (v) {
                'funds' => widget.onAdjustFunds!(context, _refresh),
                _ => widget.onDelete!(context, _refresh),
              },
              itemBuilder: (_) => [
                for (final (v, label) in menu)
                  PopupMenuItem(
                    value: v,
                    child: Text(
                      label,
                      style: TextStyle(color: v == 'delete' ? StockpileColors.danger : null),
                    ),
                  ),
              ],
            ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
        children: [
          Row(
            children: [
              Container(
                width: 60,
                height: 60,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: _isReseller ? (_dark ? _orange.withAlpha(48) : _cream) : _soft,
                ),
                child: Text(
                  initials.isEmpty ? 'M' : initials,
                  style: StockpileFonts.satoshi(
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                    color: _isReseller ? (_dark ? Colors.white : _orangeText) : _text,
                  ),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(name, style: StockpileFonts.satoshi(fontSize: 20, fontWeight: FontWeight.w800, color: _text)),
                    const SizedBox(height: 2),
                    Text('ID ${_m['id'] ?? '—'}', style: StockpileFonts.satoshi(fontSize: 13, color: _muted)),
                    const SizedBox(height: 6),
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: [
                        _pill(_isReseller ? 'Verified Reseller' : (_s('role').isEmpty ? 'Member' : _s('role')), filled: _isReseller),
                        if (package.isNotEmpty) _pill('$package package'),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              _quick(Icons.call_outlined, 'Call', contact.isEmpty ? null : () => launchUrl(Uri(scheme: 'tel', path: contact.replaceAll(' ', '')))),
              const SizedBox(width: 8),
              _quick(Icons.qr_code_rounded, 'QR code', () => showMemberQrDialog(context, _m)),
              const SizedBox(width: 8),
              _quick(Icons.history_rounded, 'History', () => widget.onHistory(context, _refresh)),
              const SizedBox(width: 8),
              _quick(Icons.edit_outlined, 'Edit', () => widget.onEdit(context, _refresh)),
            ],
          ),
          const SizedBox(height: 12),
          _card(
            label: 'Personal info',
            child: Column(
              children: [
                _fact('Contact', contact),
                Divider(height: 1, color: _line),
                _fact('Birthday', _s('birthday')),
                Divider(height: 1, color: _line),
                _fact('Address', _s('address')),
              ],
            ),
          ),
          const SizedBox(height: 12),
          _referrals(),
          const SizedBox(height: 12),
          _account(),
        ],
      ),
      bottomNavigationBar: SafeArea(
        top: false,
        child: Container(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
          decoration: BoxDecoration(color: _surface, border: Border(top: BorderSide(color: _line))),
          child: SizedBox(
            height: 50,
            child: FilledButton.icon(
              onPressed: () => widget.onUpgrade(context, _refresh),
              style: FilledButton.styleFrom(
                backgroundColor: _orange,
                shape: const StadiumBorder(),
              ),
              icon: const Icon(Icons.upgrade_rounded, size: 20),
              label: Text(
                _isReseller ? 'Upgrade package' : 'Avail a package',
                style: StockpileFonts.satoshi(fontSize: 15, fontWeight: FontWeight.w700, color: Colors.white),
              ),
            ),
          ),
        ),
      ),
    );
  }

  // ── Pieces ─────────────────────────────────────────────────────────

  Widget _pill(String text, {bool filled = false}) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
    decoration: BoxDecoration(
      color: filled ? (_dark ? _orange.withAlpha(48) : _cream) : null,
      border: filled ? null : Border.all(color: _line),
      borderRadius: BorderRadius.circular(100),
    ),
    child: Text(
      text,
      style: StockpileFonts.satoshi(
        fontSize: 12,
        fontWeight: filled ? FontWeight.w700 : FontWeight.w600,
        color: filled ? (_dark ? Colors.white : _orangeText) : _muted,
      ),
    ),
  );

  Widget _quick(IconData icon, String label, VoidCallback? onTap) => Expanded(
    child: Material(
      color: _surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: _line),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: SizedBox(
          height: 64,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 20, color: onTap == null ? _muted : _orange),
              const SizedBox(height: 4),
              Text(
                label,
                style: StockpileFonts.satoshi(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: onTap == null ? _muted : _text,
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );

  Widget _card({required String label, required Widget child}) => Semantics(
    container: true,
    label: label,
    child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
      decoration: BoxDecoration(
        color: _surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: _line),
      ),
      child: child,
    ),
  );

  Widget _fact(String label, String value) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 11),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(width: 84, child: Text(label, style: StockpileFonts.satoshi(fontSize: 13, color: _muted))),
        Expanded(
          child: Text(
            value.isEmpty ? '—' : value,
            textAlign: TextAlign.right,
            style: StockpileFonts.satoshi(fontSize: 14, fontWeight: FontWeight.w600, color: _text),
          ),
        ),
      ],
    ),
  );

  Widget _referrals() {
    final r = _refs;
    final loading = r == null && !_refsFailed;
    Widget count(String label, List<Member>? list) => Expanded(
      child: Material(
        color: _soft,
        borderRadius: BorderRadius.circular(10),
        child: InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: (list ?? const []).isEmpty ? null : () => _showList(label, list!),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  loading ? '…' : '${list?.length ?? '—'}',
                  style: StockpileFonts.satoshi(fontSize: 22, fontWeight: FontWeight.w800, color: _text),
                ),
                Text(label, style: StockpileFonts.satoshi(fontSize: 12, color: _muted)),
              ],
            ),
          ),
        ),
      ),
    );

    return _card(
      label: 'Referrals',
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Text('Referred by', style: StockpileFonts.satoshi(fontSize: 13, color: _muted)),
                const Spacer(),
                Text(
                  loading
                      ? '…'
                      : (r == null || r.referrerName.isEmpty ? 'No one' : r.referrerName),
                  style: StockpileFonts.satoshi(fontSize: 14, fontWeight: FontWeight.w600, color: _text),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                count('Direct referrals', r?.direct),
                const SizedBox(width: 8),
                count('Indirect referrals', r?.indirect),
              ],
            ),
            if (_refsFailed) ...[
              const SizedBox(height: 8),
              Text('Referrals could not be loaded.', style: StockpileFonts.satoshi(fontSize: 12, color: _muted)),
            ],
          ],
        ),
      ),
    );
  }

  void _showList(String title, List<Member> members) {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: ConstrainedBox(
          constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(ctx).height * 0.7),
          child: ListView(
            shrinkWrap: true,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
                child: Text(title, style: StockpileFonts.satoshi(fontSize: 16, fontWeight: FontWeight.w700)),
              ),
              for (final m in members)
                ListTile(
                  title: Text(
                    [m.firstName, m.lastName].where((p) => (p ?? '').isNotEmpty).join(' ').ifEmpty('Member #${m.id}'),
                  ),
                  subtitle: Text(m.role ?? 'Member'),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _account() {
    final email = _s('email');
    return _card(
      label: 'Login account',
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Login account', style: StockpileFonts.satoshi(fontSize: 13, color: _muted)),
                  const SizedBox(height: 2),
                  Text(
                    _hasAccount ? email.split('@').first : 'None yet',
                    style: StockpileFonts.satoshi(fontSize: 14, fontWeight: FontWeight.w600, color: _text),
                  ),
                ],
              ),
            ),
            if (_hasAccount && widget.onViewPassword != null)
              OutlinedButton(
                onPressed: () => widget.onViewPassword!(context, _refresh),
                style: OutlinedButton.styleFrom(minimumSize: const Size(0, 40), shape: const StadiumBorder()),
                child: const Text('View password'),
              ),
            if (!_hasAccount && widget.onCreateAccount != null)
              OutlinedButton(
                onPressed: () => widget.onCreateAccount!(context, _refresh),
                style: OutlinedButton.styleFrom(minimumSize: const Size(0, 40), shape: const StadiumBorder()),
                child: const Text('Create login'),
              ),
          ],
        ),
      ),
    );
  }
}

extension on String {
  String ifEmpty(String other) => isEmpty ? other : this;
}
