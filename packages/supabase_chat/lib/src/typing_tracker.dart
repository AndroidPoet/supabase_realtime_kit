import 'dart:async';

/// Pure, IO-free tracker for "who is typing" with per-user auto-expiry.
///
/// Broadcast typing signals have no natural "stopped" guarantee (a client can
/// drop off without sending `typing: false`), so each peer's indicator expires
/// after [timeout] unless refreshed. Keeping this free of any realtime
/// dependency makes the timer logic unit-testable with `fake_async`.
class TypingTracker {
  /// Creates a tracker for [currentUserId] (whose own signals are ignored).
  TypingTracker({
    required this.currentUserId,
    this.timeout = const Duration(seconds: 4),
  });

  /// The local user, filtered out of the typing set.
  final String currentUserId;

  /// How long a peer stays "typing" without a refresh.
  final Duration timeout;

  final Set<String> _users = <String>{};
  final Map<String, Timer> _timers = <String, Timer>{};
  final StreamController<List<String>> _controller =
      StreamController<List<String>>.broadcast();
  bool _disposed = false;

  /// Broadcast stream of currently-typing user ids; new listeners immediately
  /// receive the current set.
  Stream<List<String>> get stream async* {
    yield users;
    yield* _controller.stream;
  }

  /// The current set of typing user ids (excluding [currentUserId]).
  List<String> get users => _users.toList();

  /// Applies a typing signal. Signals from [currentUserId] or a null id are
  /// ignored. A `typing: true` signal (re)starts the expiry timer.
  void apply({required String? userId, required bool typing}) {
    if (userId == null || userId == currentUserId) return;

    _timers.remove(userId)?.cancel();
    if (typing) {
      _users.add(userId);
      _timers[userId] = Timer(timeout, () {
        _users.remove(userId);
        _emit();
      });
    } else {
      _users.remove(userId);
    }
    _emit();
  }

  void _emit() {
    if (!_controller.isClosed) _controller.add(users);
  }

  /// Cancels all timers and closes the stream. Idempotent.
  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    for (final timer in _timers.values) {
      timer.cancel();
    }
    _timers.clear();
    await _controller.close();
  }
}
