import 'package:supabase_realtime_kit/supabase_realtime_kit.dart';
import 'package:test/test.dart';

/// Minimal test row: [id] is the server identity, [key] the optimistic
/// reconciliation key (client_id), [order] drives sorting.
class _Row {
  const _Row(this.id, {this.key, this.order = 0});
  final String id;
  final String? key;
  final int order;
}

LiveListState<_Row> _state({bool withPendingKey = true, bool sorted = true}) {
  return LiveListState<_Row>(
    idOf: (r) => r.id,
    pendingKeyOf: withPendingKey ? (r) => r.key : null,
    compare: sorted ? (a, b) => a.order.compareTo(b.order) : null,
  );
}

void main() {
  group('LiveListState', () {
    test('starts empty', () {
      final state = _state();
      expect(state.items, isEmpty);
      expect(state.confirmedCount, 0);
      expect(state.pendingCount, 0);
    });

    test('upsertConfirmed adds and updates by id', () {
      final state = _state()
        ..upsertConfirmed(const _Row('a', order: 1))
        ..upsertConfirmed(const _Row('b', order: 2));
      expect(state.items.map((r) => r.id), ['a', 'b']);

      // Same id replaces, not duplicates.
      state.upsertConfirmed(const _Row('a', order: 3));
      expect(state.confirmedCount, 2);
      expect(state.items.last.id, 'a'); // re-sorted: a now order 3
    });

    test('orders by comparator', () {
      final state = _state()
        ..addAllConfirmed([
          const _Row('a', order: 3),
          const _Row('b', order: 1),
          const _Row('c', order: 2),
        ]);
      expect(state.items.map((r) => r.id), ['b', 'c', 'a']);
    });

    test('preserves insertion order when no comparator', () {
      final state = _state(sorted: false)
        ..addAllConfirmed([const _Row('a'), const _Row('b')]);
      expect(state.items.map((r) => r.id), ['a', 'b']);
    });

    test('removeConfirmedById removes and reports', () {
      final state = _state()..upsertConfirmed(const _Row('a'));
      expect(state.removeConfirmedById('a'), isTrue);
      expect(state.removeConfirmedById('a'), isFalse);
      expect(state.items, isEmpty);
    });

    test('clearConfirmed keeps optimistic rows', () {
      final state = _state()
        ..upsertConfirmed(const _Row('a', order: 1))
        ..addPending(const _Row('tmp:x', key: 'x', order: 2))
        ..clearConfirmed();
      expect(state.confirmedCount, 0);
      expect(state.pendingCount, 1);
      expect(state.items.single.id, 'tmp:x');
    });

    test('addPending overlays an optimistic row and returns its key', () {
      final state = _state();
      final key = state.addPending(const _Row('tmp:x', key: 'x'));
      expect(key, 'x');
      expect(state.items.single.id, 'tmp:x');
      expect(state.pendingCount, 1);
    });

    test('server echo reconciles the optimistic row (no duplicate)', () {
      final state = _state()
        ..addPending(const _Row('tmp:x', key: 'x', order: 1));
      expect(state.items.single.id, 'tmp:x');

      // The persisted row arrives with the real id but the SAME pending key.
      state.upsertConfirmed(const _Row('server-1', key: 'x', order: 1));

      expect(state.items, hasLength(1));
      expect(state.items.single.id, 'server-1');
      expect(state.pendingCount, 0);
    });

    test('unconfirmed optimistic rows coexist with confirmed rows', () {
      final state = _state()
        ..upsertConfirmed(const _Row('server-1', key: 'a', order: 1))
        ..addPending(const _Row('tmp:b', key: 'b', order: 2));
      expect(state.items.map((r) => r.id), ['server-1', 'tmp:b']);
    });

    test('removePending drops the optimistic row', () {
      final state = _state()..addPending(const _Row('tmp:x', key: 'x'));
      expect(state.removePending('x'), isTrue);
      expect(state.removePending('x'), isFalse);
      expect(state.items, isEmpty);
    });

    test('addPending is a no-op without a pendingKeyOf', () {
      final state = _state(withPendingKey: false);
      expect(state.addPending(const _Row('tmp:x', key: 'x')), isNull);
      expect(state.pendingCount, 0);
      expect(state.items, isEmpty);
    });
  });
}
