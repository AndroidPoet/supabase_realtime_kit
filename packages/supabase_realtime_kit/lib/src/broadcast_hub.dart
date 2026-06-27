import 'dart:async';

import 'package:supabase/supabase.dart';
import 'package:supabase_realtime_kit/src/types.dart' show JsonMap;

/// Sends and receives ephemeral, non-persisted events over a realtime channel
/// using Supabase Broadcast — ideal for typing indicators, live reactions,
/// cursors, and other signals that should not hit the database.
class BroadcastHub {
  /// Creates a broadcast hub listening for [events]. Prefer
  /// `RealtimeKit.broadcast(...)`.
  ///
  /// Set [receiveOwn] to also receive messages this client sends (useful for
  /// multi-device echo); [ack] requests server acknowledgement of sends.
  BroadcastHub({
    required SupabaseClient client,
    required this.channelName,
    required List<String> events,
    this.receiveOwn = false,
    this.ack = false,
  }) : _client = client,
       _events = List<String>.unmodifiable(events),
       _controllers = {
         for (final event in events)
           event: StreamController<JsonMap>.broadcast(),
       };

  final SupabaseClient _client;

  /// The realtime channel name used for broadcast.
  final String channelName;

  /// Whether this client receives its own broadcasts.
  final bool receiveOwn;

  /// Whether sends request server acknowledgement.
  final bool ack;

  final List<String> _events;
  final Map<String, StreamController<JsonMap>> _controllers;
  RealtimeChannel? _channel;
  bool _started = false;
  bool _disposed = false;

  /// The stream of payloads for a single broadcast [event].
  ///
  /// The event must have been declared in the constructor's `events` list.
  Stream<JsonMap> on(String event) {
    final controller = _controllers[event];
    if (controller == null) {
      throw ArgumentError.value(
        event,
        'event',
        'Not declared in the BroadcastHub events list ($_events)',
      );
    }
    return controller.stream;
  }

  /// Subscribes to the channel and begins receiving the declared events.
  /// Idempotent.
  Future<void> start() async {
    if (_started) return;
    _started = true;
    final channel = _client.channel(
      channelName,
      opts: RealtimeChannelConfig(self: receiveOwn, ack: ack),
    );
    for (final event in _events) {
      channel.onBroadcast(
        event: event,
        callback: (payload) =>
            _controllers[event]?.add(Map<String, dynamic>.from(payload)),
      );
    }
    channel.subscribe();
    _channel = channel;
  }

  /// Broadcasts [payload] under [event] to all other clients on the channel.
  Future<void> send({required String event, required JsonMap payload}) async {
    await _channel?.sendBroadcastMessage(event: event, payload: payload);
  }

  /// Releases the channel and closes all event streams. Idempotent.
  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    final channel = _channel;
    if (channel != null) await _client.removeChannel(channel);
    for (final controller in _controllers.values) {
      await controller.close();
    }
  }
}
