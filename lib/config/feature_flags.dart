// lib/config/feature_flags.dart
// Compile-time feature flags.
//
// `enableMemberLocationSetup` gates the Member Location settings section that
// was built ahead of a major release. While `false` the section is fully
// compiled but never rendered: the `if (enableMemberLocationSetup)` branch is
// const-false, so release AOT builds tree-shake it away entirely. Flip this
// to `true` to surface the setting to Members.
const bool enableMemberLocationSetup = true;
