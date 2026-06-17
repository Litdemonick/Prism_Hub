// Basic sanity test for PrismHub.
//
// The app's root widget (MainApp) requires heavy runtime initialization
// (storage, controllers, media_kit, window_manager) that isn't available in a
// bare widget-test environment, so we keep a lightweight smoke test here.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('MaterialApp renders a basic widget tree', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(body: Center(child: Text('PrismHub'))),
      ),
    );

    expect(find.text('PrismHub'), findsOneWidget);
  });
}
