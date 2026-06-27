// A backend-free smoke test for the end-to-end-encryption preview. It boots
// the in-memory two-party demo and confirms the screen renders while the
// identities are being generated (no Supabase, no network).

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_chat_example/preview_e2ee.dart';

void main() {
  testWidgets('E2EE preview boots and shows a loading state', (tester) async {
    await tester.pumpWidget(const E2eePreviewApp());
    // Identities generate asynchronously; the first frame shows a spinner.
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
  });
}
