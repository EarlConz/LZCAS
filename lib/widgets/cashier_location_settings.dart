// lib/widgets/cashier_location_settings.dart
// Thin role-specific wrapper around the shared LocationSelectionWidget.
// Keeps the `CashierLocationSettings` API stable for the Cashier and Branch
// Cashier dashboards while all GPS / geocoding / address-search logic lives in
// lib/widgets/location_selection_widget.dart (shared with the Member role).

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../auth/auth.dart';
import '../db/db.dart';
import 'location_selection_widget.dart';
import 'map_kit.dart';

class CashierLocationSettings extends StatelessWidget {
  const CashierLocationSettings({super.key});

  @override
  Widget build(BuildContext context) {
    final auth = context.read<AuthState>();
    final uid = auth.userId;
    if (uid == null) return const SizedBox.shrink();

    return LocationSelectionWidget(
      // The pin previews in the colour members will see this account as.
      pinKind: auth.userRole == UserRole.branchCashier
          ? MapPinKind.branch
          : MapPinKind.cashier,
      title: 'Cashier Location',
      description:
          'Members use this location to find you in the Nearest Cashiers '
          'map. It is a static point — no live tracking.',
      actionLabel:
          'Do you want to use your current location as your Cashier Location?',
      savedToast: 'Cashier location saved',
      approximateToast:
          'Location saved (approximate, based on your IP address)',
      removeDialogTitle: 'Remove saved location?',
      removeDialogBody:
          'You will stop appearing in the members’ Nearest Cashiers map '
          'until you set a location again.',
      onLoad: () async {
        final loc = await repository.fetchCashierLocation(uid);
        if (loc == null) return null;
        return SavedLocation(
          latitude: loc.latitude,
          longitude: loc.longitude,
          address: loc.address,
          updatedAt: loc.locationUpdatedAt,
        );
      },
      onSave: (lat, lng, address) => repository.updateCashierLocation(
        userId: uid,
        latitude: lat,
        longitude: lng,
        address: address,
      ),
      onClear: () => repository.clearCashierLocation(userId: uid),
    );
  }
}
