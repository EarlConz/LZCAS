# lzcas

A new Flutter project.

## Getting Started

This project is a starting point for a Flutter application.

A few resources to get you started if this is your first Flutter project:

- [Lab: Write your first Flutter app](https://docs.flutter.dev/get-started/codelab)
- [Cookbook: Useful Flutter samples](https://docs.flutter.dev/cookbook)

For help getting started with Flutter development, view the
[online documentation](https://docs.flutter.dev/), which offers tutorials,
samples, guidance on mobile development, and a full API reference.

## Recent changes

- Show member transaction history on the member details card for the buyer themselves
	(previously the card showed transactions of members they referred). This makes
	the displayed history reflect the member's own purchases.
- Sales CSV export/import now include a `buyerId` column so sales remain tied to
	the buyer when exported and re-imported. If you have existing exports, update
	import scripts to include the `buyerId` column (numeric id or empty).
