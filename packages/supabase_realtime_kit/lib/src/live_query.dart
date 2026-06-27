import 'dart:async';

import 'package:supabase/supabase.dart';
import 'package:supabase_realtime_kit/src/realtime_kit_exception.dart';
import 'package:supabase_realtime_kit/src/result.dart';
import 'package:supabase_realtime_kit/src/types.dart';

/// A realtime, self-updating view of a filtered table slice.
///
/// [LiveQuery] does the three things people get wrong when wiring Supabase
/// realtime by hand:
///   1. **Initial load + live tail** — fetches a first page over REST, then
///      keeps it current from `postgres_changes` (insert/update/delete).
///   2. **Optimistic merge** — [addPending] shows a row instantly; when the
///      server echo arrives (matched by [pendingKeyOf]) the placeholder is
///      transparently replaced.
///   3. **Reconnect reconciliation** — on resubscribe it refetches the head of
///      the list to backfill any changes missed while offline.
///
/// Create instances via `RealtimeKit.liveQuery(...)`.
class LiveQuery<T> {
  /// Creates a live query. Prefer `RealtimeKit.liveQuery` over calling this
  /// directly.
  LiveQuery({
    required SupabaseClient client,
    required this.table,
    required this.fromJson,
    required this.idOf,
    this.schema = 'public',
    this.primaryKeyColumn = 'id',
    this.filterColumn,
    this.filterValue,
    this.orderColumn = 'created_at',
    this.ascending = false,
    this.pageSize = 30,
    this.pendingKeyOf,
    this.compare,
    String? channelName,
  }) : assert(
         filterColumn == null || filterValue != null,
         'filterValue is required when filterColumn is set',
       ),
       _client = client,
       channelName =
           channelName ??
           'rtk:$schema:$table'
               '${filterColumn == null ? '' : ':$filterColumn=$filterValue'}';

  final SupabaseClient _client;

  /// The table being observed.
  final String table;

  /// The Postgres schema of [table].
  final String schema;

  /// The primary-key column, used to identify rows in delete events.
  final String primaryKeyColumn;

  /// Maps a row to a `T`.
  final FromJson<T> fromJson;

  /// Extracts the server identity of a `T`.
  final IdSelector<T> idOf;

  /// Optional equality filter column (e.g. `room_id`).
  final String? filterColumn;

  /// The value [filterColumn] must equal.
  final Object? filterValue;

  /// Column used for ordering the initial fetch and pagination.
  final String orderColumn;

  /// Whether the database fetch is ascending.
  final bool ascending;

  /// Page size for the initial load and [loadMore].
  final int pageSize;

  /// Optional optimistic-reconciliation key selector. Needed by [addPending].
  final PendingKeySelector<T>? pendingKeyOf;

  /// Optional comparator controlling the order of emitted items. When `null`,
  /// items keep database order with optimistic rows appended.
  final Comparator<T>? compare;

  /// The realtime channel name this query subscribes on.
  final String channelName;

  final Map<Object, T> _confirmed = <Object, T>{};
  final Map<Object, T> _pending = <Object, T>{};
  final StreamController<List<T>> _controller =
      StreamController<List<T>>.broadcast();

  RealtimeChannel? _channel;
  List<T> _snapshot = <T>[];
  int _offset = 0;
  bool _hasMore = true;
  bool _everSubscribed = false;
  bool _started = false;
  bool _disposed = false;

  /// The current merged snapshot (confirmed rows + unconfirmed optimistic).
  List<T> get items => List<T>.unmodifiable(_snapshot);

  /// Whether [loadMore] may return additional older rows.
  bool get hasMore => _hasMore;

  /// A broadcast stream of merged snapshots. New listeners immediately receive
  /// the latest snapshot.
  Stream<List<T>> get stream async* {
    yield items;
    yield* _controller.stream;
  }

  /// Subscribes to realtime changes and performs the initial load.
  ///
  /// Idempotent: a second call returns the current snapshot without
  /// re-subscribing. Returns the first page or an [Err] on failure.
  Future<Result<List<T>>> start() async {
    if (_started) return Result<List<T>>.ok(items);
    _started = true;
    _subscribe();
    return loadInitial();
  }

  /// Merges the head of the list (newest rows) without clearing already-loaded
  /// older pages. Used to backfill changes missed while disconnected.
  Future<void> _backfill() async {
    final result = await Result.guard(() async {
      final rows = await _fetchPage(0);
      for (final row in rows) {
        _upsertConfirmed(fromJson(row));
      }
      _emit();
    });
    // Backfill is best-effort; surface failures on the stream, don't throw.
    if (result case Err(:final error)) {
      if (!_controller.isClosed) _controller.addError(error);
    }
  }

  /// Fetches (or refetches) the first page, replacing confirmed state.
  Future<Result<List<T>>> loadInitial() => Result.guard(() async {
    final rows = await _fetchPage(0);
    _confirmed.clear();
    for (final row in rows) {
      final item = fromJson(row);
      _confirmed[idOf(item)] = item;
    }
    _offset = rows.length;
    _hasMore = rows.length == pageSize;
    _emit();
    return items;
  });

  /// Loads the next page of older rows and merges them in.
  Future<Result<List<T>>> loadMore() => Result.guard(() async {
    if (!_hasMore) return <T>[];
    final rows = await _fetchPage(_offset);
    final loaded = <T>[];
    for (final row in rows) {
      final item = fromJson(row);
      _confirmed[idOf(item)] = item;
      loaded.add(item);
    }
    _offset += rows.length;
    _hasMore = rows.length == pageSize;
    _emit();
    return loaded;
  });

  /// Inserts an optimistic [item] that renders immediately and is replaced by
  /// its server echo. Requires [pendingKeyOf] to have been provided.
  void addPending(T item) {
    final key = pendingKeyOf?.call(item);
    assert(key != null, 'addPending requires a non-null pendingKeyOf');
    if (key == null) return;
    _pending[key] = item;
    _emit();
  }

  /// Removes a previously added optimistic item (e.g. after a permanent send
  /// failure) by its [pendingKey].
  void removePending(Object pendingKey) {
    if (_pending.remove(pendingKey) != null) _emit();
  }

  Future<List<JsonMap>> _fetchPage(int offset) async {
    final selected = filterColumn == null
        ? _client.schema(schema).from(table).select()
        : _client
              .schema(schema)
              .from(table)
              .select()
              .eq(filterColumn!, filterValue!);
    final rows = await selected
        .order(orderColumn, ascending: ascending)
        .range(offset, offset + pageSize - 1);
    return rows;
  }

  void _subscribe() {
    final channel = _client.channel(channelName);
    final filter = filterColumn == null
        ? null
        : PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: filterColumn!,
            value: filterValue,
          );

    for (final event in const [
      PostgresChangeEvent.insert,
      PostgresChangeEvent.update,
      PostgresChangeEvent.delete,
    ]) {
      channel.onPostgresChanges(
        event: event,
        schema: schema,
        table: table,
        filter: filter,
        callback: _onChange,
      );
    }

    channel.subscribe(_onStatus);
    _channel = channel;
  }

  void _onChange(PostgresChangePayload payload) {
    switch (payload.eventType) {
      case PostgresChangeEvent.insert:
      case PostgresChangeEvent.update:
        _upsertConfirmed(fromJson(payload.newRecord));
      case PostgresChangeEvent.delete:
        // NOTE: for a *filtered* query, Postgres only includes non-PK columns
        // in the delete payload when the table uses `REPLICA IDENTITY FULL`.
        // With the default identity, filtered deletes may not be delivered at
        // all — prefer soft-deletes (an UPDATE) when you need a filter.
        final id = payload.oldRecord[primaryKeyColumn];
        if (id != null) _confirmed.remove(id);
      case PostgresChangeEvent.all:
        return; // never delivered for a concrete change
    }
    _emit();
  }

  void _upsertConfirmed(T item) {
    _confirmed[idOf(item)] = item;
    final key = pendingKeyOf?.call(item);
    if (key != null) _pending.remove(key); // reconcile optimistic placeholder
  }

  void _onStatus(RealtimeSubscribeStatus status, Object? error) {
    switch (status) {
      case RealtimeSubscribeStatus.subscribed:
        if (_everSubscribed) {
          // Backfill anything missed while the socket was down, preserving
          // already-loaded older pages.
          unawaited(_backfill());
        }
        _everSubscribed = true;
      case RealtimeSubscribeStatus.channelError:
      case RealtimeSubscribeStatus.timedOut:
        if (!_controller.isClosed) {
          _controller.addError(
            ChannelSubscribeException(channelName, cause: error),
          );
        }
      case RealtimeSubscribeStatus.closed:
        break;
    }
  }

  void _emit() {
    if (_disposed) return;
    final byId = <Object, T>{
      for (final item in _confirmed.values) idOf(item): item,
    };
    // Overlay optimistic rows that the server has not yet echoed.
    final confirmedKeys = pendingKeyOf == null
        ? const <Object>{}
        : {
            for (final item in _confirmed.values)
              if (pendingKeyOf!(item) case final k?) k,
          };
    for (final item in _pending.values) {
      final key = pendingKeyOf?.call(item);
      if (key != null && confirmedKeys.contains(key)) continue;
      byId[idOf(item)] = item;
    }
    final merged = byId.values.toList();
    if (compare != null) merged.sort(compare);
    _snapshot = merged;
    if (!_controller.isClosed) _controller.add(items);
  }

  /// Unsubscribes from realtime and releases resources. Idempotent.
  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    final channel = _channel;
    if (channel != null) await _client.removeChannel(channel);
    await _controller.close();
  }
}
