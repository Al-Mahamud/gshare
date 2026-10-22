import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gshare/ui/name_setup_screen.dart';

void main() {
  testWidgets('Continue is disabled until a name is typed', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: NameSetupScreen()));

    FilledButton button() => tester.widget<FilledButton>(find.widgetWithText(FilledButton, 'Continue'));
    expect(button().onPressed, isNull);

    await tester.enterText(find.byType(TextField), '   ');
    await tester.pump();
    expect(button().onPressed, isNull);

    await tester.enterText(find.byType(TextField), 'Rahim');
    await tester.pump();
    expect(button().onPressed, isNotNull);
  });
}
