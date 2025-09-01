# LZCAS - Technical Overview

This document serves as the technical overview of the LZCAS Inventory project, intended for development and maintenance purposes.

## Project Structure

The project structure follows standard Flutter project structure. Notable locations are:

- **Theme**: `lib\theme.dart` -> This file contains the theme used in the project to keep the aesthetics streamlined. Keep this file in mind for all future use.
- **Reusable UI Components**: `lib\widgets\` -> Contains common and reusable UI widgets.
- **Dialogs**: `lib\dialogs\` -> Contains reusable dialog components for various interactions.

## Architectural Notes
- The application follows a standard Flutter App project structure.
- Reusable UI components are located in `./lib/widgets`.
- Dialog components are now centralized in `./lib/dialogs`.

## Implementation Standards
- DO NOT overengineer things. Start with the simplest implementation. Wait for the user to tell you to continue with improvements.
- Always follow the theme to keep a streamlined look to the project. Do not use hardcoded colors. If new colors are needed, adjust the `lib\theme.dart\` file as necessary.
- Ask for clarifications rather than guessing next steps if you are not clear about anything.
- All changes should be made carefully, and with thorough thought behind all changes.
- Any new modifications that fundamentally change how code is used should update this file. Refer to the examples below. This will help future changes refer to these new files.

### Chart Components
- **SalesChart**: The `MonthlySalesChart` and `WeeklySalesChart` have been combined into a single, reusable `SalesChart` widget (`lib/widgets/saleschart.dart`). This new component accepts data, titles, and styling parameters, reducing redundancy and promoting a unified charting approach.

### Button and Dialog Components
- **Standardized Buttons**: Introduced `CustomElevatedButton` (`lib/widgets/custom_elevated_button.dart`) and `CustomIconButton` (`lib/widgets/custom_icon_button.dart`) to ensure consistent styling across the application, adhering to the project's theme.
- **Extracted Dialogs**: Complex interactive dialogs have been extracted into dedicated, reusable dialog widgets within `lib/dialogs/`:
    - `AddMemberDialog` (`lib/dialogs/add_member_dialog.dart`) for adding new members.
    - `ConfirmationDialog` (`lib/dialogs/confirmation_dialog.dart`) for generic user confirmations.
    - `EditMemberDialog` (`lib/dialogs/edit_member_dialog.dart`) for editing existing member details.
    - `EditStockDialog` (`lib/dialogs/edit_stock_dialog.dart`) for modifying inventory stock quantities.
- **Refactored Button Logic**: The `AddMemberButton`, `DeleteMemberButton`, `EditMemberButton`, and `InventoryActionButton` have been updated to leverage the new `CustomElevatedButton`, `CustomIconButton`, and their respective extracted dialog components, significantly simplifying their internal logic and improving modularity.
