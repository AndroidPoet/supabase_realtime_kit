import 'package:meta/meta.dart';

/// A pending write that could not be delivered immediately (e.g. offline) and
/// will be retried by the kit on reconnect.
@immutable
class OutboxEntry {
  /// Creates an outbox entry.
  const OutboxEntry({
    required this.id,
    required this.table,
    required this.payload,
    this.schema = 'public',
    this.attempts = 0,
  });

  /// Reconstructs an entry from [json] produced by [toJson].
  factory OutboxEntry.fromJson(Map<String, dynamic> json) => OutboxEntry(
    id: json['id'] as String,
    table: json['table'] as String,
    payload: Map<String, dynamic>.from(json['payload'] as Map),
    schema: json['schema'] as String? ?? 'public',
    attempts: json['attempts'] as int? ?? 0,
  );

  /// Stable client-generated id. For chat this doubles as `messages.client_id`,
  /// giving idempotent delivery and optimistic reconciliation.
  final String id;

  /// The target table for the queued insert.
  final String table;

  /// The Postgres schema of [table].
  final String schema;

  /// The row to insert.
  final Map<String, dynamic> payload;

  /// How many delivery attempts have been made so far.
  final int attempts;

  /// Returns a copy with [attempts] incremented by one.
  OutboxEntry incrementAttempts() => OutboxEntry(
    id: id,
    table: table,
    payload: payload,
    schema: schema,
    attempts: attempts + 1,
  );

  /// Serializes this entry for persistent outbox implementations.
  Map<String, dynamic> toJson() => {
    'id': id,
    'table': table,
    'schema': schema,
    'payload': payload,
    'attempts': attempts,
  };
}

/// Storage for writes awaiting delivery.
///
/// The kit ships an in-memory implementation ([InMemoryOutbox]). For durable
/// offline support, implement this against your own store (SharedPreferences,
/// SQLite, Hive, …) and pass it in — persistence is intentionally **not**
/// bundled so the core stays dependency-light and platform-agnostic.
abstract interface class Outbox {
  /// Adds [entry] to the queue (replacing any existing entry with the same id).
  Future<void> add(OutboxEntry entry);

  /// Returns all pending entries in insertion order.
  Future<List<OutboxEntry>> pending();

  /// Removes the entry with [id] (called after successful delivery).
  Future<void> remove(String id);

  /// Replaces an existing entry, typically to persist an incremented attempt
  /// count after a failed delivery.
  Future<void> update(OutboxEntry entry);
}

/// Default non-durable [Outbox]. Survives reconnects within a process but not
/// app restarts.
final class InMemoryOutbox implements Outbox {
  final Map<String, OutboxEntry> _entries = <String, OutboxEntry>{};

  @override
  Future<void> add(OutboxEntry entry) async => _entries[entry.id] = entry;

  @override
  Future<List<OutboxEntry>> pending() async => _entries.values.toList();

  @override
  Future<void> remove(String id) async => _entries.remove(id);

  @override
  Future<void> update(OutboxEntry entry) async => _entries[entry.id] = entry;
}
