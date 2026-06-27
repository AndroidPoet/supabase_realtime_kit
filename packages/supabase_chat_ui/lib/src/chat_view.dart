import 'package:flutter/material.dart';
import 'package:supabase_chat/supabase_chat.dart';
import 'package:supabase_chat_ui/src/message_bubble.dart';
import 'package:supabase_chat_ui/src/message_composer.dart';
import 'package:supabase_chat_ui/src/typing_indicator.dart';

/// A complete, drop-in chat screen body for a [ChatRoom].
///
/// Wire it up with three lines:
/// ```dart
/// Scaffold(
///   appBar: AppBar(title: const Text('general')),
///   body: ChatView(room: chat.room(roomId)),
/// );
/// ```
///
/// By default it joins the room on mount and leaves on dispose. Set
/// [manageLifecycle] to `false` if you call `join`/`leave` yourself.
class ChatView extends StatefulWidget {
  /// Creates a chat view bound to [room].
  const ChatView({
    required this.room,
    super.key,
    this.manageLifecycle = true,
    this.nameFor,
  });

  /// The room to display.
  final ChatRoom room;

  /// Whether this widget calls [ChatRoom.join]/[ChatRoom.leave] automatically.
  final bool manageLifecycle;

  /// Optional resolver from user id to display name (for typing indicator).
  final String Function(String userId)? nameFor;

  @override
  State<ChatView> createState() => _ChatViewState();
}

class _ChatViewState extends State<ChatView> {
  final ScrollController _scroll = ScrollController();

  @override
  void initState() {
    super.initState();
    if (widget.manageLifecycle) widget.room.join();
  }

  @override
  void dispose() {
    if (widget.manageLifecycle) widget.room.leave();
    _scroll.dispose();
    super.dispose();
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
