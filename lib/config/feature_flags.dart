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
/// `false` on `main` and the whole 1.5.x line — those releases carry the GPS
/// fix only, and const-false branches are tree-shaken out of release AOT
/// builds.
///
/// `true` on the `delivery-account` branch, for testing against staging,
/// which has v48–v52 applied. That makes this branch UNSAFE TO BUILD FOR
/// PRODUCTION until the delivery release: production has none of v48–v50 or
/// v52, so every delivery screen would fail against it. Build staging from
/// here (`--flavor staging` plus the staging dart-defines), and production
/// from `main` only.
const bool enableDeliverySystem = true;
