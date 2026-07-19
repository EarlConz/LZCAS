// lib/services/bonus_engine.dart
// Clean, isolated bonus calculation service for the LZCAS MLM system.
// All logic is separated from UI and repository I/O — this service only
// computes payouts; the caller is responsible for persisting transactions.

import '../data/models.dart';

/// Result of a bonus computation: who gets paid, how much, and why.
class BonusTransaction {
  final int recipientMemberId;
  final int amount;
  final String reason; // e.g. 'direct_referral', 'indirect_referral', etc.

  const BonusTransaction({
    required this.recipientMemberId,
    required this.amount,
    required this.reason,
  });
}

/// Pure computation engine for the LZCAS referral / commission system.
///
/// Does NOT perform I/O.  Callers supply lookups via callbacks so the engine
/// works identically whether backed by Supabase, Drift, or stubs in tests.
class BonusEngine {
  const BonusEngine();

  // ═════════════════════════════════════════════════════════════════════════
  // Passive Income — per-item purchase bonuses
  // ═════════════════════════════════════════════════════════════════════════

  /// Compute passive-income bonuses when [buyerId] purchases [itemCount]
  /// product items (NOT package availments).
  ///
  /// Returns a list of [BonusTransaction]s, one per referrer who qualifies.
  /// - Direct referrer earns 5 per item
  /// - Indirect referrer (referrer of the direct referrer) earns 3 per item
  List<BonusTransaction> computePassiveIncome({
    required int buyerId,
    required int itemCount,
    required Member? Function(int memberId) resolveMember,
  }) {
    if (itemCount <= 0) return [];

    final results = <BonusTransaction>[];

    // Walk up exactly two levels: direct → indirect
    final directReferrerId = _referrerId(buyerId, resolveMember);
    if (directReferrerId == null) return results;

    // Direct referral bonus: 5 per item
    results.add(BonusTransaction(
      recipientMemberId: directReferrerId,
      amount: 5 * itemCount,
      reason: 'passive_direct',
    ));

    // Indirect referral bonus: 3 per item
    final indirectReferrerId = _referrerId(directReferrerId, resolveMember);
    if (indirectReferrerId != null) {
      results.add(BonusTransaction(
        recipientMemberId: indirectReferrerId,
        amount: 3 * itemCount,
        reason: 'passive_indirect',
      ));
    }

    return results;
  }

  // ═════════════════════════════════════════════════════════════════════════
  // Package Registration Bonus (new sign-up)
  // ═════════════════════════════════════════════════════════════════════════

  /// Compute bonuses when [newMemberId] registers with [chosenPackage].
  ///
  /// - Direct referrer gets the `directReferralBonus` from *their own* package.
  /// - Indirect referrer gets the `indirectReferralBonus` from *their own* package.
  /// - Chairman bonus: 50 for Starter (1500), 100 for Ambassador (3000).
  List<BonusTransaction> computeRegistrationBonuses({
    required int newMemberId,
    required Package chosenPackage,
    required Member? Function(int memberId) resolveMember,
    required Package? Function(int packageId)? resolvePackage,
  }) {
    final results = <BonusTransaction>[];

    // Direct referrer
    final directReferrerId = _referrerId(newMemberId, resolveMember);
    if (directReferrerId == null) return results;

    final directMember = resolveMember(directReferrerId);
    if (directMember?.packageId != null && resolvePackage != null) {
      final directPkg = resolvePackage(directMember!.packageId!);
      if (directPkg != null && directPkg.directReferralBonus > 0) {
        results.add(BonusTransaction(
          recipientMemberId: directReferrerId,
          amount: directPkg.directReferralBonus,
          reason: 'direct_referral',
        ));
      }
    }

    // Indirect referrer
    final indirectReferrerId = _referrerId(directReferrerId, resolveMember);
    if (indirectReferrerId != null) {
      final indirectMember = resolveMember(indirectReferrerId);
      if (indirectMember?.packageId != null && resolvePackage != null) {
        final indirectPkg = resolvePackage(indirectMember!.packageId!);
        if (indirectPkg != null && indirectPkg.indirectReferralBonus > 0) {
          results.add(BonusTransaction(
            recipientMemberId: indirectReferrerId,
            amount: indirectPkg.indirectReferralBonus,
            reason: 'indirect_referral',
          ));
        }
      }
    }

    // Chairman's bonus: paid per new registration based on the chosen package
    final chairmanBonus = _chairmanRegistrationBonus(chosenPackage.price);
    if (chairmanBonus > 0) {
      results.add(BonusTransaction(
        recipientMemberId: 0, // chairman — resolved by caller
        amount: chairmanBonus,
        reason: 'chairman_registration',
      ));
    }

    return results;
  }

  // ═════════════════════════════════════════════════════════════════════════
  // Package Upgrade Bonus
  // ═════════════════════════════════════════════════════════════════════════

  /// Compute bonuses when [memberId] upgrades to [upgradedPackage].
  ///
  /// Looks up the direct upline's current package; if that package has a
  /// non-zero [Package.upgradeReferralBonus], the upline receives that amount.
  List<BonusTransaction> computeUpgradeBonus({
    required int memberId,
    required Package upgradedPackage,
    required Member? Function(int memberId) resolveMember,
    required Package? Function(int packageId) resolvePackage,
  }) {
    final directReferrerId = _referrerId(memberId, resolveMember);
    if (directReferrerId == null) return [];

    final referrer = resolveMember(directReferrerId);
    if (referrer?.packageId == null) return [];

    final referrerPkg = resolvePackage(referrer!.packageId!);
    if (referrerPkg == null || referrerPkg.upgradeReferralBonus <= 0) {
      return [];
    }

    return [
      BonusTransaction(
        recipientMemberId: directReferrerId,
        amount: referrerPkg.upgradeReferralBonus,
        reason: 'upgrade_referral',
      ),
    ];
  }

  // ═════════════════════════════════════════════════════════════════════════
  // Helpers
  // ═════════════════════════════════════════════════════════════════════════

  /// Walk one level up the referral tree.
  static int? _referrerId(
    int memberId,
    Member? Function(int) resolve,
  ) {
    final m = resolve(memberId);
    return m?.referrerId;
  }

  /// Chairman's bonus for a new registration based on package price.
  static int _chairmanRegistrationBonus(int packagePrice) {
    if (packagePrice >= 3000) return 100;
    if (packagePrice >= 1500) return 50;
    return 0;
  }
}
