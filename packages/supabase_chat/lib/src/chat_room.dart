import 'dart:async';

import 'package:supabase_chat/src/models/message.dart';
import 'package:supabase_realtime_kit/supabase_realtime_kit.dart';

/// A live, plug-and-play handle on a single chat room.
///
/// One object wires together the durable message history, ephemeral typing
/// signals, and presence for a room:
///
/// ```dart
/// final room = chat.room(roomId);
/// await room.join();
/// room.messages.listen(render);
/// room.typingUserIds.listen(showTyping);
/// await room.send(text: 'hello');
/// ```
class ChatRoom {
  /// Creates a room handle. Prefer `SupabaseChat.room(...)`.
  ChatRoom({
    required RealtimeKit kit,
    required this.roomId,
    required this.currentUserId,
    Map<String, dynamic> presenceState = const {},
    this.typingTimeout = const Duration(seconds: 4),
  }) : _kit = kit,
       _presenceState = {'user_id': currentUserId, ...presenceState};

  /// Auto-expiry window for a peer's typing indicator.
  final Duration typingTimeout;

  /// The room id.
  final String roomId;

  /// The signed-in user driving this handle.
  final String currentUserId;

  final RealtimeKit _kit;
  final Map<String, dynamic> _presenceState;

  late final LiveQuery<Message> _messages = _kit.liveQuery<Message>(
    table: 'messages',
    filterColumn: 'room_id',
    filterValue: roomId,
    fromJson: Message.fromJson,
    idOf: (m) => m.id,
    pendingKeyOf: (m) => m.clientId,
    compare: (a, b) => a.createdAt.compareTo(b.createdAt),
    channelName: 'chat:messages:$roomId',
  );

  late final BroadcastHub _typing = _kit.broadcast(
    channelName: 'chat:typing:$roomId',
    events: const ['typing'],
  );

  late final PresenceTracker _presence = _kit.presence(
    channelName: 'chat:presence:$roomId',
    initialState: _presenceState,
    presenceKey: currentUserId,
  );

  final Set<String> _typingUsers = <String>{};
  final Map<String, Timer> _typingTimers = <String, Timer>{};
  final StreamController<List<String>> _typingController =
      StreamController<List<String>>.broadcast();
  StreamSubscription<JsonMap>? _typingSub;
  bool _joined = false;

  /// The live, ordered (oldest→newest) list of messages, including optimistic
  /// sends.
  Stream<List<Message>> get messages => _messages.stream;

  /// The current message snapshot.
  List<Message> get currentMessages => _messages.items;

  /// User ids (excluding the current user) currently typing.
  Stream<List<String>> get typingUserIds => _typingController.stream;

  /// State payloads of everyone currently present in the room.
  Stream<List<JsonMap>> get presentUsers => _presence.stream;

  /// Whether there are older messages to page in.
  bool get hasMore => _messages.hasMore;

  /// Subscribes to messages, typing, and presence and loads the first page.
  /// Idempotent.
  Future<void> join() async {
    if (_joined) return;
    _joined = true;
    _typingSub = _typing.on('typing').listen(_onTyping);
    await Future.wait([_messages.start(), _typing.start(), _presence.start()]);
  }

  /// Sends a message, rendering it optimistically and persisting it via the
  /// outbox-backed write path. The returned [Result] reflects the *persist*
  /// outcome; on failure the optimistic message remains queued for retry.
  Future<Result<Message>> send({
    String? text,
    List<Map<String, dynamic>> attachments = const [],
  }) async {
    final clientId = _newClientId();
    final optimistic = Message(
      id: 'tmp:$clientId',
      roomId: roomId,
      senderId: currentUserId,
      content: text,
      attachments: attachments,
      clientId: clientId,
      createdAt: DateTime.now().toUtc(),
      pending: true,
    );
    _messages.addPending(optimistic);

    final result = await _kit.insert(
      table: 'messages',
      payload: optimistic.toInsert(),
      outboxId: clientId,
    );
    return result.map(Message.fromJson);
  }

  /// Broadcasts whether the current user is typing.
  Future<void> setTyping({required bool typing}) => _typing.send(
    event: 'typing',
    payload: {'user_id': currentUserId, 'typing': typing},
  );

  /// Marks [messageId] as read by the current user.
  Future<Result<void>> markRead(String messageId) => Result.guard(() async {
    await _kit.client.from('message_receipts').upsert({
      'message_id': messageId,
      'user_id': currentUserId,
    });
  });

  /// Loads an older page of messages.
  Future<Result<List<Message>>> loadMore() => _messages.loadMore();

  void _onTyping(JsonMap payload) {
    final userId = payload['user_id'] as String?;
    final isTyping = payload['typing'] as bool? ?? false;
    if (userId == null || userId == currentUserId) return;

    _typingTimers.remove(userId)?.cancel();
    if (isTyping) {
      _typingUsers.add(userId);
      _typingTimers[userId] = Timer(typingTimeout, () {
        _typingUsers.remove(userId);
        _emitTyping();
      });
    } else {
      _typingUsers.remove(userId);
    }
    _emitTyping();
  }

  void _emitTyping() {
    if (!_typingController.isClosed) {
      _typingController.add(_typingUsers.toList());
    }
  }

  static int _counter = 0;
  String _newClientId() =>
      '${currentUserId}_${DateTime.now().microsecondsSinceEpoch}_${_counter++}';

  /// Leaves the room and releases all realtime resources. Idempotent.
  Future<void> leave() async {
    await _typingSub?.cancel();
    for (final timer in _typingTimers.values) {
      timer.cancel();
    }
    _typingTimers.clear();
    await Future.wait([
      _messages.dispose(),
      _typing.dispose(),
      _presence.dispose(),
    ]);
    await _typingController.close();
  }
}
