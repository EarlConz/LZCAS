// lib/utils/member_search.dart
//
// Member suggestions for a picker (an Autocomplete's optionsBuilder), asked
// of the database as the person types. Pickers used to download every
// member and search in the app, which is slow and stops at 1,000 members.

import 'dart:async';

import 'package:lzcas/db/db.dart';

/// One per picker. Waits for a pause in typing, and only the newest search
/// may show its results: an older one finishing late keeps what is shown.
class MemberSearch {
  int _ticket = 0;
  Iterable<Member> _last = const [];

  /// Members whose name or number matches [text], minus [exclude]. Fewer
  /// than two characters gives none.
  Future<Iterable<Member>> call(String text, {Set<int> exclude = const {}}) async {
    final q = text.trim();
    final ticket = ++_ticket;
    if (q.length < 2) return _last = const [];
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
