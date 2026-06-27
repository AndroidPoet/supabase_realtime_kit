import 'package:supabase_realtime_kit/src/types.dart';

/// The pure, IO-free merge engine behind `LiveQuery`.
///
/// It holds two layers — confirmed (server) rows keyed by identity, and
/// unconfirmed optimistic rows keyed by their pending key — and produces a
/// single merged, optionally-sorted snapshot. Keeping this free of any
/// Supabase/stream dependency makes the reconciliation logic exhaustively
/// unit-testable.
class LiveListState<T> {
  /// Creates a merge engine.
  LiveListState({required this.idOf, this.pendingKeyOf, this.compare});

  /// Extracts the server identity of an item.
  final IdSelector<T> idOf;

  /// Extracts the optimistic-reconciliation key of an item, if any.
  final PendingKeySelector<T>? pendingKeyOf;

  /// Optional ordering for the merged snapshot.
  final Comparator<T>? compare;

  final Map<Object, T> _confirmed = <Object, T>{};
  final Map<Object, T> _pending = <Object, T>{};

  /// Upserts a confirmed (server) row. If it shares a pending key with an
  /// optimistic row, that placeholder is reconciled away.
  void upsertConfirmed(T item) {
    _confirmed[idOf(item)] = item;
    final key = pendingKeyOf?.call(item);
    if (key != null) _pending.remove(key);
  }

  /// Upserts many confirmed rows.
  void addAllConfirmed(Iterable<T> items) => items.forEach(upsertConfirmed);

  /// Removes a confirmed row by its primary-key value.
  bool removeConfirmedById(Object id) => _confirmed.remove(id) != null;

  /// Clears all confirmed rows (e.g. before a full reload). Optimistic rows are
  /// left intact.
  void clearConfirmed() => _confirmed.clear();

  /// Adds an optimistic row. Returns its pending key, or `null` if the item has
  /// none (in which case it is not tracked).
  Object? addPending(T item) {
    final key = pendingKeyOf?.call(item);
    if (key == null) return null;
    _pending[key] = item;
    return key;
  }

  /// Removes an optimistic row by its pending key.
  bool removePending(Object pendingKey) => _pending.remove(pendingKey) != null;

  /// Number of confirmed rows currently held.
  int get confirmedCount => _confirmed.length;

  /// Number of unconfirmed optimistic rows currently held.
  int get pendingCount => _pending.length;

  /// The merged snapshot: confirmed rows plus optimistic rows the server has
  /// not yet echoed, ordered by [compare] when provided.
  List<T> get items {
    final byId = <Object, T>{
      for (final item in _confirmed.values) idOf(item): item,
    };
    final confirmedKeys = pendingKeyOf == null
        ? const <Object>{}
        : {
            for (final item in _confirmed.values)
              if (pendingKeyOf!(item) case final key?) key,
          };
    for (final item in _pending.values) {
      final key = pendingKeyOf?.call(item);
      if (key != null && confirmedKeys.contains(key)) continue;
      byId[idOf(item)] = item;
    }
    final merged = byId.values.toList();
    if (compare != null) merged.sort(compare);
    return merged;
  }
}
