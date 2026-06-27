import 'dart:async';

import 'package:supabase/supabase.dart';
import 'package:supabase_realtime_kit/src/types.dart' show JsonMap;

/// Tracks who is currently present on a channel using Supabase Presence.
///
/// Each connected client publishes a small state map (e.g. user id, name);
/// [stream] emits the flattened list of all present clients' states and updates
/// as people join and leave.
class PresenceTracker {
  /// Creates a presence tracker. Prefer `RealtimeKit.presence(...)`.
  PresenceTracker({
    required SupabaseClient client,
    required this.channelName,
    required JsonMap initialState,
    String presenceKey = '',
  }) : _client = client,
       _state = initialState,
       _presenceKey = presenceKey;

  final SupabaseClient _client;

  /// The realtime channel name used for presence.
  final String channelName;

  final String _presenceKey;
  JsonMap _state;

  RealtimeChannel? _channel;
  List<JsonMap> _present = <JsonMap>[];
  final StreamController<List<JsonMap>> _controller =
      StreamController<List<JsonMap>>.broadcast();
  bool _started = false;
  bool _disposed = false;

  /// The latest list of present clients' state payloads.
  List<JsonMap> get present => List<JsonMap>.unmodifiable(_present);

  /// A broadcast stream of present clients, emitting the current value to new
  /// listeners immediately.
  Stream<List<JsonMap>> get stream async* {
    yield present;
    yield* _controller.stream;
  }

  /// Joins the channel and begins broadcasting this client's presence.
  /// Idempotent.
  Future<void> start() async {
    if (_started) return;
    _started = true;
    final channel = _client.channel(
      channelName,
      opts: RealtimeChannelConfig(key: _presenceKey),
    );
    channel
      ..onPresenceSync((_) => _recompute(channel))
      ..onPresenceJoin((_) => _recompute(channel))
      ..onPresenceLeave((_) => _recompute(channel))
      ..subscribe((status, _) async {
        if (status == RealtimeSubscribeStatus.subscribed) {
          await channel.track(_state);
        }
      });
    _channel = channel;
  }

  /// Updates this client's published presence [state].
  Future<void> update(JsonMap state) async {
    _state = state;
    await _channel?.track(state);
  }

  void _recompute(RealtimeChannel channel) {
    if (_disposed) return;
    _present = [
      for (final entry in channel.presenceState())
        for (final presence in entry.presences) presence.payload,
    ];
    if (!_controller.isClosed) _controller.add(present);
  }

  /// Stops tracking and releases the channel. Idempotent.
  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    final channel = _channel;
    if (channel != null) {
      await channel.untrack();
      await _client.removeChannel(channel);
    }
    await _controller.close();
  }
}
