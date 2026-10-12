// The Sell window on a small phone (lib/buttons/sellbutton.dart): each of
// its views, with long product names, in light and dark. A layout
// overflow fails the test. Also checks the taps: adding, the stock limit,
// the quantity buttons and the price that Sell waits for.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';

import 'package:lzcas/buttons/sellbutton.dart';
import 'package:lzcas/theme.dart';

const _long = 'GUTVita Probiotic Plus Fiber Blend, 30 sachets (family pack)';
const _items = ['Detox Tea', _long, 'Sold Out Item', 'Vitamin C'];
const _stock = {'Detox Tea': 24, _long: 2, 'Sold Out Item': 0, 'Vitamin C': 7};

Future<void> _pump(WidgetTester tester, {ThemeData? theme, Size size = const Size(360, 740)}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      theme: theme ?? stockpileTheme,
      home: Builder(
        builder: (context) => sellDialogForTest(items: _items, itemStock: _stock),
      ),
    ),
  );
  await tester.pump();
}

void main() {
  setUpAll(() => GoogleFonts.config.allowRuntimeFetching = false);

  testWidgets('phone: empty cart, adding, quantities, price, Sell', (tester) async {
    await _pump(tester);
    expect(find.text('Sell items'), findsOneWidget);
    expect(find.text('The cart is empty.\nSearch above to add a product.'), findsOneWidget);

    // Into the products: every product listed, the sold-out one marked.
    await tester.tap(find.byType(TextField).first);
    await tester.pumpAndSettle();
    expect(find.text('Add products'), findsOneWidget);
    expect(find.text('Out of stock'), findsOneWidget);

    // Two taps on the long one (stock 2), then a third: refused.
    await tester.tap(find.text(_long));
    await tester.pump();
    await tester.tap(find.text(_long));
    await tester.pump();
    expect(find.text('×2'), findsOneWidget);
    expect(find.text('All 2 in the cart'), findsOneWidget);
    await tester.tap(find.text(_long));
    await tester.pump();
    expect(find.textContaining('Only 2 of'), findsOneWidget);

    // Typing narrows the list.
    await tester.enterText(find.byType(TextField).first, 'vita');
    await tester.pump();
    expect(find.text('Detox Tea'), findsNothing);
    await tester.tap(find.text('Vitamin C'));
    await tester.pump();
    expect(find.text('3 items in the cart'), findsOneWidget);

    // Back to the cart: two lines, prices missing, Sell waits.
    await tester.tap(find.text('Done'));
    await tester.pumpAndSettle();
    expect(find.text('2 products'), findsOneWidget);
    expect(find.text('Enter a price for every item (2 missing)'), findsOneWidget);
    final sell = find.widgetWithText(FilledButton, 'Sell 3 items');
    expect(tester.widget<FilledButton>(sell).onPressed, isNull);

    // + stops at the stock; − at 1 takes the line out.
    expect(find.text('That is all the stock'), findsNothing); // price note comes first
    await tester.ensureVisible(find.byTooltip('One more').last);
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('One more').last);
    await tester.pump();
    expect(find.text('Sell 4 items'), findsOneWidget);
    await tester.tap(find.byTooltip('One less').last);
    await tester.pump();
    await tester.tap(find.byTooltip('Take it out').last);
    await tester.pump();
    await tester.pump(); // the removed line's price field is let go after the frame
    expect(find.text('1 product'), findsOneWidget);

    // Prices in: the total and Sell come alive.
    await tester.enterText(find.widgetWithText(TextField, '0'), '350');
    await tester.pump();
    expect(find.text('₱700'), findsWidgets);
    expect(tester.widget<FilledButton>(find.widgetWithText(FilledButton, 'Sell 2 items')).onPressed, isNotNull);
  });

  testWidgets('phone: the buyer view, light and dark', (tester) async {
    for (final theme in [stockpileTheme, stockpileDarkTheme]) {
      await _pump(tester, theme: theme);
      await tester.tap(find.text('Walk-in (no member)'));
      await tester.pumpAndSettle();
      expect(find.text('Choose the buyer'), findsOneWidget);
      expect(find.text('MEMBERS · NAME, NUMBER OR ID'), findsOneWidget);
      // Walk-in returns to the cart.
      await tester.tap(find.text('Walk-in (no member)'));
      await tester.pumpAndSettle();
      expect(find.text('Sell items'), findsOneWidget);
    }
  });

  testWidgets('PC: the dialog, with one product search', (tester) async {
    await _pump(tester, size: const Size(1280, 800));
    expect(find.text('Sell Items'), findsOneWidget);
    expect(find.text('Search Item'), findsNothing); // the old second box (Part 7, PS1)
    expect(find.text('Item'), findsOneWidget);
  });
}
