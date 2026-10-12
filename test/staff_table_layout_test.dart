// The shared staff table (lib/widgets/staff_table.dart) at its tightest:
// the narrowest wide screen that still gets the table, and a small phone,
// with long names and the widest pills. A layout overflow fails the test.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';

import 'package:lzcas/widgets/staff_table.dart';

const _long = 'Villanueva-Dela Cruz, Maria Carmencita Josefina';

Widget _host(Size size, Widget child, {Brightness brightness = Brightness.light}) => MediaQuery(
  data: MediaQueryData(size: size),
  child: MaterialApp(
    theme: ThemeData(brightness: brightness),
    home: Scaffold(
      body: Padding(padding: const EdgeInsets.all(16), child: child),
    ),
  ),
);

Future<void> _pumpAt(WidgetTester tester, Size size, Widget child, {Brightness brightness = Brightness.light}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(_host(size, child, brightness: brightness));
  await tester.pump();
}

/// Transactions' columns, with its widest content.
Widget _transactionsTable() => Column(
  children: [
    StaffTableTop(
      caption: 'This month · 1,284 sales · ₱1,218,450',
      searchWidth: 320,
      search: StaffSearchField(hint: 'Buyer or product', onChanged: (_) {}),
      actions: [
        StaffButton(label: 'Export', icon: Icons.file_download_outlined, primary: false, onPressed: () {}),
        StaffButton(label: 'Sell', icon: Icons.point_of_sale_outlined, onPressed: () {}),
      ],
    ),
    const SizedBox(height: 14),
    StaffChipBar(
      hint: 'Click a row for the receipt',
      chips: [
        StaffChip(label: 'All', count: 1284, selected: true, onTap: () {}),
        StaffChip(label: 'Counter', count: 1029, selected: false, onTap: () {}),
        StaffChip(label: 'Delivery', count: 206, selected: false, onTap: () {}),
        StaffChip(label: 'Branch', count: 49, selected: false, onTap: () {}),
        StaffSelectChip<int>(label: '', icon: Icons.calendar_today_outlined, value: 1, options: const [(1, 'This month')], onChanged: (_) {}),
      ],
    ),
    const SizedBox(height: 14),
    Expanded(
      child: StaffTable(
        itemCount: 8,
        loadingMore: true,
        footer: staffShowing(8, 1284),
        onRowTap: (_) {},
        columns: const [
          StaffColumn('When', width: 110),
          StaffColumn('Buyer', flex: 15),
          StaffColumn('Items', flex: 22),
          StaffColumn('Sold by', flex: 10),
          StaffColumn('Paid', flex: 12),
          StaffColumn('Total', width: 110, alignEnd: true),
          StaffColumn('', width: 48),
        ],
        cells: (context, i) => [
          const Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [Text('10:42 AM'), Text('30 Sep')],
          ),
          const Text(_long, maxLines: 1, overflow: TextOverflow.ellipsis),
          const Row(
            children: [
              SizedBox(width: 84, height: 36),
              SizedBox(width: 10),
              Expanded(child: Text('Collagen Drink ×12, Vita Coffee ×6, Moringa Capsules ×2', maxLines: 1, overflow: TextOverflow.ellipsis)),
            ],
          ),
          const Text('cashier_mandaue_branch', maxLines: 1, overflow: TextOverflow.ellipsis),
          const Align(alignment: Alignment.centerLeft, child: StaffPill('Delivery · at counter', tone: StaffTone.blue)),
          const Text('₱1,218,450'),
          StaffMoreButton(items: [StaffMenuItem('Delete', Icons.delete_outline, () {}, danger: true)]),
        ],
      ),
    ),
  ],
);

Widget _phoneRows() => ListView(
  children: [
    StaffPhoneTop(
      caption: 'This month · 1,284 sales · ₱1,218,450',
      captionTrailing: StaffSelectChip<int>(label: '', icon: Icons.calendar_today_outlined, value: 1, options: const [(1, 'This month')], onChanged: (_) {}),
      search: StaffSearchField(hint: 'Buyer or product', height: 48, onChanged: (_) {}),
      chips: [
        StaffChip(label: 'All', count: 1284, selected: true, onTap: () {}),
        StaffChip(label: 'Counter', count: 1029, selected: false, onTap: () {}),
        StaffChip(label: 'Delivery', count: 206, selected: false, onTap: () {}),
        StaffChip(label: 'Branch', count: 49, selected: false, onTap: () {}),
      ],
    ),
    const StaffGroupLabel('Wed 30 Sep · 137 sales', trailing: '₱1,218,450'),
    StaffPhoneCard(
      rows: [
        for (var i = 0; i < 3; i++)
          StaffPhoneRow(
            leading: const SizedBox(width: 56, height: 36),
            title: _long,
            lines: const ['Collagen Drink ×12, Vita Coffee ×6, Moringa Capsules ×2', '10:42 AM · cashier_mandaue_branch'],
            trailing: const StaffPhoneValue('₱121,450', pill: StaffPill('Delivery · at counter', tone: StaffTone.blue, small: true)),
            menu: [StaffMenuItem('Delete', Icons.delete_outline, () {}, danger: true)],
            onTap: () {},
          ),
      ],
    ),
  ],
);

void main() {
  setUpAll(() => GoogleFonts.config.allowRuntimeFetching = false);

  testWidgets('the table fits the narrowest wide screen', (tester) async {
    // 900 of content: the breakpoint, plus the page's own padding.
    await _pumpAt(tester, const Size(932, 700), _transactionsTable());
    expect(tester.takeException(), isNull);
    expect(find.text('WHEN'), findsOneWidget);
    expect(find.text('Showing 8 of 1,284 · more load as you scroll'), findsOneWidget);
  });

  testWidgets('the table fits in dark mode too', (tester) async {
    await _pumpAt(tester, const Size(1366, 768), _transactionsTable(), brightness: Brightness.dark);
    expect(tester.takeException(), isNull);
  });

  testWidgets('phone rows fit a 360 px phone', (tester) async {
    await _pumpAt(tester, const Size(360, 780), _phoneRows());
    expect(tester.takeException(), isNull);
  });

  test('staffShowing and staffWhen read as designed', () {
    expect(staffShowing(25, 1284), 'Showing 25 of 1,284 · more load as you scroll');
    expect(staffShowing(48, 48), 'Showing all 48');
    expect(staffShowing(0, 0), '');
    final now = DateTime.now();
    expect(staffWhen(now.subtract(const Duration(minutes: 12))), '12 min ago');
    expect(staffWhen(now.subtract(const Duration(days: 3))), '3 days ago');
  });
}
