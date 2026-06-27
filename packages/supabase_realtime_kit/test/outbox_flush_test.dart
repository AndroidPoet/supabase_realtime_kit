import 'package:supabase/supabase.dart';
import 'package:supabase_realtime_kit/supabase_realtime_kit.dart';
import 'package:test/test.dart';

void main() {
  group('RealtimeKit.deliverOutboxEntry', () {
    late InMemoryOutbox outbox;

    setUp(() => outbox = InMemoryOutbox());

    OutboxEntry sample({int attempts = 0}) => OutboxEntry(
      id: 'c1',
      table: 'messages',
      payload: const {'content': 'hi'},
      attempts: attempts,
    );

    test('removes the entry on successful delivery', () async {
      await outbox.add(sample());
      await RealtimeKit.deliverOutboxEntry(sample(), outbox, (_) async {});
      expect(await outbox.pending(), isEmpty);
    });

    test('removes the entry on duplicate-key (already delivered)', () async {
      await outbox.add(sample());
      await RealtimeKit.deliverOutboxEntry(
        sample(),
        outbox,
        (_) async =>
            throw const PostgrestException(message: 'dup', code: '23505'),
      );
      expect(await outbox.pending(), isEmpty);
    });

    test('increments attempts on a transient failure', () async {
      await outbox.add(sample());
      await RealtimeKit.deliverOutboxEntry(
        sample(),
        outbox,
        (_) async =>
            throw const PostgrestException(message: 'boom', code: '500'),
        maxAttempts: 5,
      );
      final pending = await outbox.pending();
      expect(pending.single.attempts, 1);
    });

    test('drops a poison entry once attempts reach the cap', () async {
      final poisoned = sample(attempts: 4); // 4 + 1 == cap (5)
      await outbox.add(poisoned);
      await RealtimeKit.deliverOutboxEntry(
        poisoned,
        outbox,
        (_) async => throw StateError('permanent'),
        maxAttempts: 5,
      );
      expect(await outbox.pending(), isEmpty);
    });

    test(
      'non-Postgrest errors also increment (then eventually drop)',
      () async {
        await outbox.add(sample());
        await RealtimeKit.deliverOutboxEntry(
          sample(),
          outbox,
          (_) async => throw Exception('io'),
          maxAttempts: 5,
        );
        expect((await outbox.pending()).single.attempts, 1);
      },
    );
  });
}
