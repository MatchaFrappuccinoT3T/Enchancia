// Smoke test placeholder.
//
// The real app boots through Hive + SharedPreferences in `main()`, which needs
// platform channel mocks to drive from a test. Until those are wired up this
// just verifies the test harness itself is healthy.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('test harness builds a MaterialApp shell', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: Scaffold()));
    expect(find.byType(Scaffold), findsOneWidget);
  });
}
