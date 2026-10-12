// lib/config/feature_flags.dart
// Compile-time feature flags.
//
// `enableMemberLocationSetup` gates the Member Location settings section that
// was built ahead of a major release. While `false` the section is fully
// compiled but never rendered: the `if (enableMemberLocationSetup)` branch is
// const-false, so release AOT builds tree-shake it away entirely. Flip this
// to `true` to surface the setting to Members.
const bool enableMemberLocationSetup = true;

/// Gates the online-shopping-and-delivery system as a whole: the member's
/// Marketplace and Active Orders tabs, the cashier/admin Delivery Orders
/// module, the order notification chimes, and the rider-related parts of
/// the admin Cashier Locations map.
///
/// On for every build since v1.6.0 (2026-10-13). Until then it was on for
/// staging builds only (`String.fromEnvironment('APP_FLAVOR') == 'staging'`),
/// because production lacked the delivery migrations. Production got v48–v74
/// on 2026-10-12 (supabase/DELIVERY_ROLLOUT.md), so production builds now
/// include delivery too.
///
/// Kept as a flag rather than deleted: turning it back to `false` hides
/// every delivery screen again (a compile-time constant, tree-shaken out),
/// should a release ever need to ship without delivery.
const bool enableDeliverySystem = true;
