// lib/pages/admin/announcements_page.dart
//
// Admin: post and manage announcements, and control the automatic birthday
// greeting.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import 'package:lzcas/db/db.dart';
import 'package:lzcas/services/config_service.dart';
import 'package:lzcas/theme.dart';
import 'package:lzcas/utils/animations.dart';
import 'package:lzcas/utils/fonts.dart';
import 'package:lzcas/utils/formatters.dart';
import 'package:lzcas/utils/toast_utils.dart';
import 'package:lzcas/widgets/announcement_widgets.dart';

class AdminAnnouncementsPage extends StatefulWidget {
  const AdminAnnouncementsPage({super.key});

  @override
  State<AdminAnnouncementsPage> createState() => _AdminAnnouncementsPageState();
}

class _AdminAnnouncementsPageState extends State<AdminAnnouncementsPage> {
  List<Announcement> _announcements = const [];
  ({int total, int withoutBirthday})? _coverage;
  bool _loading = true;
  StreamSubscription<String>? _sub;

  @override
  void initState() {
    super.initState();
    _load();
    _sub = repository.changes.listen((e) {
      if (e == 'announcements_changed' && mounted) _load();
    });
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    final rows = await repository.fetchAllAnnouncements();
    final coverage = await repository.birthdayCoverage();
    if (!mounted) return;
    setState(() {
      _announcements = rows;
      _coverage = coverage;
      _loading = false;
    });
  }

  Future<void> _compose({Announcement? existing}) async {
    final saved = await showAnnouncementEditor(context, existing: existing);
    if (saved == true) _load();
  }

  /// Archiving, never deleting — a member may have this in their saved list,
  /// and the count is shown before the admin commits so they know.
  Future<void> _confirmArchive(Announcement a) async {
    final savedBy = await repository.countMembersWhoSaved(a.id);
    if (!mounted) return;

    final ok = await showAnimatedDialog<bool>(
      context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        title: const Text('Take this down?'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '“${a.title}” stops showing to everyone it was sent to.',
              style: Theme.of(ctx).textTheme.bodyMedium,
            ),
            const SizedBox(height: 12),
            Text(
              savedBy == 0
                  ? 'Nobody has saved it.'
                  : savedBy == 1
                  ? '1 member has saved this and will keep their copy.'
                  : '$savedBy members have saved this and will keep their '
                        'copies.',
              style: Theme.of(
                ctx,
              ).textTheme.bodySmall?.copyWith(color: StockpileColors.mutedText),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Take it down'),
          ),
        ],
      ),
    );

    if (ok != true) return;
    final done = await repository.archiveAnnouncement(a.id);
    if (!mounted) return;
    if (done) {
      showSuccessToast('Announcement taken down');
      _load();
    } else {
      showErrorToast('Could not take it down.');
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _header(context, isDark),
          const SizedBox(height: 20),
          if (_loading)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 60),
              child: Center(child: CircularProgressIndicator()),
            )
          else ...[
            _list(isDark),
            const SizedBox(height: 20),
            _BirthdayPanel(
              coverage: _coverage,
              isDark: isDark,
              onEdited: _load,
            ),
          ],
        ],
      ),
    );
  }

  Widget _header(BuildContext context, bool isDark) {
    final theme = Theme.of(context);

    final title = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text('Announcements', style: theme.textTheme.titleLarge),
        const SizedBox(height: 2),
        Text(
          'Shown on the Announcements screen of every account you send '
          'them to.',
          style: theme.textTheme.bodySmall?.copyWith(
            color: StockpileColors.mutedText,
          ),
        ),
      ],
    );

    final button = FilledButton.icon(
      onPressed: () => _compose(),
      icon: const Icon(Icons.add_rounded, size: 18),
      label: const Text('New Announcement'),
    );

    // Side by side there is not enough room on a phone for both the
    // description and a button whose label is two words long, so the button
    // drops below and takes the full width.
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth >= 560) {
          return Row(
            children: [
              Expanded(child: title),
              const SizedBox(width: 16),
              button,
            ],
          );
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [title, const SizedBox(height: 14), button],
        );
      },
    );
  }

  Widget _list(bool isDark) {
    final divider = isDark
        ? StockpileColors.darkDivider
        : StockpileColors.divider;

    if (_announcements.isEmpty) {
      return _shell(
        isDark,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 40),
          child: Center(
            child: Text(
              'No announcements yet.',
              style: StockpileFonts.satoshi(
                fontSize: 14,
                color: StockpileColors.mutedText,
              ),
            ),
          ),
        ),
      );
    }

    // The table form needs 502px of fixed columns before the title gets any
    // space at all, so on a phone it is replaced by stacked cards rather than
    // squeezed. The column headings go with it — they label nothing once the
    // columns are gone.
    return LayoutBuilder(
      builder: (context, constraints) {
        final wide = constraints.maxWidth >= 720;
        return _shell(
          isDark,
          child: Column(
            children: [
              if (wide) _headerRow(isDark),
              for (var i = 0; i < _announcements.length; i++) ...[
                if (i > 0) Divider(height: 1, color: divider.withAlpha(120)),
                wide
                    ? _row(_announcements[i], isDark)
                    : _card(_announcements[i], isDark),
              ],
            ],
          ),
        );
      },
    );
  }

  /// Narrow-width form of [_row]: the same information stacked, with the
  /// chips wrapping instead of sitting in fixed columns.
  Widget _card(Announcement a, bool isDark) {
    final live = a.isCurrent();
    final textColor = live
        ? (isDark ? StockpileColors.darkTextPrimary : StockpileColors.darkText)
        : StockpileColors.mutedText;

    return Container(
      color: live
          ? null
          : (isDark
                ? Colors.white.withValues(alpha: 0.02)
                : const Color(0xFFFCFCFD)),
      padding: const EdgeInsets.fromLTRB(16, 14, 8, 14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  a.title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: StockpileFonts.satoshi(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    height: 1.3,
                    color: textColor,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  a.body,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: StockpileFonts.satoshi(
                    fontSize: 12,
                    height: 1.4,
                    color: StockpileColors.mutedText,
                  ),
                ),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 8,
                  runSpacing: 6,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    _chip(
                      a.isArchived ? 'Taken down' : (live ? 'Active' : 'Ended'),
                      bg: live
                          ? StockpileColors.successBg
                          : (isDark
                                ? StockpileColors.darkInputBg
                                : StockpileColors.inputBg),
                      fg: live
                          ? const Color(0xFF16A34A)
                          : StockpileColors.mutedText,
                      bold: true,
                    ),
                    _audienceChip(a, isDark),
                    Text(
                      a.endsAt == null
                          ? 'No end date'
                          : 'Until ${formatDayAndMonth(a.endsAt)}',
                      style: StockpileFonts.satoshi(
                        fontSize: 12,
                        color: StockpileColors.mutedText,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          Column(
            children: [
              IconButton(
                tooltip: 'Edit',
                iconSize: 18,
                onPressed: a.isArchived ? null : () => _compose(existing: a),
                icon: const Icon(Icons.edit_outlined),
              ),
              IconButton(
                tooltip: 'Take down',
                iconSize: 18,
                onPressed: a.isArchived ? null : () => _confirmArchive(a),
                icon: const Icon(Icons.archive_outlined),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _shell(bool isDark, {required Widget child}) => Container(
    width: double.infinity,
    decoration: BoxDecoration(
      color: isDark ? StockpileColors.darkSurface : StockpileColors.surface,
      borderRadius: BorderRadius.circular(16),
      border: Border.all(
        color: isDark ? StockpileColors.darkDivider : StockpileColors.divider,
      ),
    ),
    clipBehavior: Clip.antiAlias,
    child: child,
  );

  Widget _headerRow(bool isDark) {
    Widget h(String text, {double? width, bool grow = false}) {
      final child = Text(
        text,
        style: StockpileFonts.satoshi(
          fontSize: 13,
          fontWeight: FontWeight.w600,
          color: StockpileColors.mutedText,
        ),
      );
      if (grow) return Expanded(child: child);
      return SizedBox(width: width, child: child);
    }

    return Container(
      color: isDark ? StockpileColors.darkInputBg : StockpileColors.tableHead,
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      child: Row(
        children: [
          h('Announcement', grow: true),
          const SizedBox(width: 16),
          h('Audience', width: 130),
          const SizedBox(width: 16),
          h('Status', width: 100),
          const SizedBox(width: 16),
          h('Shows until', width: 120),
          const SizedBox(width: 16),
          const SizedBox(width: 88),
        ],
      ),
    );
  }

  Widget _row(Announcement a, bool isDark) {
    final live = a.isCurrent();
    final textColor = live
        ? (isDark ? StockpileColors.darkTextPrimary : StockpileColors.darkText)
        : StockpileColors.mutedText;

    return Container(
      color: live
          ? null
          : (isDark
                ? Colors.white.withValues(alpha: 0.02)
                : const Color(0xFFFCFCFD)),
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  a.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: StockpileFonts.satoshi(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: textColor,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  a.body,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: StockpileFonts.satoshi(
                    fontSize: 12,
                    color: StockpileColors.mutedText,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 16),
          SizedBox(width: 130, child: _audienceChip(a, isDark)),
          const SizedBox(width: 16),
          SizedBox(
            width: 100,
            child: _chip(
              a.isArchived ? 'Taken down' : (live ? 'Active' : 'Ended'),
              bg: live
                  ? StockpileColors.successBg
                  : (isDark
                        ? StockpileColors.darkInputBg
                        : StockpileColors.inputBg),
              fg: live ? const Color(0xFF16A34A) : StockpileColors.mutedText,
              bold: true,
            ),
          ),
          const SizedBox(width: 16),
          SizedBox(
            width: 120,
            child: Text(
              a.endsAt == null ? 'No end date' : formatDayAndMonth(a.endsAt),
              style: StockpileFonts.satoshi(
                fontSize: 13,
                color: a.endsAt == null ? StockpileColors.mutedText : textColor,
              ),
            ),
          ),
          const SizedBox(width: 16),
          SizedBox(
            width: 88,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                IconButton(
                  tooltip: 'Edit',
                  iconSize: 18,
                  onPressed: a.isArchived ? null : () => _compose(existing: a),
                  icon: const Icon(Icons.edit_outlined),
                ),
                IconButton(
                  tooltip: 'Take down',
                  iconSize: 18,
                  onPressed: a.isArchived ? null : () => _confirmArchive(a),
                  icon: const Icon(Icons.archive_outlined),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// Audience chip, shared by the wide row and the narrow card so the two
  /// forms cannot disagree about what an audience is called.
  ///
  /// Branches is tinted because it is the one that reaches staff rather than
  /// customers — the distinction worth catching at a glance before posting.
  Widget _audienceChip(Announcement a, bool isDark) {
    final isBranches = a.audience == AnnouncementAudience.branches;
    return _chip(
      switch (a.audience) {
        AnnouncementAudience.all => 'Everyone',
        AnnouncementAudience.branches => 'Branches',
        AnnouncementAudience.members => 'Members',
      },
      bg: isBranches
          ? StockpileColors.secondary50
          : (isDark ? StockpileColors.darkInputBg : StockpileColors.inputBg),
      fg: isBranches ? StockpileColors.secondary500 : StockpileColors.bodyText,
    );
  }

  Widget _chip(
    String text, {
    required Color bg,
    required Color fg,
    bool bold = false,
  }) {
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(100),
        ),
        child: Text(
          text,
          style: StockpileFonts.satoshi(
            fontSize: 12,
            fontWeight: bold ? FontWeight.w700 : FontWeight.w600,
            color: fg,
          ),
        ),
      ),
    );
  }
}

// ─── Birthday panel ─────────────────────────────────────────────────────

/// Controls the automatic greeting, and names the gap it cannot close:
/// members with no readable birthday get nothing, silently. Surfacing that
/// count is the difference between a feature that works and one that only
/// appears to.
class _BirthdayPanel extends StatelessWidget {
  final ({int total, int withoutBirthday})? coverage;
  final bool isDark;
  final VoidCallback onEdited;

  const _BirthdayPanel({
    required this.coverage,
    required this.isDark,
    required this.onEdited,
  });

  @override
  Widget build(BuildContext context) {
    final config = context.watch<ConfigService>();
    final on = config.birthdayGreetingsEnabled;
    final days = config.birthdayGreetingDays;
    final missing = coverage?.withoutBirthday ?? 0;

    final textColor = isDark
        ? StockpileColors.darkTextPrimary
        : StockpileColors.darkText;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
      decoration: BoxDecoration(
        color: isDark ? StockpileColors.darkSurface : StockpileColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isDark ? StockpileColors.darkDivider : StockpileColors.divider,
        ),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          // Icon + a paragraph + a button in one row leaves the paragraph
          // about 120px on a phone, which turns it into a ragged column of
          // single words. Below the breakpoint the button moves underneath
          // and the text gets the full width.
          final wide = constraints.maxWidth >= 520;

          final icon = Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: StockpileColors.primary900.withValues(alpha: 0.10),
              shape: BoxShape.circle,
            ),
            alignment: Alignment.center,
            child: const Icon(
              Icons.cake_rounded,
              size: 20,
              color: StockpileColors.primary900,
            ),
          );

          final body = Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                on ? 'Birthday greetings are on' : 'Birthday greetings are off',
                style: StockpileFonts.satoshi(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  color: textColor,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                on
                    ? 'A reseller sees a greeting on their Overview for '
                          '$days days after their birthday, so they still '
                          'get it even if they do not open the app on the '
                          'day itself.'
                          '${missing > 0 ? ' $missing '
                                    '${missing == 1 ? 'reseller has' : 'resellers have'} '
                                    'no birthday recorded and will not receive one.' : ''}'
                    : 'No greetings are being shown.',
                style: StockpileFonts.satoshi(
                  fontSize: 13,
                  height: 1.5,
                  color: isDark
                      ? StockpileColors.darkTextBody
                      : StockpileColors.bodyText,
                ),
              ),
            ],
          );

          final button = OutlinedButton(
            onPressed: () async {
              final saved = await showBirthdaySettingsDialog(
                context,
                coverage: coverage,
              );
              if (saved == true) onEdited();
            },
            child: const Text('Edit message'),
          );

          if (wide) {
            return Row(
              children: [
                icon,
                const SizedBox(width: 14),
                Expanded(child: body),
                const SizedBox(width: 16),
                button,
              ],
            );
          }
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  icon,
                  const SizedBox(width: 14),
                  Expanded(child: body),
                ],
              ),
              const SizedBox(height: 14),
              button,
            ],
          );
        },
      ),
    );
  }
}

// ─── Compose / edit dialog ──────────────────────────────────────────────

/// Post a new announcement, or edit one. Returns true when something was
/// written.
Future<bool?> showAnnouncementEditor(
  BuildContext context, {
  Announcement? existing,
}) => showAnimatedDialog<bool>(
  context,
  builder: (ctx) => _AnnouncementEditor(existing: existing),
);

class _AnnouncementEditor extends StatefulWidget {
  final Announcement? existing;
  const _AnnouncementEditor({this.existing});

  @override
  State<_AnnouncementEditor> createState() => _AnnouncementEditorState();
}

class _AnnouncementEditorState extends State<_AnnouncementEditor> {
  static const _bodyMaxLength = 400;

  late final TextEditingController _title;
  late final TextEditingController _body;
  late AnnouncementAudience _audience;
  DateTime? _endsAt;
  bool _submitting = false;

  /// How many accounts the chosen audience reaches. A number turns an
  /// abstract choice into something an admin notices is wrong before
  /// posting.
  Map<AnnouncementAudience, int> _reach = const {};

  bool get _isEdit => widget.existing != null;

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    _title = TextEditingController(text: e?.title ?? '')
      ..addListener(_onChanged);
    _body = TextEditingController(text: e?.body ?? '')..addListener(_onChanged);
    _audience = e?.audience ?? AnnouncementAudience.all;
    _endsAt = e?.endsAt?.toLocal();
    _loadReach();
  }

  @override
  void dispose() {
    _title.dispose();
    _body.dispose();
    super.dispose();
  }

  void _onChanged() => setState(() {});

  Future<void> _loadReach() async {
    // Members and resellers both live in `members`; branch cashiers are
    // staff accounts in `profiles`, so the two counts come from different
    // places and "Everyone" is their sum.
    final members = await repository.fetchMembers();
    final staff = await repository.fetchCashierProfiles();
    if (!mounted) return;
    final branches = staff.where((p) => p.role == 'branch_cashier').length;
    setState(() {
      _reach = {
        AnnouncementAudience.all: members.length + branches,
        AnnouncementAudience.branches: branches,
        // Members AND resellers — no longer split, see migration v38.
        AnnouncementAudience.members: members.length,
      };
    });
  }

  /// Stacked, a field should size to its content; side by side it should share
  /// the row evenly. [Expanded] means "fill the main axis", which is wrong in
  /// a vertical Flex — it would stretch each field to fill the dialog height.
  static Widget _flexChild(bool stacked, Widget child) =>
      stacked ? child : Expanded(child: child);

  bool get _canSubmit =>
      !_submitting &&
      _title.text.trim().length >= 3 &&
      _body.text.trim().length >= 3;

  Future<void> _pickEndDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _endsAt ?? now.add(const Duration(days: 14)),
      firstDate: now,
      lastDate: DateTime(now.year + 3),
    );
    if (picked == null || !mounted) return;
    // End of the chosen day, so "show until 21 December" includes the 21st.
    setState(
      () => _endsAt = DateTime(picked.year, picked.month, picked.day, 23, 59),
    );
  }

  Future<void> _submit() async {
    if (!_canSubmit) return;
    setState(() => _submitting = true);

    final error = _isEdit
        ? await repository.updateAnnouncement(
            id: widget.existing!.id,
            title: _title.text,
            body: _body.text,
            audience: _audience,
            endsAt: _endsAt,
          )
        : await repository.createAnnouncement(
            title: _title.text,
            body: _body.text,
            audience: _audience,
            endsAt: _endsAt,
          );

    if (!mounted) return;
    if (error != null) {
      setState(() => _submitting = false);
      showErrorToast(error);
      return;
    }
    showSuccessToast(_isEdit ? 'Announcement updated' : 'Announcement posted');
    Navigator.pop(context, true);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isNarrow = MediaQuery.sizeOf(context).width < 500;
    final reach = _reach[_audience];

    return _ResponsiveFormDialog(
      isNarrow: isNarrow,
      icon: Icons.campaign_rounded,
      title: _isEdit ? 'Edit Announcement' : 'New Announcement',
      subtitle: _isEdit
          ? 'Changes show the next time someone opens the app'
          : 'Goes live as soon as you post it',
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextField(
            controller: _title,
            enabled: !_submitting,
            textCapitalization: TextCapitalization.sentences,
            inputFormatters: [LengthLimitingTextInputFormatter(90)],
            decoration: const InputDecoration(
              labelText: 'Title',
              // The Overview strip shows one line, so the opening words
              // have to carry the notice on their own.
              helperText: 'The first few words are what most people see.',
            ),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _body,
            enabled: !_submitting,
            maxLines: 4,
            maxLength: _bodyMaxLength,
            textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(
              labelText: 'Message',
              helperText: 'Write it the way you would say it to them.',
            ),
          ),
          const SizedBox(height: 8),
          // Side by side these two get ~150px each on a phone, which is
          // not enough for a dropdown value plus the date field's suffix
          // button. Narrow stacks them.
          Flex(
            direction: isNarrow ? Axis.vertical : Axis.horizontal,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _flexChild(
                isNarrow,
                DropdownButtonFormField<AnnouncementAudience>(
                  isExpanded: true,
                  initialValue: _audience,
                  decoration: InputDecoration(
                    labelText: 'Send to',
                    helperText: reach == null
                        ? ' '
                        : '$reach account${reach == 1 ? '' : 's'}',
                  ),
                  items: [
                    for (final a in AnnouncementAudience.values)
                      DropdownMenuItem(value: a, child: Text(a.label)),
                  ],
                  onChanged: _submitting
                      ? null
                      : (v) => setState(() => _audience = v ?? _audience),
                ),
              ),
              SizedBox(width: isNarrow ? 0 : 12, height: isNarrow ? 8 : 0),
              _flexChild(
                isNarrow,
                InkWell(
                  onTap: _submitting ? null : _pickEndDate,
                  borderRadius: BorderRadius.circular(12),
                  child: InputDecorator(
                    decoration: InputDecoration(
                      labelText: 'Show until',
                      helperText: _endsAt == null
                          ? 'Leave blank to keep it up'
                          : 'Tap to change',
                      suffixIcon: _endsAt == null
                          ? const Icon(Icons.calendar_today_rounded, size: 18)
                          : IconButton(
                              iconSize: 18,
                              tooltip: 'Clear',
                              onPressed: () => setState(() => _endsAt = null),
                              icon: const Icon(Icons.close_rounded),
                            ),
                    ),
                    child: Text(
                      _endsAt == null
                          ? 'No end date'
                          : formatDayAndMonth(_endsAt),
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: _endsAt == null
                            ? StockpileColors.mutedText
                            : null,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: StockpileColors.mutedText.withValues(alpha: 0.10),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(
                  Icons.info_outline_rounded,
                  size: 18,
                  color: StockpileColors.mutedText,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Everyone you send this to sees it the next time they '
                    'open the app. They can star it to keep it after it '
                    'ends.',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: StockpileColors.mutedText,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: _submitting ? null : () => Navigator.pop(context, false),
          child: const Text('Cancel'),
        ),
        FilledButton.icon(
          onPressed: _canSubmit ? _submit : null,
          icon: _submitting
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.check_rounded, size: 18),
          label: Text(_isEdit ? 'Save changes' : 'Post Announcement'),
        ),
      ],
    );
  }
}

// ─── Birthday settings dialog ───────────────────────────────────────────

Future<bool?> showBirthdaySettingsDialog(
  BuildContext context, {
  ({int total, int withoutBirthday})? coverage,
}) => showAnimatedDialog<bool>(
  context,
  builder: (ctx) => _BirthdaySettingsDialog(coverage: coverage),
);

/// Shell for the two admin forms — the announcement editor and the birthday
/// settings — so both behave the same at every width.
///
/// **Wide** keeps the familiar 480px centred dialog.
///
/// **Narrow goes full-screen**, which is the point of this widget. A default
/// [AlertDialog] on a 360px phone insets 40px each side and pads 24px more,
/// leaving about 232px for a form containing a multi-line message field, a
/// dropdown, a date field, a preview card and a row of chips — everything
/// technically fitted, and all of it cramped. Full-screen gives roughly 320px
/// of width and the whole height, so the same content simply has room.
///
/// Actions sit in a bottom bar on narrow rather than the usual trailing row:
/// with a scrolling body the buttons need to stay put and stay reachable with
/// a thumb.
class _ResponsiveFormDialog extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;

  /// Optional control in the heading — the birthday dialog's on/off switch.
  final Widget? trailing;
  final Widget content;
  final List<Widget> actions;
  final bool isNarrow;

  const _ResponsiveFormDialog({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.content,
    required this.actions,
    required this.isNarrow,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final divider = isDark
        ? StockpileColors.darkDivider
        : StockpileColors.divider;

    final heading = _DialogHeading(
      icon: icon,
      title: title,
      subtitle: subtitle,
      isNarrow: isNarrow,
      trailing: trailing,
    );

    if (!isNarrow) {
      return AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        titlePadding: const EdgeInsets.fromLTRB(24, 22, 24, 0),
        contentPadding: const EdgeInsets.fromLTRB(24, 16, 24, 8),
        title: heading,
        content: SizedBox(
          width: 480,
          child: SingleChildScrollView(child: content),
        ),
        actions: actions,
      );
    }

    return Dialog.fullscreen(
      backgroundColor: isDark
          ? StockpileColors.darkBg
          : StockpileColors.scaffoldBg,
      child: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 18, 20, 16),
              child: heading,
            ),
            Divider(height: 1, color: divider),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(20, 20, 20, 24),
                child: content,
              ),
            ),
            Divider(height: 1, color: divider),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 12),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  for (var i = 0; i < actions.length; i++) ...[
                    if (i > 0) const SizedBox(width: 8),
                    actions[i],
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

/// Shared dialog heading: icon, title, subtitle and an optional trailing
/// control.
///
/// Wide keeps everything on one row. Narrow drops the subtitle to its own
/// full-width line and scales the title down to fit rather than overflowing —
/// an AlertDialog on a phone is about 280px wide, and the icon plus a Switch
/// take most of the room a headline would need.
class _DialogHeading extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final bool isNarrow;
  final Widget? trailing;

  const _DialogHeading({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.isNarrow,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    final titleText = Text(
      title,
      maxLines: 1,
      style: theme.textTheme.headlineSmall?.copyWith(
        fontWeight: FontWeight.w700,
      ),
    );
    final subtitleText = Text(
      subtitle,
      style: theme.textTheme.bodySmall?.copyWith(
        color: StockpileColors.mutedText,
      ),
    );
    final iconWidget = Icon(icon, color: theme.colorScheme.primary, size: 28);

    if (!isNarrow) {
      return Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          iconWidget,
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [titleText, subtitleText],
            ),
          ),
          if (trailing != null) trailing!,
        ],
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          children: [
            iconWidget,
            const SizedBox(width: 10),
            Expanded(
              child: FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: titleText,
              ),
            ),
            if (trailing != null) trailing!,
          ],
        ),
        const SizedBox(height: 4),
        subtitleText,
      ],
    );
  }
}

class _BirthdaySettingsDialog extends StatefulWidget {
  final ({int total, int withoutBirthday})? coverage;
  const _BirthdaySettingsDialog({this.coverage});

  @override
  State<_BirthdaySettingsDialog> createState() =>
      _BirthdaySettingsDialogState();
}

class _BirthdaySettingsDialogState extends State<_BirthdaySettingsDialog> {
  /// Every sensible answer, as buttons. A free-text day count is one more
  /// field that can be typed wrong for no gain — an existing value outside
  /// this set is preserved as its own chip rather than snapped.
  static const _presetDays = [7, 14, 30, 60];

  /// Sample name for the preview. The real card puts the member's own first
  /// name here; the helper under the field says so.
  static const _sampleName = 'Maria';

  late final TextEditingController _message;
  late bool _enabled;
  late int _days;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final config = context.read<ConfigService>();
    _enabled = config.birthdayGreetingsEnabled;
    _days = config.birthdayGreetingDays;
    _message = TextEditingController(text: config.birthdayGreetingMessage)
      ..addListener(_onChanged);
  }

  @override
  void dispose() {
    _message.dispose();
    super.dispose();
  }

  void _onChanged() => setState(() {});

  List<int> get _dayChoices {
    final set = {..._presetDays, _days}.toList()..sort();
    return set;
  }

  /// The birthday the preview is pretending to show: far enough back that
  /// the card is at the OLDEST it can appear.
  ///
  /// That is the state the wording is most likely to fail in — anyone
  /// writing "hope you have a wonderful day" should see straight away that
  /// it will not hold three weeks later. It also makes the sentence under
  /// the day chips exact: this date, kept until today.
  DateTime get _previewBirthday =>
      DateTime.now().subtract(Duration(days: _days - 1));

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      await repository.updateAppConfig(
        'birthday_greetings_enabled',
        _enabled ? 'true' : 'false',
      );
      await repository.updateAppConfig('birthday_greeting_days', '$_days');
      await repository.updateAppConfig(
        'birthday_greeting_message',
        _message.text.trim(),
      );
      if (!mounted) return;
      await context.read<ConfigService>().refresh();
      if (!mounted) return;
      showSuccessToast('Birthday greeting saved');
      Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      showErrorToast('Could not save the birthday greeting.');
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final isNarrow = MediaQuery.sizeOf(context).width < 500;

    return _ResponsiveFormDialog(
      isNarrow: isNarrow,
      icon: Icons.cake_rounded,
      title: 'Birthday Greeting',
      subtitle: 'Goes out on its own. Nobody has to remember.',
      // In the heading rather than as the first field, so the switch reads as
      // governing the dialog instead of competing with what it governs.
      trailing: Switch(
        value: _enabled,
        onChanged: _saving ? null : (v) => setState(() => _enabled = v),
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (!_enabled) ...[
            _banner(
              theme,
              icon: Icons.cancel_outlined,
              color: StockpileColors.mutedText,
              text:
                  'No greetings are being shown. Anyone whose birthday '
                  'passes while this is off will not get one later — it '
                  'is not held back and sent afterwards.',
            ),
            const SizedBox(height: 18),
          ],
          // Everything the switch governs dims together rather than
          // disappearing, so an admin can see what they are turning off
          // before they commit to it.
          Opacity(
            opacity: _enabled ? 1 : 0.4,
            child: IgnorePointer(
              ignoring: !_enabled,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _sectionLabel(theme, 'WHAT A RESELLER SEES'),
                  const SizedBox(height: 8),
                  // The real widget, not a mock-up of it — a preview that
                  // can drift from the thing it previews is worse than
                  // none at all.
                  BirthdayGreetingCard(
                    greeting: BirthdayGreeting(
                      year: _previewBirthday.year,
                      occurredOn: _previewBirthday,
                      daysSince: _days - 1,
                    ),
                    firstName: _sampleName,
                    message: _message.text.trim().isEmpty
                        ? '…'
                        : _message.text.trim(),
                    onToggleSaved: null,
                    isDark: isDark,
                  ),
                  const SizedBox(height: 6),
                  _hint(
                    theme,
                    'Shown at the latest it can appear, so you can see '
                    'the wording still works weeks after the day.',
                  ),
                  const SizedBox(height: 20),
                  TextField(
                    controller: _message,
                    enabled: !_saving,
                    maxLines: 3,
                    maxLength: 240,
                    textCapitalization: TextCapitalization.sentences,
                    decoration: const InputDecoration(
                      labelText: 'Message',
                      helperText: 'Their first name is added for you.',
                    ),
                  ),
                  const SizedBox(height: 12),
                  _sectionLabel(theme, 'KEEP SHOWING IT FOR'),
                  const SizedBox(height: 8),
                  // Four chips sharing a phone-width dialog get about
                  // 52px each, which clips "60 days". Narrow wraps them
                  // onto as many rows as they need instead.
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final d in _dayChoices)
                        SizedBox(
                          width: isNarrow ? 76 : null,
                          child: _DayChip(
                            days: d,
                            selected: d == _days,
                            onTap: _saving
                                ? null
                                : () => setState(() => _days = d),
                            isDark: isDark,
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  _hint(
                    theme,
                    'A ${formatDayAndMonth(_previewBirthday)} birthday '
                    'keeps showing until '
                    '${formatDayAndMonth(DateTime.now())}.',
                  ),
                  if (widget.coverage != null) ...[
                    const SizedBox(height: 18),
                    _coverageBanner(theme, widget.coverage!),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.pop(context, false),
          child: const Text('Cancel'),
        ),
        FilledButton.icon(
          onPressed: _saving ? null : _save,
          icon: _saving
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.check_rounded, size: 18),
          label: const Text('Save greeting'),
        ),
      ],
    );
  }

  Widget _sectionLabel(ThemeData theme, String text) => Text(
    text,
    style: StockpileFonts.satoshi(
      fontSize: 11,
      height: 1.3,
      fontWeight: FontWeight.w700,
      letterSpacing: 0.7,
      color: StockpileColors.mutedText,
    ),
  );

  Widget _hint(ThemeData theme, String text) => Text(
    text,
    style: theme.textTheme.bodySmall?.copyWith(
      fontSize: 12,
      height: 1.4,
      color: StockpileColors.mutedText,
    ),
  );

  /// The number that says whether this feature is actually reaching people.
  /// It belongs here, where the decision is made, not only on the page
  /// behind the dialog.
  Widget _coverageBanner(
    ThemeData theme,
    ({int total, int withoutBirthday}) c,
  ) {
    final withBirthday = c.total - c.withoutBirthday;
    final allCovered = c.withoutBirthday == 0;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: StockpileColors.primary900.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: StockpileColors.primary900.withValues(alpha: 0.28),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(
            Icons.info_outline_rounded,
            size: 18,
            color: StockpileColors.primary900,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              allCovered
                  ? 'All ${c.total} resellers have a birthday recorded.'
                  : '$withBirthday of ${c.total} resellers have a birthday '
                        'recorded. The other ${c.withoutBirthday} will not '
                        'get a greeting until someone fills theirs in.',
              style: theme.textTheme.bodySmall?.copyWith(
                fontSize: 13,
                height: 1.45,
                color: theme.colorScheme.onSurface,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _banner(
    ThemeData theme, {
    required IconData icon,
    required Color color,
    required String text,
  }) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: color),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              style: theme.textTheme.bodySmall?.copyWith(
                fontSize: 13,
                height: 1.45,
                color: theme.colorScheme.onSurface,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// One window-length choice. 44px tall so it clears a comfortable target,
/// and radius 12 to match the input language rather than a pill.
class _DayChip extends StatelessWidget {
  final int days;
  final bool selected;
  final VoidCallback? onTap;
  final bool isDark;

  const _DayChip({
    required this.days,
    required this.selected,
    required this.onTap,
    required this.isDark,
  });

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular(12);
    final idleFill = isDark
        ? StockpileColors.darkInputBg
        : StockpileColors.inputBg;
    final idleBorder = isDark
        ? StockpileColors.darkDivider
        : StockpileColors.divider;
    final idleText = isDark
        ? StockpileColors.darkTextMuted
        : StockpileColors.mutedText;

    return Material(
      color: selected
          ? (isDark
                ? StockpileColors.primary900.withValues(alpha: 0.16)
                : StockpileColors.primary50)
          : idleFill,
      borderRadius: radius,
      child: InkWell(
        onTap: onTap,
        borderRadius: radius,
        child: Container(
          height: 44,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            borderRadius: radius,
            border: Border.all(
              color: selected ? StockpileColors.primary900 : idleBorder,
              width: selected ? 1.5 : 1,
            ),
          ),
          child: Text(
            '$days days',
            style: StockpileFonts.satoshi(
              fontSize: 14,
              fontWeight: selected ? FontWeight.w700 : FontWeight.w600,
              color: selected ? StockpileColors.primary900 : idleText,
            ),
          ),
        ),
      ),
    );
  }
}
