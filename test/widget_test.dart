// This is a basic Flutter widget test for Plexus.

import 'package:flutter_test/flutter_test.dart';
import 'package:plexus/app.dart';

void main() {
  testWidgets('Plexus app smoke test', (WidgetTester tester) async {
    // Build our app and trigger a frame.
    await tester.pumpWidget(const PlexusApp());

    // Verify that Plexus app launches.
    expect(find.byType(PlexusApp), findsOneWidget);
  });
}
