// lib/db/db.dart
// Barrel export — now points to Supabase-backed models and repository.

import '../data/supabase_repository.dart';

export '../data/models.dart'
    show
        Item,
        Member,
        Sale,
        Borrow,
        StockMovement,
        PendingRequest,
        Package,
        Category,
        EarningsSnapshot,
        MemberTransactionEntry,
        SystemAlert,
        inventoryItemsFromRows,
        membersFromRows,
        statusFromStock;
export '../data/supabase_repository.dart' show SupabaseRepository, PageResult;

/// Global repository instance. Set by main() before the app runs.
SupabaseRepository get repository {
  final r = _repository;
  if (r == null) throw StateError('Repository not initialized');
  return r;
}

SupabaseRepository? _repository;

void setRepository(SupabaseRepository repo) {
  _repository = repo;
}
