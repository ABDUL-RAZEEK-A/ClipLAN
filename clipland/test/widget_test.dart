import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:cliplan/widgets/hashing_dialog.dart';

void main() {
  testWidgets(
    'HashingConfirmationDialog displays hashing options and information',
    (WidgetTester tester) async {
      bool? result;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) {
                return ElevatedButton(
                  onPressed: () async {
                    result = await showDialog<bool>(
                      context: context,
                      builder: (_) => const HashingConfirmationDialog(),
                    );
                  },
                  child: const Text('Open Dialog'),
                );
              },
            ),
          ),
        ),
      );

      // Tap button to open dialog
      await tester.tap(find.text('Open Dialog'));
      await tester.pumpAndSettle();

      // Verify dialog elements are displayed
      expect(find.text('File Hashing Verification'), findsOneWidget);
      expect(
        find.text('Do you want to enable file hashing before sending?'),
        findsOneWidget,
      );
      expect(find.text('Use Hashing'), findsOneWidget);
      expect(find.text('Accept Risk & Send Without Hashing'), findsOneWidget);
      expect(find.text('Cancel'), findsOneWidget);

      // Tap "Use Hashing" button
      await tester.tap(find.text('Use Hashing'));
      await tester.pumpAndSettle();

      expect(result, isTrue);
    },
  );

  testWidgets('HashingConfirmationDialog returns false on Accept Risk', (
    WidgetTester tester,
  ) async {
    bool? result;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) {
              return ElevatedButton(
                onPressed: () async {
                  result = await showDialog<bool>(
                    context: context,
                    builder: (_) => const HashingConfirmationDialog(),
                  );
                },
                child: const Text('Open Dialog'),
              );
            },
          ),
        ),
      ),
    );

    await tester.tap(find.text('Open Dialog'));
    await tester.pumpAndSettle();

    await tester.ensureVisible(find.text('Accept Risk & Send Without Hashing'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Accept Risk & Send Without Hashing'));
    await tester.pumpAndSettle();

    expect(result, isFalse);
  });
}
