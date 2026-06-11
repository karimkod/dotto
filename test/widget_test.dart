// Basic smoke test for the Dotto main menu.

import 'package:flutter_test/flutter_test.dart';

import 'package:dotto/main.dart';

void main() {
  testWidgets('Dotto menu renders title and play button', (tester) async {
    await tester.pumpWidget(const DottoApp());
    await tester.pump();

    // Wordmark.
    expect(find.text('Dotto'), findsOneWidget);
    // Current level (level 2 is the first unlocked) play button.
    expect(find.text('Level 2'), findsOneWidget);
    // Difficulty badge for level 2 (Easy).
    expect(find.text('Easy'), findsOneWidget);
  });
}
