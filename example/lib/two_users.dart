// Two-user demo: two independent Supabase clients (two anonymous users) share
// one room, rendered side by side, so you can watch every realtime status
// propagate live between them — presence (online), typing, send (sending/sent),
// and read receipts (unread badge clearing).
//
// Run with the same credentials as the single-user demo:
//   flutter run -t lib/two_users.dart \
//     --dart-define=SUPABASE_URL=https://xyz.supabase.co \
//     --dart-define=SUPABASE_ANON_KEY=ey...
//
// Requires supabase/migrations/0001_chat_schema.sql and anonymous sign-ins.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:supabase_chat/supabase_chat.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

const _supabaseUrl = String.fromEnvironment('SUPABASE_URL');
const _supabaseAnonKey = String.fromEnvironment('SUPABASE_ANON_KEY');

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const TwoUsersApp());
}

/// The two-user demo application root.
class TwoUsersApp extends StatelessWidget {
  /// Creates the app.
  const TwoUsersApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'supabase_chat — two users',
      theme: ThemeData(
        colorSchemeSeed: const Color(0xFF4F46E5), // indigo
        useMaterial3: true,
      ),
      home: const TwoUsersDemo(),
    );
  }
}

/// Boots two anonymous users into a shared room and shows both sides.
class TwoUsersDemo extends StatefulWidget {
  /// Creates the demo.
  const TwoUsersDemo({super.key});

  @override
  State<TwoUsersDemo> createState() => _TwoUsersDemoState();
}

class _TwoUsersDemoState extends State<TwoUsersDemo> {
  late final Future<_Pair> _pair = _boot();

  Future<_Pair> _boot() async {
    // Two INDEPENDENT clients → two distinct auth sessions / users.
    final clientA = SupabaseClient(_supabaseUrl, _supabaseAnonKey);
    final clientB = SupabaseClient(_supabaseUrl, _supabaseAnonKey);
    await clientA.auth.signInAnonymously();
    await clientB.auth.signInAnonymously();
    final idB = clientB.auth.currentUser!.id;

    final chatA = SupabaseChat(clientA);
    final chatB = SupabaseChat(clientB);

    // A opens a direct room with B; both then open it by id.
    final created = await chatA.directRoom(idB);
    final roomId = created.valueOrNull?.id;
    if (roomId == null) {
      throw StateError('Could not open the shared room');
    }

    final roomA = chatA.room(roomId);
    final roomB = chatB.room(roomId);
    await roomA.join();
    await roomB.join();

    return _Pair(
      clientA: clientA,
      clientB: clientB,
      roomA: roomA,
      roomB: roomB,
    );
  }

  @override
  void dispose() {
    _pair
      ..then((p) => p.roomA.leave())
      ..then((p) => p.roomB.leave());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Two users — live status')),
      body: FutureBuilder<_Pair>(
        future: _pair,
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return Center(child: Text('Error: ${snapshot.error}'));
          }
          final pair = snapshot.data;
          if (pair == null) {
            return const Center(child: CircularProgressIndicator());
          }
          final paneA = _UserPane(label: 'Alice', room: pair.roomA);
          final paneB = _UserPane(label: 'Bob', room: pair.roomB);
          // Side by side when wide, stacked when narrow.
          return LayoutBuilder(
            builder: (context, constraints) {
              if (constraints.maxWidth >= 720) {
                return Row(
                  children: [
                    Expanded(child: paneA),
                    const VerticalDivider(width: 1),
                    Expanded(child: paneB),
                  ],
                );
              }
              return Column(
                children: [
                  Expanded(child: paneA),
                  const Divider(height: 1),
                  Expanded(child: paneB),
                ],
              );
            },
          );
        },
      ),
    );
  }
}

/// Holds the two clients and rooms for disposal.
class _Pair {
  _Pair({
    required this.clientA,
    required this.clientB,
    required this.roomA,
    required this.roomB,
  });

  final SupabaseClient clientA;
  final SupabaseClient clientB;
  final ChatRoom roomA;
  final ChatRoom roomB;
}

/// One user's view: a status header (presence + unread), the message list with
/// per-message send status, a typing indicator, and a composer that broadcasts
/// typing. Auto-marks incoming messages read so the other pane's badge clears.
class _UserPane extends StatefulWidget {
  const _UserPane({required this.label, required this.room});

  final String label;
  final ChatRoom room;

  @override
  State<_UserPane> createState() => _UserPaneState();
}

class _UserPaneState extends State<_UserPane> {
  final _controller = TextEditingController();
  Timer? _typingStop;
  bool _typing = false;

  ChatRoom get _room => widget.room;

  @override
  void dispose() {
    _typingStop?.cancel();
    _controller.dispose();
    super.dispose();
  }

  void _onChanged(String _) {
    if (!_typing) {
      _typing = true;
      _room.setTyping(typing: true);
    }
    _typingStop?.cancel();
    _typingStop = Timer(const Duration(seconds: 2), _stopTyping);
  }

  void _stopTyping() {
    if (_typing) {
      _typing = false;
      _room.setTyping(typing: false);
    }
  }

  Future<void> _send() async {
    final text = _controller.text.trim();
    if (text.isEmpty) return;
    _controller.clear();
    _stopTyping();
    await _room.send(text: text);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      children: [
        _Header(label: widget.label, room: _room),
        const Divider(height: 1),
        Expanded(
          child: StreamBuilder<List<Message>>(
            stream: _room.messages,
            builder: (context, snapshot) {
              final messages = snapshot.data ?? const [];
              // Read receipt: as soon as this user sees messages, mark read so
              // the SENDER's pane shows its unread badge drop to zero.
              if (messages.isNotEmpty) {
                WidgetsBinding.instance.addPostFrameCallback(
                  (_) => _room.markRead(),
                );
              }
              if (messages.isEmpty) {
                return const Center(child: Text('No messages yet'));
              }
              return ListView.builder(
                reverse: true,
                padding: const EdgeInsets.all(12),
                itemCount: messages.length,
                itemBuilder: (context, i) {
                  final m = messages[messages.length - 1 - i];
                  return _Bubble(
                    message: m,
                    isMine: m.senderId == _room.currentUserId,
                  );
                },
              );
            },
          ),
        ),
        _TypingLine(room: _room),
        Padding(
          padding: const EdgeInsets.all(8),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _controller,
                  onChanged: _onChanged,
                  onSubmitted: (_) => _send(),
                  decoration: InputDecoration(
                    isDense: true,
                    hintText: 'Message as ${widget.label}',
                    border: const OutlineInputBorder(),
                  ),
                ),
              ),
              IconButton(
                icon: Icon(Icons.send, color: theme.colorScheme.primary),
                onPressed: _send,
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// Header: who this pane is, how many peers are online (presence), and how many
/// messages are unread for this user (read-receipt counter).
class _Header extends StatelessWidget {
  const _Header({required this.label, required this.room});

  final String label;
  final ChatRoom room;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      color: theme.colorScheme.surfaceContainerHighest,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      child: Row(
        children: [
          CircleAvatar(
            radius: 14,
            backgroundColor: theme.colorScheme.primary,
            child: Text(
              label.characters.first,
              style: TextStyle(color: theme.colorScheme.onPrimary),
            ),
          ),
          const SizedBox(width: 10),
          Text(label, style: theme.textTheme.titleMedium),
          const Spacer(),
          StreamBuilder<List<Map<String, dynamic>>>(
            stream: room.presentUsers,
            builder: (context, s) {
              final others = (s.data ?? const []).length;
              return _Chip(
                icon: Icons.circle,
                iconColor: others > 0 ? Colors.green : Colors.grey,
                label: '$others online',
              );
            },
          ),
          const SizedBox(width: 6),
          StreamBuilder<int>(
            stream: room.unreadCount,
            builder: (context, s) {
              final unread = s.data ?? 0;
              return _Chip(
                icon: Icons.mark_chat_unread,
                iconColor: unread > 0 ? theme.colorScheme.error : Colors.grey,
                label: '$unread unread',
              );
            },
          ),
        ],
      ),
    );
  }
}

/// "X is typing…" sourced from the room's typing stream.
class _TypingLine extends StatelessWidget {
  const _TypingLine({required this.room});

  final ChatRoom room;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<String>>(
      stream: room.typingUserIds,
      builder: (context, s) {
        final typing = s.data ?? const [];
        if (typing.isEmpty) return const SizedBox(height: 18);
        return Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 2),
          child: Text(
            'typing…',
            style: Theme.of(
              context,
            ).textTheme.bodySmall?.copyWith(fontStyle: FontStyle.italic),
          ),
        );
      },
    );
  }
}

/// A message bubble with a send-status indicator (sending vs sent).
class _Bubble extends StatelessWidget {
  const _Bubble({required this.message, required this.isMine});

  final Message message;
  final bool isMine;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final bg = isMine
        ? theme.colorScheme.primary
        : theme.colorScheme.surfaceContainerHighest;
    final fg = isMine
        ? theme.colorScheme.onPrimary
        : theme.colorScheme.onSurface;
    return Align(
      alignment: isMine ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 3),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        constraints: const BoxConstraints(maxWidth: 260),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(14),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(message.content ?? '', style: TextStyle(color: fg)),
            if (isMine)
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    message.pending ? Icons.schedule : Icons.check,
                    size: 13,
                    color: fg.withValues(alpha: 0.8),
                  ),
                  const SizedBox(width: 3),
                  Text(
                    message.pending ? 'sending…' : 'sent',
                    style: TextStyle(
                      fontSize: 10,
                      color: fg.withValues(alpha: 0.8),
                    ),
                  ),
                ],
              ),
          ],
        ),
      ),
    );
  }
}

/// A small status chip used in the header.
class _Chip extends StatelessWidget {
  const _Chip({
    required this.icon,
    required this.iconColor,
    required this.label,
  });

  final IconData icon;
  final Color iconColor;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 12, color: iconColor),
        const SizedBox(width: 4),
        Text(label, style: Theme.of(context).textTheme.labelSmall),
      ],
    );
  }
}
