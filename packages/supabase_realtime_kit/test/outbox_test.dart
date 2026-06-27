import 'package:supabase_realtime_kit/supabase_realtime_kit.dart';
import 'package:test/test.dart';

void main() {
  group('InMemoryOutbox', () {
    test('adds, lists, updates, and removes entries', () async {
      final outbox = InMemoryOutbox();
      const entry = OutboxEntry(
        id: 'c1',
        table: 'messages',
        payload: {'content': 'hi'},
      );

      await outbox.add(entry);
      expect((await outbox.pending()).single.id, 'c1');

      await outbox.update(entry.incrementAttempts());
      expect((await outbox.pending()).single.attempts, 1);

      await outbox.remove('c1');
      expect(await outbox.pending(), isEmpty);
    });

    test('add replaces an entry with the same id', () async {
      final outbox = InMemoryOutbox();
      await outbox.add(
        const OutboxEntry(id: 'c1', table: 't', payload: {'v': 1}),
      );
      await outbox.add(
        const OutboxEntry(id: 'c1', table: 't', payload: {'v': 2}),
      );
      final pending = await outbox.pending();
      expect(pending, hasLength(1));
      expect(pending.single.payload['v'], 2);
    });
  });

  group('OutboxEntry', () {
    test('round-trips through JSON', () {
      const entry = OutboxEntry(
        id: 'c1',
        table: 'messages',
        payload: {'content': 'hi'},
        schema: 'chat',
        attempts: 2,
      );
      final restored = OutboxEntry.fromJson(entry.toJson());
      expect(restored.id, entry.id);
      expect(restored.table, entry.table);
      expect(restored.schema, 'chat');
      expect(restored.payload, entry.payload);
      expect(restored.attempts, 2);

      // incrementAttempts preserves schema.
      expect(entry.incrementAttempts().schema, 'chat');
    });
  });
}
