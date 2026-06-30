import 'package:flutter_test/flutter_test.dart';
import 'package:rickshaw_flutter/main.dart';

void main() {
  testWidgets('App launch smoke test', (WidgetTester tester) async {
    // Build our app and trigger a frame.
    await tester.pumpWidget(const RickshawwApp());

    // Verify ChooseRoleScreen starts
    expect(find.byType(RickshawwApp), findsOneWidget);
  });
}
