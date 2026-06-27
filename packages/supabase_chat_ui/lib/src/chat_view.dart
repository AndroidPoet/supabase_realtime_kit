import 'dart:async';

import 'package:flutter/material.dart';
import 'package:supabase_chat/supabase_chat.dart';
import 'package:supabase_chat_ui/src/message_bubble.dart';
import 'package:supabase_chat_ui/src/message_composer.dart';
import 'package:supabase_chat_ui/src/typing_indicator.dart';

/// A complete, drop-in chat screen body for a [ChatRoom].
///
/// Renders messages (with replies, media and reactions), a typing indicator,
/// and a composer. Long-pressing a message toggles a 👍 reaction by default;
/// override [onMessageLongPress] to drive your own reply/react UI.
///
/// ```dart
/// Scaffold(
///   appBar: AppBar(title: const Text('general')),
///   body: ChatView(room: chat.room(roomId)),
/// );
/// ```
class ChatView extends StatefulWidget {
  /// Creates a chat view bound to [room].
  const ChatView({
    required this.room,
    super.key,
    this.manageLifecycle = true,
    this.nameFor,
    this.onMessageLongPress,
  });

  /// The room to display.
  final ChatRoom room;

  /// Whether this widget calls [ChatRoom.join]/[ChatRoom.leave] automatically.
  final bool manageLifecycle;

  /// Optional resolver from user id to display name (for typing indicator).
  final String Function(String userId)? nameFor;

  /// Overrides the default long-press behavior (toggle 👍).
  final void Function(Message message)? onMessageLongPress;

  @override
  State<ChatView> createState() => _ChatViewState();
}

class _ChatViewState extends State<ChatView> {
  final ScrollController _scroll = ScrollController();
  StreamSubscription<Map<String, List<Reaction>>>? _reactionsSub;
  Map<String, List<Reaction>> _reactions = const {};

  @override
  void initState() {
    super.initState();
    if (widget.manageLifecycle) widget.room.join();
    _reactionsSub = widget.room.reactionsByMessage.listen((grouped) {
      if (mounted) setState(() => _reactions = grouped);
    });
  }

  @override
  void dispose() {
    _reactionsSub?.cancel();
    if (widget.manageLifecycle) widget.room.leave();
    _scroll.dispose();
    super.dispose();
  }

  void _handleLongPress(Message message) {
    final custom = widget.onMessageLongPress;
    if (custom != null) {
      custom(message);
      return;
    }
    // Default: toggle a thumbs-up by the current user.
    final mine = _reactions[message.id]?.any(
      (r) => r.userId == widget.room.currentUserId && r.emoji == '👍',
    );
    if (mine ?? false) {
      widget.room.removeReaction(message.id, '👍');
    } else {
      widget.room.react(message.id, '👍');
    }
  }

  @override
  Widget build(BuildContext context) {
    final room = widget.room;
    return Column(
      children: [
        Expanded(
          child: StreamBuilder<List<Message>>(
            stream: room.messages,
            initialData: room.currentMessages,
            builder: (context, snapshot) {
              final messages = snapshot.data ?? const [];
              if (messages.isEmpty) {
                return const Center(child: Text('No messages yet'));
              }
              final byId = {for (final m in messages) m.id: m};
              return ListView.builder(
                controller: _scroll,
                reverse: true, // newest at the bottom, grows upward
                padding: const EdgeInsets.symmetric(vertical: 8),
                itemCount: messages.length,
                itemBuilder: (context, index) {
                  final message = messages[messages.length - 1 - index];
                  return MessageBubble(
                    message: message,
                    isMine: message.senderId == room.currentUserId,
                    repliedTo: message.replyToId == null
                        ? null
                        : byId[message.replyToId],
                    reactions: _reactions[message.id] ?? const [],
                    onLongPress: _handleLongPress,
                  );
                },
              );
            },
          ),
        ),
        StreamBuilder<List<String>>(
          stream: room.typingUserIds,
          initialData: const [],
          builder: (context, snapshot) => TypingIndicator(
            userIds: snapshot.data ?? const [],
            nameFor: widget.nameFor,
          ),
        ),
        MessageComposer(
          onSend: (text) => room.send(text: text),
          onTypingChanged: (typing) => room.setTyping(typing: typing),
        ),
      ],
    );
  }
}
