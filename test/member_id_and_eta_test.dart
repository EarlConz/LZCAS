// Member ID searches (test SP3) and the rider's arrival-time working (ET4).

import 'package:flutter_test/flutter_test.dart';

import 'package:lzcas/data/supabase_repository.dart' show SupabaseRepository;
import 'package:lzcas/services/eta_estimator.dart';

void main() {
  test('a member ID is read however staff type it', () {
    for (final typed in ['6', ' 6 ', '#6', '# 6', 'ID 6', 'id6', 'Id: 6', 'ID:6']) {
      expect(SupabaseRepository.memberIdQuery(typed), 6, reason: typed);
    }
    expect(SupabaseRepository.memberIdQuery('41'), 41);
    for (final typed in ['', 'Juan', 'Juan 6', '0917 123 4567', '6a', 'ID']) {
      expect(SupabaseRepository.memberIdQuery(typed), isNull, reason: typed);
    }
  });

  test('the arrival time shows its working', () {
    const t = EtaTuning(factor: 1.2, handoverMinutes: 3);
    expect(t.explain(const Duration(minutes: 15)), 'Map 15 min × 1.2 + 3 min handover');
    expect(t.apply(const Duration(minutes: 15)).inMinutes, 21);
    const noHandover = EtaTuning(factor: 1.5, handoverMinutes: 0);
    expect(noHandover.explain(const Duration(seconds: 20)), 'Map <1 min × 1.5');
  });
}
