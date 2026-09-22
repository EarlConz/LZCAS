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
/// `false` for the 1.5.x line — those releases carry the GPS fix only. The
/// delivery code stays compiled (so it keeps building) but is unreachable,
/// and const-false branches are tree-shaken out of release AOT builds. Flip
/// to `true` for the delivery release; the matching database migrations
/// (v48 onward) must be applied first.
const bool enableDeliverySystem = false;
