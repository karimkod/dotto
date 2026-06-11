// Basic smoke test for the Dotto app.

import 'package:flutter_test/flutter_test.dart';

import 'package:dotto/main.dart';

void main() {
  testWidgets('Dotto home screen renders', (WidgetTester tester) async {
    await tester.pumpWidget(const DottoApp());

    expect(find.text('Dotto'), findsOneWidget);
    expect(find.text('Puzzle game'), findsOneWidget);
  });
}
