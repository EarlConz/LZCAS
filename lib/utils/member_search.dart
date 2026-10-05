// lib/utils/member_search.dart
//
// Member suggestions for a picker (an Autocomplete's optionsBuilder), asked
// of the database as the person types. Pickers used to download every
// member and search in the app, which is slow and stops at 1,000 members.

import 'dart:async';

import 'package:flutter/material.dart';

import 'package:lzcas/db/db.dart';

/// One per picker. Waits for a pause in typing, and only the newest search
/// may show its results: an older one finishing late keeps what is shown.
class MemberSearch {
  int _ticket = 0;
  Iterable<Member> _last = const [];

  /// Members whose name, number or member ID matches [text], minus
  /// [exclude]. A name needs two characters; an ID ("6", "#6", "ID 6")
  /// searches from its first digit (test SP3: one-digit IDs never did).
  Future<Iterable<Member>> call(String text, {Set<int> exclude = const {}}) async {
    final q = text.trim();
    final ticket = ++_ticket;
    if (q.length < 2 && SupabaseRepository.memberIdQuery(q) == null) return _last = const [];
    await Future<void>.delayed(const Duration(milliseconds: 300));
    if (ticket != _ticket) return _last;
    try {
      final found = await repository.searchMembers(q, excludeIds: exclude);
      if (ticket != _ticket) return _last;
      return _last = found;
    } catch (_) {
      return _last;
    }
  }
}

/// The suggestions under a member picker: the name, then "ID 6 · Gold
/// package" (and [extra], such as "3 referrals"), so staff can tell two
/// members with the same name apart and see that an ID search matched.
Widget memberOptionsView({
  required BuildContext context,
  required AutocompleteOnSelected<Member> onSelected,
  required Iterable<Member> options,
  required String Function(Member) label,
  String Function(Member)? extra,
}) {
  final screenW = MediaQuery.sizeOf(context).width;
  return Align(
    alignment: Alignment.topLeft,
    child: Material(
      elevation: 4,
      borderRadius: BorderRadius.circular(12),
      child: ConstrainedBox(
        // Wide enough to read on a phone, capped on a PC.
        constraints: BoxConstraints(
          maxHeight: 240,
          maxWidth: (screenW - 32).clamp(200.0, 380.0),
        ),
        child: ListView.builder(
          padding: EdgeInsets.zero,
          shrinkWrap: true,
          itemCount: options.length,
          itemBuilder: (context, index) {
            final m = options.elementAt(index);
            final pkg = (m.packageName ?? '').trim();
            final more = extra?.call(m) ?? '';
            final line = [
              'ID ${m.id}',
              if (pkg.isNotEmpty) '$pkg package',
              if (more.isNotEmpty) more,
            ].join(' · ');
            return ListTile(
              dense: true,
              minTileHeight: 48,
              title: Text(label(m), overflow: TextOverflow.ellipsis),
              subtitle: Text(line, overflow: TextOverflow.ellipsis),
              onTap: () => onSelected(m),
            );
          },
        ),
      ),
    ),
  );
}
