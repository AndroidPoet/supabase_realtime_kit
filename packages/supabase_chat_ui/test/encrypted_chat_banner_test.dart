import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_chat_ui/supabase_chat_ui.dart';

void main() {
  Widget host(Widget child) => MaterialApp(home: Scaffold(body: child));

  testWidgets('unverified banner shows the safety number and Verify button', (
    tester,
  ) async {
    var tapped = false;
    await tester.pumpWidget(
      host(
        EncryptedChatBanner(
          verified: false,
          safetyNumber: '12345 67890 11111',
          peerLabel: 'Bob',
          onVerify: () => tapped = true,
        ),
      ),
    );

    expect(find.text('Verify Bob'), findsOneWidget);
    expect(find.text('12345 67890 11111'), findsOneWidget);
    expect(find.text('Verify'), findsOneWidget);

    await tester.tap(find.text('Verify'));
    expect(tapped, isTrue);
  });

  testWidgets('verified banner collapses to a verified indicator', (
    tester,
  ) async {
    await tester.pumpWidget(
      host(
        EncryptedChatBanner(
          verified: true,
          safetyNumber: '12345 67890 11111',
          peerLabel: 'Bob',
          onVerify: () {},
        ),
      ),
    );

    expect(find.text('End-to-end encrypted · verified'), findsOneWidget);
    expect(find.text('Verify'), findsNothing);
    expect(find.text('12345 67890 11111'), findsNothing);
  });
}
