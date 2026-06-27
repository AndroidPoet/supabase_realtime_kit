import 'dart:async';

import 'package:meta/meta.dart';
import 'package:supabase/supabase.dart';
import 'package:supabase_realtime_kit/src/broadcast_hub.dart';
import 'package:supabase_realtime_kit/src/connection_state.dart';
import 'package:supabase_realtime_kit/src/live_query.dart';
import 'package:supabase_realtime_kit/src/outbox.dart';
import 'package:supabase_realtime_kit/src/presence_tracker.dart';
import 'package:supabase_realtime_kit/src/realtime_kit_exception.dart';
import 'package:supabase_realtime_kit/src/result.dart';
import 'package:supabase_realtime_kit/src/types.dart';

/// The entry point of the kit: a thin, opinionated layer over a
/// [SupabaseClient] that hands out realtime primitives and an outbox-backed
/// write path.
///
/// ```dart
/// final kit = RealtimeKit(Supabase.instance.client);
/// final messages = kit.liveQuery<Message>(
///   table: 'messages',
///   filterColumn: 'room_id', filterValue: roomId,
///   fromJson: Message.fromJson,
///   idOf: (m) => m.id,
///   pendingKeyOf: (m) => m.clientId,
///   compare: (a, b) => a.createdAt.compareTo(b.createdAt),
/// );
/// await messages.start();
/// messages.stream.listen(render);
/// ```
class RealtimeKit {
  /// Wraps [client]. Optionally supply a durable [outbox]; an in-memory one is
  /// used by default. When [autoFlushOutbox] is true (the default), queued
  /// writes are retried automatically whenever the realtime socket reconnects.
  RealtimeKit(
    this.client, {
    Outbox? outbox,
    this.autoFlushOutbox = true,
    this.maxOutboxAttempts = defaultMaxOutboxAttempts,
  }) : outbox = outbox ?? InMemoryOutbox() {
    if (autoFlushOutbox) {
      client.realtime.onOpen(() => unawaited(flushOutbox()));
    }
  }

  /// Default ceiling on outbox delivery attempts before an entry is dropped.
  static const int defaultMaxOutboxAttempts = 8;

  /// The underlying Supabase client.
  final SupabaseClient client;

  /// The outbox used to queue writes that fail while offline.
  final Outbox outbox;

  /// Whether the outbox is flushed automatically on reconnect.
  final bool autoFlushOutbox;

  /// Maximum delivery attempts before a permanently-failing entry is dropped
  /// (dead-lettered) so it can't be retried forever.
  final int maxOutboxAttempts;

  /// Creates a realtime, self-updating [LiveQuery] over a table slice.
  ///
  /// You must call [LiveQuery.start] on the returned instance.
  LiveQuery<T> liveQuery<T>({
    required String table,
    required FromJson<T> fromJson,
    required IdSelector<T> idOf,
    String schema = 'public',
    String primaryKeyColumn = 'id',
    String? filterColumn,
    Object? filterValue,
    String orderColumn = 'created_at',
    bool ascending = false,
    int pageSize = 30,
    PendingKeySelector<T>? pendingKeyOf,
    Comparator<T>? compare,
    String? channelName,
  }) {
    return LiveQuery<T>(
      client: client,
      table: table,
      fromJson: fromJson,
      idOf: idOf,
      schema: schema,
      primaryKeyColumn: primaryKeyColumn,
      filterColumn: filterColumn,
      filterValue: filterValue,
      orderColumn: orderColumn,
      ascending: ascending,
      pageSize: pageSize,
      pendingKeyOf: pendingKeyOf,
      compare: compare,
      channelName: channelName,
    );
  }

  /// Creates a [PresenceTracker] for [channelName].
  PresenceTracker presence({
    required String channelName,
    required JsonMap initialState,
    String presenceKey = '',
  }) {
    return PresenceTracker(
      client: client,
      channelName: channelName,
      initialState: initialState,
      presenceKey: presenceKey,
    );
  }

  /// Creates a [BroadcastHub] for [channelName] listening for [events].
  BroadcastHub broadcast({
    required String channelName,
    required List<String> events,
    bool receiveOwn = false,
    bool ack = false,
  }) {
    return BroadcastHub(
      client: client,
      channelName: channelName,
      events: events,
      receiveOwn: receiveOwn,
      ack: ack,
    );
  }

  /// Inserts [payload] into [table], returning the stored row.
  ///
  /// If the insert fails and [outboxId] is provided, the write is queued for
  /// retry on the next reconnect and an [Err] (wrapping a [WriteException]) is
  /// returned. Provide a stable [outboxId] (also stored as the row's
  /// idempotency key) to make retries safe.
  Future<Result<JsonMap>> insert({
    required String table,
    required JsonMap payload,
    String schema = 'public',
    String? outboxId,
  }) async {
    try {
      final inserted = await client
          .schema(schema)
          .from(table)
          .insert(payload)
          .select()
          .single();
      return Ok<JsonMap>(inserted);
    } on Object catch (error, stackTrace) {
      if (outboxId != null) {
        await outbox.add(
          OutboxEntry(
            id: outboxId,
            table: table,
            payload: payload,
            schema: schema,
          ),
        );
      }
      return Err<JsonMap>(WriteException(table, cause: error), stackTrace);
    }
  }

  /// Attempts to deliver every queued write. Successful and already-delivered
  /// (duplicate-key) entries are removed; transient failures increment the
  /// attempt count and stay queued; entries that exceed [maxOutboxAttempts] are
  /// dropped so a poison write can't retry forever.
  Future<void> flushOutbox() async {
    for (final entry in await outbox.pending()) {
      await deliverOutboxEntry(
        entry,
        outbox,
        (e) => client.schema(e.schema).from(e.table).insert(e.payload),
        maxAttempts: maxOutboxAttempts,
      );
    }
  }

  /// Delivers a single outbox [entry] via [send], applying the outbox decision
  /// policy and mutating [outbox] accordingly. Exposed for testing the policy
  /// without a live client.
  @visibleForTesting
  static Future<void> deliverOutboxEntry(
    OutboxEntry entry,
    Outbox outbox,
    Future<void> Function(OutboxEntry entry) send, {
    int maxAttempts = defaultMaxOutboxAttempts,
  }) async {
    try {
      await send(entry);
      await outbox.remove(entry.id);
    } on PostgrestException catch (error) {
      if (error.code == '23505') {
        // Unique violation → a previous attempt already landed. Done.
        await outbox.remove(entry.id);
      } else {
        await _failOrDrop(entry, outbox, maxAttempts);
      }
    } on Object catch (_) {
      await _failOrDrop(entry, outbox, maxAttempts);
    }
  }

  static Future<void> _failOrDrop(
    OutboxEntry entry,
    Outbox outbox,
    int maxAttempts,
  ) async {
    if (entry.attempts + 1 >= maxAttempts) {
      // Dead-letter: drop the poison entry rather than retry it forever.
      await outbox.remove(entry.id);
    } else {
      await outbox.update(entry.incrementAttempts());
    }
  }

  StreamController<KitConnectionState>? _connectionController;
  KitConnectionState _lastConnState = KitConnectionState.disconnected;
  bool _disposed = false;

  /// A broadcast stream of high-level [KitConnectionState] transitions derived
  /// from the realtime socket. New listeners immediately receive the current
  /// state.
  ///
  /// Socket callbacks are registered once and shared across all callers; close
  /// the stream via [dispose].
  Stream<KitConnectionState> connectionStates() async* {
    _ensureConnectionWiring();
    yield _lastConnState;
    yield* _connectionController!.stream;
  }

  void _ensureConnectionWiring() {
    if (_disposed || _connectionController != null) return;
    final controller = StreamController<KitConnectionState>.broadcast();
    _connectionController = controller;

    void emit(KitConnectionState state) {
      _lastConnState = state;
      if (!controller.isClosed) controller.add(state);
    }

    client.realtime
      ..onOpen(() => emit(KitConnectionState.connected))
      ..onClose((_) => emit(KitConnectionState.disconnected))
      ..onError((_) => emit(KitConnectionState.disconnected));
    _lastConnState = client.realtime.isConnected
        ? KitConnectionState.connected
        : KitConnectionState.disconnected;
  }

  /// Releases resources owned by the kit (the connection-state stream).
  /// Does not close the underlying [SupabaseClient].
  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    await _connectionController?.close();
    _connectionController = null;
  }
}
