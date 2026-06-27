import 'dart:async';

import 'package:supabase_chat/src/models/attachment.dart';
import 'package:supabase_chat/src/models/message.dart';
import 'package:supabase_chat/src/models/reaction.dart';
import 'package:supabase_chat/src/typing_tracker.dart';
import 'package:supabase_realtime_kit/supabase_realtime_kit.dart';

/// A live, plug-and-play handle on a single chat room.
///
/// Wires together everything a WhatsApp-style conversation needs: durable
/// message history with optimistic send, replies, edits, soft-deletes, emoji
/// reactions, typing indicators, presence, read receipts and unread counts.
///
/// ```dart
/// final room = chat.room(roomId);
/// await room.join();
/// room.messages.listen(render);
/// await room.send(text: 'hello');
/// await room.react(messageId, '👍');
/// ```
class ChatRoom {
  /// Creates a room handle. Prefer `SupabaseChat.room(...)`.
  ChatRoom({
    required RealtimeKit kit,
    required this.roomId,
    required this.currentUserId,
    Map<String, dynamic> presenceState = const {},
    Duration typingTimeout = const Duration(seconds: 4),
  }) : _kit = kit,
       _presenceState = {'user_id': currentUserId, ...presenceState},
       _typingTracker = TypingTracker(
         currentUserId: currentUserId,
         timeout: typingTimeout,
       );

  /// The room id.
  final String roomId;

  /// The signed-in user driving this handle.
  final String currentUserId;

  final RealtimeKit _kit;
  final Map<String, dynamic> _presenceState;
  final TypingTracker _typingTracker;

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

  late final LiveQuery<Reaction> _reactions = _kit.liveQuery<Reaction>(
    table: 'message_reactions',
    filterColumn: 'room_id',
    filterValue: roomId,
    fromJson: Reaction.fromJson,
    idOf: (r) => r.id,
    compare: (a, b) => a.createdAt.compareTo(b.createdAt),
    channelName: 'chat:reactions:$roomId',
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

  StreamSubscription<JsonMap>? _typingSub;
  DateTime? _lastReadAt;
  bool _joined = false;

  /// The live, ordered (oldest→newest) list of messages, including optimistic
  /// sends.
  Stream<List<Message>> get messages => _messages.stream;

  /// The current message snapshot.
  List<Message> get currentMessages => _messages.items;

  /// All reactions in the room.
  Stream<List<Reaction>> get reactions => _reactions.stream;

  /// Reactions grouped by message id — convenient for rendering reaction chips.
  Stream<Map<String, List<Reaction>>> get reactionsByMessage =>
      _reactions.stream.map((all) {
        final grouped = <String, List<Reaction>>{};
        for (final reaction in all) {
          (grouped[reaction.messageId] ??= <Reaction>[]).add(reaction);
        }
        return grouped;
      });

  /// User ids (excluding the current user) currently typing.
  Stream<List<String>> get typingUserIds => _typingTracker.stream;

  /// State payloads of everyone currently present in the room.
  Stream<List<JsonMap>> get presentUsers => _presence.stream;

  /// A live count of messages from others newer than the last read marker.
  Stream<int> get unreadCount => _messages.stream.map(_countUnread);

  /// Whether there are older messages to page in.
  bool get hasMore => _messages.hasMore;

  /// Subscribes to messages, reactions, typing, and presence; loads the first
  /// page and the read marker. Idempotent.
  Future<void> join() async {
    if (_joined) return;
    _joined = true;
    _typingSub = _typing
        .on('typing')
        .listen(
          (p) => _typingTracker.apply(
            userId: p['user_id'] as String?,
            typing: p['typing'] as bool? ?? false,
          ),
        );
    await Future.wait([
      _messages.start(),
      _reactions.start(),
      _typing.start(),
      _presence.start(),
      _loadReadMarker(),
    ]);
  }

  /// Sends a message, rendering it optimistically and persisting it via the
  /// outbox-backed write path. Use [replyToId] to quote another message and
  /// [attachments]/[type] for media. The returned [Result] reflects the
  /// *persist* outcome; on failure the optimistic message remains queued.
  Future<Result<Message>> send({
    String? text,
    String? replyToId,
    List<Attachment> attachments = const [],
    MessageType type = MessageType.text,
    Map<String, dynamic> extra = const <String, dynamic>{},
  }) async {
    final clientId = _newClientId();
    final optimistic = Message(
      id: 'tmp:$clientId',
      roomId: roomId,
      senderId: currentUserId,
      type: type,
      content: text,
      attachments: attachments,
      replyToId: replyToId,
      clientId: clientId,
      createdAt: DateTime.now().toUtc(),
      pending: true,
      extra: extra,
    );
    _messages.addPending(optimistic);

    final result = await _kit.insert(
      table: 'messages',
      payload: optimistic.toInsert(),
      outboxId: clientId,
    );
    return result.map(Message.fromJson);
  }

  /// Sends a media message ([attachments] already uploaded via
  /// `SupabaseChat.uploadAttachment`), inferring a sensible [type].
  Future<Result<Message>> sendMedia({
    required List<Attachment> attachments,
    String? caption,
    String? replyToId,
    MessageType? type,
  }) => send(
    text: caption,
    replyToId: replyToId,
    attachments: attachments,
    type: type ?? _inferType(attachments),
  );

  /// Replies to [toMessageId] with [text] (and optional [attachments]).
  Future<Result<Message>> reply({
    required String toMessageId,
    String? text,
    List<Attachment> attachments = const [],
  }) => send(text: text, replyToId: toMessageId, attachments: attachments);

  /// Edits the text of a message the current user authored.
  Future<Result<void>> editMessage(String messageId, String text) =>
      Result.guard(() async {
        await _kit.client
            .from('messages')
            .update({
              'content': text,
              'edited_at': DateTime.now().toUtc().toIso8601String(),
            })
            .eq('id', messageId);
      });

  /// Soft-deletes a message the current user authored (history is preserved;
  /// the row is marked deleted and its content cleared).
  Future<Result<void>> deleteMessage(String messageId) =>
      Result.guard(() async {
        await _kit.client
            .from('messages')
            .update({
              'deleted_at': DateTime.now().toUtc().toIso8601String(),
              'content': null,
            })
            .eq('id', messageId);
      });

  /// Adds an emoji [reaction] to [messageId] (idempotent per user+emoji).
  Future<Result<void>> react(String messageId, String reaction) =>
      Result.guard(() async {
        await _kit.client.from('message_reactions').upsert({
          'room_id': roomId,
          'message_id': messageId,
          'user_id': currentUserId,
          'emoji': reaction,
        }, onConflict: 'message_id,user_id,emoji');
      });

  /// Removes the current user's [reaction] from [messageId].
  Future<Result<void>> removeReaction(String messageId, String reaction) =>
      Result.guard(() async {
        await _kit.client
            .from('message_reactions')
            .delete()
            .eq('message_id', messageId)
            .eq('user_id', currentUserId)
            .eq('emoji', reaction);
      });

  /// Broadcasts whether the current user is typing.
  Future<void> setTyping({required bool typing}) => _typing.send(
    event: 'typing',
    payload: {'user_id': currentUserId, 'typing': typing},
  );

  /// Marks the room read up to now: advances the user's read marker (for unread
  /// counts) and, when [messageId] is given, records a per-message receipt.
  Future<Result<void>> markRead([String? messageId]) => Result.guard(() async {
    final now = DateTime.now().toUtc();
    _lastReadAt = now;
    await _kit.client
        .from('room_members')
        .update({'last_read_at': now.toIso8601String()})
        .eq('room_id', roomId)
        .eq('user_id', currentUserId);
    if (messageId != null) {
      await _kit.client.from('message_receipts').upsert({
        'message_id': messageId,
        'user_id': currentUserId,
      });
    }
  });

  /// Loads an older page of messages.
  Future<Result<List<Message>>> loadMore() => _messages.loadMore();

  int _countUnread(List<Message> msgs) {
    final marker = _lastReadAt;
    return msgs.where((m) {
      if (m.senderId == currentUserId || m.isDeleted) return false;
      return marker == null || m.createdAt.isAfter(marker);
    }).length;
  }

  Future<void> _loadReadMarker() async {
    final result = await Result.guard(() async {
      final row = await _kit.client
          .from('room_members')
          .select('last_read_at')
          .eq('room_id', roomId)
          .eq('user_id', currentUserId)
          .maybeSingle();
      final value = row?['last_read_at'] as String?;
      if (value != null) _lastReadAt = DateTime.parse(value).toUtc();
    });
    // Best-effort; absence just means everything counts as unread.
    if (result.isErr) _lastReadAt = null;
  }

  MessageType _inferType(List<Attachment> attachments) {
    final mime = attachments.firstOrNull?.mimeType ?? '';
    if (mime.startsWith('image/')) return MessageType.image;
    if (mime.startsWith('video/')) return MessageType.video;
    if (mime.startsWith('audio/')) return MessageType.audio;
    return MessageType.file;
  }

  static int _counter = 0;
  String _newClientId() =>
      '${currentUserId}_${DateTime.now().microsecondsSinceEpoch}_${_counter++}';

  /// Leaves the room and releases all realtime resources. Idempotent.
  Future<void> leave() async {
    await _typingSub?.cancel();
    await Future.wait([
      _messages.dispose(),
      _reactions.dispose(),
      _typing.dispose(),
      _presence.dispose(),
      _typingTracker.dispose(),
    ]);
  }
}
