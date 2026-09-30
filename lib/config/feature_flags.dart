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
/// On for STAGING builds only, until the delivery release. Staging has the
/// delivery migrations (v48–v56); production does not, so a production
/// build with this on would show screens that fail against it. Tying it to
/// the build flavor rather than the branch means every branch — `main`
/// included — is safe to build for production, and every staging build
/// (which always passes `--dart-define=APP_FLAVOR=staging`) gets delivery.
///
/// Still a compile-time constant: production builds tree-shake the delivery
/// screens out entirely. Exact match, no trimming — `AppFlavor.current`
/// normalises, but that is not const, and the member sidebar needs this to
/// be. The staging build commands pass exactly `staging`.
///
/// On release day, once production has the migrations: set this to `true`.
const bool enableDeliverySystem =
    String.fromEnvironment('APP_FLAVOR') == 'staging';
