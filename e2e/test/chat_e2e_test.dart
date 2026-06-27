@Timeout(Duration(seconds: 60))
library;

import 'dart:async';
import 'dart:io';

import 'package:supabase/supabase.dart';
import 'package:supabase_chat/supabase_chat.dart';
import 'package:test/test.dart';

/// Real-instance end-to-end tests.
///
/// These talk to a LIVE Supabase project, so they only run when credentials are
/// present in the environment; otherwise the whole group is skipped.
///
/// Prerequisites:
///   * Apply `supabase/migrations/0001_chat_schema.sql` to the project.
///   * Enable anonymous sign-ins in Auth settings.
///
/// Run:
///   export SUPABASE_URL=https://YOUR.supabase.co
///   export SUPABASE_ANON_KEY=YOUR_ANON_KEY
///   dart test
void main() {
  final url = Platform.environment['SUPABASE_URL'];
  final anonKey = Platform.environment['SUPABASE_ANON_KEY'];
  final skip = (url == null || anonKey == null)
      ? 'Set SUPABASE_URL and SUPABASE_ANON_KEY to run e2e tests'
      : false;

  group('chat e2e (two live clients)', () {
    late SupabaseClient clientA;
    late SupabaseClient clientB;
    late SupabaseChat chatA;
    late SupabaseChat chatB;
    late ChatRoom roomA;
    late ChatRoom roomB;
    late String roomId;

    setUpAll(() async {
      clientA = SupabaseClient(url!, anonKey!);
      clientB = SupabaseClient(url, anonKey);
      await clientA.auth.signInAnonymously();
      await clientB.auth.signInAnonymously();

      chatA = SupabaseChat(clientA);
      chatB = SupabaseChat(clientB);

      // A creates a fresh room and invites B.
      final created = await chatA.createRoom(
        name: 'e2e-${DateTime.now().microsecondsSinceEpoch}',
        memberIds: [chatB.currentUserId!],
      );
      roomId = created.valueOrNull!.id;

      roomA = chatA.room(roomId);
      roomB = chatB.room(roomId);
      await roomA.join();
      await roomB.join();
      // Give the realtime sockets a moment to finish subscribing.
      await Future<void>.delayed(const Duration(seconds: 2));
    });

    tearDownAll(() async {
      await roomA.leave();
      await roomB.leave();
      // Best-effort cleanup so test rooms/messages don't accumulate (cascades).
      try {
        await clientA.from('rooms').delete().eq('id', roomId);
      } on Object catch (_) {
        // ignore cleanup failures
      }
      await clientA.auth.signOut();
      await clientB.auth.signOut();
      await clientA.dispose();
      await clientB.dispose();
    });

    test('A optimistic send appears instantly then reconciles', () async {
      final sent = await roomA.send(text: 'hello from A');
      expect(sent.isOk, isTrue, reason: 'persist should succeed');

      // A's own list should converge to exactly one row, not pending, no dup.
      final settled = await roomA.messages
          .firstWhere(
            (msgs) =>
                msgs.any((m) => m.content == 'hello from A' && !m.pending),
          )
          .timeout(const Duration(seconds: 15));
      final matches = settled
          .where((m) => m.content == 'hello from A')
          .toList();
      expect(matches, hasLength(1), reason: 'no optimistic duplicate');
    });

    test("B receives A's message over realtime", () async {
      final text = 'realtime-${DateTime.now().microsecondsSinceEpoch}';
      await roomA.send(text: text);

      final received = await roomB.messages
          .firstWhere((msgs) => msgs.any((m) => m.content == text))
          .timeout(const Duration(seconds: 15));
      expect(received.map((m) => m.content), contains(text));
    });

    test('B sees A typing over broadcast', () async {
      final future = roomB.typingUserIds
          .firstWhere((ids) => ids.contains(chatA.currentUserId))
          .timeout(const Duration(seconds: 15));
      // Broadcast has no replay; resend until B observes it (or the test times
      // out) so a not-yet-subscribed channel can't drop the single event.
      final ticker = Timer.periodic(
        const Duration(milliseconds: 500),
        (_) => roomA.setTyping(typing: true),
      );
      try {
        final typing = await future;
        expect(typing, contains(chatA.currentUserId));
      } finally {
        ticker.cancel();
      }
    });

    test('presence reports both members in the room', () async {
      final present = await roomB.presentUsers
          .firstWhere((users) => users.length >= 2)
          .timeout(const Duration(seconds: 15));
      final ids = present.map((p) => p['user_id']).toSet();
      expect(ids, contains(chatA.currentUserId));
      expect(ids, contains(chatB.currentUserId));
    });
  }, skip: skip);
}
