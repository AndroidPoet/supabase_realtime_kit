import 'package:meta/meta.dart';

/// Base type for errors surfaced by `supabase_realtime_kit`.
///
/// These wrap lower-level Supabase/Postgrest errors with kit context so callers
/// can branch on intent without depending on the underlying SDK's error types.
@immutable
sealed class RealtimeKitException implements Exception {
  /// Creates an exception with a human-readable [message] and an optional
  /// underlying [cause].
  const RealtimeKitException(this.message, {this.cause});

  /// A human-readable description of what went wrong.
  final String message;

  /// The originating error, if this wraps one.
  final Object? cause;

  @override
  String toString() =>
      // ignore: no_runtimetype_tostring  — the concrete type aids debugging.
      '$runtimeType: $message${cause == null ? '' : ' (cause: $cause)'}';
}

/// The realtime channel failed to subscribe or was closed unexpectedly.
final class ChannelSubscribeException extends RealtimeKitException {
  /// Creates a channel-subscription failure for [channelName].
  const ChannelSubscribeException(this.channelName, {super.cause})
    : super('Failed to subscribe to channel "$channelName"');

  /// The name of the channel that failed.
  final String channelName;
}

/// An initial load or pagination fetch against the database failed.
final class QueryException extends RealtimeKitException {
  /// Creates a query failure for [table].
  const QueryException(this.table, {super.cause})
    : super('Query against table "$table" failed');

  /// The table that was being queried.
  final String table;
}

/// A write (insert/update) failed after exhausting outbox retries.
final class WriteException extends RealtimeKitException {
  /// Creates a write failure for [table].
  const WriteException(this.table, {super.cause})
    : super('Write to table "$table" failed');

  /// The table that was being written to.
  final String table;
}
