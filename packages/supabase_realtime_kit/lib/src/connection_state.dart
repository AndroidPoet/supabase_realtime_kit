/// High-level connection state of the realtime socket, normalized away from the
/// SDK's lower-level channel/socket status enums.
enum KitConnectionState {
  /// The socket is establishing or re-establishing a connection.
  connecting,

  /// The socket is connected and channels can send/receive.
  connected,

  /// The socket is disconnected; sends are queued by the outbox if enabled.
  disconnected;

  /// Whether realtime traffic can flow right now.
  bool get isLive => this == KitConnectionState.connected;
}
