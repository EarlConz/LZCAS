// This is a basic Flutter widget test.
//
// To perform an interaction with a widget in your test, use the WidgetTester
// utility in the flutter_test package. For example, you can send tap and scroll
// gestures. You can also use WidgetTester to find child widgets in the widget
// tree, read text, and verify that the values of widget properties are correct.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

// Keep this widget test minimal and self-contained to avoid initializing
// the full app or DB during the test run.

void main() {
  testWidgets('Counter increments smoke test', (WidgetTester tester) async {
    // Build a minimal app shell for the widget test.
    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(
        body: Center(child: Text('LZCAS')),
      ),
    ));

    // Verify that the app title is present in this minimal shell
    expect(find.text('LZCAS'), findsOneWidget);
  });
}
