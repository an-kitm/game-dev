import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sequence/features/auth/nickname_provider.dart';
import 'package:sequence/features/auth/nickname_screen.dart';

void main() {
  testWidgets('NicknameScreen renders title and continue button',
      (WidgetTester tester) async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final prefs = await SharedPreferences.getInstance();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [sharedPrefsProvider.overrideWithValue(prefs)],
        child: const MaterialApp(home: NicknameScreen()),
      ),
    );

    expect(find.text('SEQUENCE'), findsOneWidget);
    expect(find.text('Continue'), findsOneWidget);
    expect(find.byType(TextField), findsOneWidget);
  });
}
