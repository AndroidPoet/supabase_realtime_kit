// A backend-free UI preview of the supabase_chat_ui widgets with mock data.
// Run with:  flutter run -t lib/preview.dart
//
// This bypasses Supabase entirely so you can see the chat UI (bubbles, replies,
// media, reactions, typing, composer) without any credentials.

import 'package:flutter/material.dart';
import 'package:supabase_chat/supabase_chat.dart';
import 'package:supabase_chat_ui/supabase_chat_ui.dart';

const _me = 'me';
const _alice = 'alice';

void main() => runApp(const PreviewApp());

/// Preview application root.
class PreviewApp extends StatelessWidget {
  /// Creates the preview app.
  const PreviewApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'supabase_chat UI preview',
      theme: ThemeData(
        colorSchemeSeed: const Color(0xFF4F46E5), // indigo
        useMaterial3: true,
      ),
      home: const PreviewScreen(),
    );
  }
}

/// A mock chat screen built from the library's building-block widgets.
class PreviewScreen extends StatelessWidget {
  /// Creates the preview screen.
  const PreviewScreen({super.key});

  DateTime _at(int minsAgo) =>
      DateTime.now().toUtc().subtract(Duration(minutes: minsAgo));

  @override
  Widget build(BuildContext context) {
    final greeting = Message(
      id: 'm1',
      roomId: 'r1',
      senderId: _alice,
      content: 'Hey! Are we still on for tonight? 🎉',
      createdAt: _at(32),
    );
    final messages = <Message>[
      greeting,
      Message(
        id: 'm2',
        roomId: 'r1',
        senderId: _me,
        content: 'Yeah! 7pm works for me',
        createdAt: _at(30),
      ),
      Message(
        id: 'm3',
        roomId: 'r1',
        senderId: _me,
        content: 'Looking forward to it 😄',
        replyToId: 'm1',
        createdAt: _at(29),
      ),
      Message(
        id: 'm4',
        roomId: 'r1',
        senderId: _alice,
        type: MessageType.image,
        content: 'Found this spot 👇',
        attachments: const [
          Attachment(
            path: 'r1/view.jpg',
            url: 'https://picsum.photos/id/1018/600/360',
            mimeType: 'image/jpeg',
          ),
        ],
        createdAt: _at(20),
      ),
      Message(
        id: 'm5',
        roomId: 'r1',
        senderId: _me,
        type: MessageType.file,
        attachments: const [
          Attachment(path: 'r1/itinerary.pdf', name: 'itinerary.pdf'),
        ],
        createdAt: _at(14),
      ),
      Message(
        id: 'm6',
        roomId: 'r1',
        senderId: _alice,
        content: 'This looks amazing, thank you!',
        createdAt: _at(9),
        editedAt: _at(8),
      ),
      Message(
        id: 'm7',
        roomId: 'r1',
        senderId: _me,
        content: 'oops wrong chat',
        createdAt: _at(6),
        deletedAt: _at(6),
      ),
    ];

    final byId = {for (final m in messages) m.id: m};
    final reactions = <String, List<Reaction>>{
      'm3': [
        Reaction(
          id: 'x1',
          messageId: 'm3',
          userId: _alice,
          emoji: '❤️',
          createdAt: _at(28),
        ),
      ],
      'm4': [
        Reaction(
          id: 'x2',
          messageId: 'm4',
          userId: _me,
          emoji: '👍',
          createdAt: _at(19),
        ),
        Reaction(
          id: 'x3',
          messageId: 'm4',
          userId: _alice,
          emoji: '🔥',
          createdAt: _at(18),
        ),
      ],
    };

    return Scaffold(
      appBar: AppBar(
        title: const Text('Alice'),
        actions: const [
          Icon(Icons.videocam_outlined),
          SizedBox(width: 16),
          Icon(Icons.call_outlined),
          SizedBox(width: 12),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: ListView(
              padding: const EdgeInsets.symmetric(vertical: 8),
              children: [
                for (final m in messages)
                  MessageBubble(
                    message: m,
                    isMine: m.senderId == _me,
                    repliedTo: m.replyToId == null ? null : byId[m.replyToId],
                    reactions: reactions[m.id] ?? const [],
                  ),
              ],
            ),
          ),
          const TypingIndicator(userIds: [_alice], nameFor: _nameFor),
          MessageComposer(onSend: (_) {}),
        ],
      ),
    );
  }
}

String _nameFor(String userId) => userId == _alice ? 'Alice' : userId;
