// Encrypted two-user demo: two anonymous users chat end-to-end encrypted, and a
// third "server view" panel shows the EXACT ciphertext stored in Supabase
// (messages.encrypted). The top panes show plaintext the humans see; the bottom
// panel shows what the database actually holds — proving the server never sees
// plaintext.
//
// Uses the permissive (MIT) supabase_chat_seal package (ECDH + AES-GCM).
//
//   flutter run -t lib/encrypted_two_users.dart \
//     --dart-define=SUPABASE_URL=https://xyz.supabase.co \
//     --dart-define=SUPABASE_ANON_KEY=ey...
//
// Requires migrations 0001_chat_schema.sql + 0003_e2ee_public_keys.sql and
// anonymous sign-ins enabled.
import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:supabase_chat/supabase_chat.dart';
import 'package:supabase_chat_seal/supabase_chat_seal.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

const _supabaseUrl = String.fromEnvironment('SUPABASE_URL');
const _supabaseAnonKey = String.fromEnvironment('SUPABASE_ANON_KEY');

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const EncryptedTwoUsersApp());
}

/// The encrypted two-user demo application root.
class EncryptedTwoUsersApp extends StatelessWidget {
  /// Creates the app.
  const EncryptedTwoUsersApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'supabase_chat — encrypted two users',
      theme: ThemeData(
        colorSchemeSeed: const Color(0xFF0EA5A4), // teal
        useMaterial3: true,
      ),
      home: const EncryptedTwoUsersDemo(),
    );
  }
}

/// Boots two encrypted users into a shared room and shows both sides plus the
/// server's ciphertext view.
class EncryptedTwoUsersDemo extends StatefulWidget {
  /// Creates the demo.
  const EncryptedTwoUsersDemo({super.key});

  @override
  State<EncryptedTwoUsersDemo> createState() => _EncryptedTwoUsersDemoState();
}

class _EncryptedTwoUsersDemoState extends State<EncryptedTwoUsersDemo> {
  late final Future<_Secure> _secure = _boot();

  Future<_Secure> _boot() async {
    // Two INDEPENDENT clients → two distinct users.
    final clientA = SupabaseClient(_supabaseUrl, _supabaseAnonKey);
    final clientB = SupabaseClient(_supabaseUrl, _supabaseAnonKey);
    await clientA.auth.signInAnonymously();
    await clientB.auth.signInAnonymously();
    final idA = clientA.auth.currentUser!.id;
    final idB = clientB.auth.currentUser!.id;

    final chatA = SupabaseChat(clientA);
    final chatB = SupabaseChat(clientB);

    // Each user gets an identity + manager and publishes its public key.
    final mgrA = SealManager(
      identity: await SealIdentity.generate(),
      directory: SupabasePublicKeyDirectory(clientA),
      currentUserId: idA,
    );
    final mgrB = SealManager(
      identity: await SealIdentity.generate(),
      directory: SupabasePublicKeyDirectory(clientB),
      currentUserId: idB,
    );
    await mgrA.publishOwnKeys();
    await mgrB.publishOwnKeys();

    // A opens a direct room with B; both wrap it in a SealedChatRoom.
    final created = await chatA.directRoom(idB);
    final roomId = created.valueOrNull?.id;
    if (roomId == null) {
      throw StateError('Could not open the shared room');
    }

    final secureA = SealedChatRoom(
      chatA.room(roomId),
      mgrA,
      recipientUserIds: [idB],
    );
    final secureB = SealedChatRoom(
      chatB.room(roomId),
      mgrB,
      recipientUserIds: [idA],
    );
    await secureA.join();
    await secureB.join();

    // Verify both ways so strict mode lets sends through.
    final number = await secureA.safetyNumber();
    await secureB.safetyNumber();
    await secureA.markVerified();
    await secureB.markVerified();

    return _Secure(
      clientA: clientA,
      clientB: clientB,
      secureA: secureA,
      secureB: secureB,
      safetyNumber: number.formatted,
    );
  }

  @override
  void dispose() {
    _secure
      ..then((s) => s.secureA.leave())
      ..then((s) => s.secureB.leave());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Encrypted chat — server sees ciphertext'),
      ),
      body: FutureBuilder<_Secure>(
        future: _secure,
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return Center(child: Text('Error: ${snapshot.error}'));
          }
          final s = snapshot.data;
          if (s == null) {
            return const Center(child: CircularProgressIndicator());
          }
          return Column(
            children: [
              Expanded(flex: 3, child: _twoPanes(s)),
              const Divider(height: 1),
              // The honest part: what Supabase actually stores.
              Expanded(flex: 2, child: _ServerView(room: s.secureA.raw)),
            ],
          );
        },
      ),
    );
  }

  Widget _twoPanes(_Secure s) {
    final paneA = _SecurePane(
      label: 'Alice',
      room: s.secureA,
      safetyNumber: s.safetyNumber,
    );
    final paneB = _SecurePane(
      label: 'Bob',
      room: s.secureB,
      safetyNumber: s.safetyNumber,
    );
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
  }
}

/// Holds the two clients and encrypted rooms for disposal.
class _Secure {
  _Secure({
    required this.clientA,
    required this.clientB,
    required this.secureA,
    required this.secureB,
    required this.safetyNumber,
  });

  final SupabaseClient clientA;
  final SupabaseClient clientB;
  final SealedChatRoom secureA;
  final SealedChatRoom secureB;
  final String safetyNumber;
}

/// One user's encrypted view: header (verified + presence), the decrypted
/// message list, a typing indicator, and a composer.
class _SecurePane extends StatefulWidget {
  const _SecurePane({
    required this.label,
    required this.room,
    required this.safetyNumber,
  });

  final String label;
  final SealedChatRoom room;
  final String safetyNumber;

  @override
  State<_SecurePane> createState() => _SecurePaneState();
}

class _SecurePaneState extends State<_SecurePane> {
  final _controller = TextEditingController();
  Timer? _typingStop;
  bool _typing = false;

  SealedChatRoom get _room => widget.room;

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
    await _room.send(text);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      children: [
        _SecureHeader(
          label: widget.label,
          room: _room,
          safetyNumber: widget.safetyNumber,
        ),
        const Divider(height: 1),
        Expanded(
          child: StreamBuilder<List<DecryptedMessage>>(
            stream: _room.messages,
            builder: (context, snapshot) {
              final messages = snapshot.data ?? const [];
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
                  return _PlainBubble(
                    message: m,
                    isMine: m.message.senderId == _room.currentUserId,
                  );
                },
              );
            },
          ),
        ),
        _TypingLine(stream: _room.typingUserIds),
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
                    hintText: 'Encrypt & send as ${widget.label}',
                    border: const OutlineInputBorder(),
                  ),
                ),
              ),
              IconButton(
                icon: Icon(Icons.lock, color: theme.colorScheme.primary),
                onPressed: _send,
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// Header: who this pane is, the verified safety number, and presence.
class _SecureHeader extends StatelessWidget {
  const _SecureHeader({
    required this.label,
    required this.room,
    required this.safetyNumber,
  });

  final String label;
  final SealedChatRoom room;
  final String safetyNumber;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      color: theme.colorScheme.surfaceContainerHighest,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
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
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(label, style: theme.textTheme.titleSmall),
              Text(
                '🔒 ${safetyNumber.substring(0, 17)}…',
                style: theme.textTheme.labelSmall,
              ),
            ],
          ),
          const Spacer(),
          const Icon(Icons.verified_user, size: 14, color: Colors.green),
          const SizedBox(width: 4),
          StreamBuilder<List<Map<String, dynamic>>>(
            stream: room.presentUsers,
            builder: (context, s) {
              final others = (s.data ?? const []).length;
              return Text('$others online', style: theme.textTheme.labelSmall);
            },
          ),
        ],
      ),
    );
  }
}

/// "typing…" line.
class _TypingLine extends StatelessWidget {
  const _TypingLine({required this.stream});

  final Stream<List<String>> stream;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<String>>(
      stream: stream,
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

/// A decrypted message bubble (what the human reads).
class _PlainBubble extends StatelessWidget {
  const _PlainBubble({required this.message, required this.isMine});

  final DecryptedMessage message;
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
    final text =
        message.plaintext ??
        (message.decryptFailed ? '🔒 (cannot decrypt)' : '');
    return Align(
      alignment: isMine ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 3),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        constraints: const BoxConstraints(maxWidth: 240),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(14),
        ),
        child: Text(text, style: TextStyle(color: fg)),
      ),
    );
  }
}

/// The server's-eye view: streams the raw room rows and renders only the
/// ciphertext stored in `messages.encrypted`. This is exactly what Supabase
/// holds — no plaintext anywhere.
class _ServerView extends StatelessWidget {
  const _ServerView({required this.room});

  final ChatRoom room;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ColoredBox(
      color: const Color(0xFF0B1021),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 6),
            child: Row(
              children: [
                const Icon(Icons.storage, size: 16, color: Colors.white70),
                const SizedBox(width: 8),
                Text(
                  'Supabase · messages.encrypted (server only ever sees this)',
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: Colors.white70,
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: StreamBuilder<List<Message>>(
              stream: room.messages,
              builder: (context, snapshot) {
                final rows = snapshot.data ?? const [];
                if (rows.isEmpty) {
                  return const Center(
                    child: Text(
                      'No rows yet',
                      style: TextStyle(color: Colors.white38),
                    ),
                  );
                }
                return ListView.builder(
                  reverse: true,
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  itemCount: rows.length,
                  itemBuilder: (context, i) {
                    final m = rows[rows.length - 1 - i];
                    return _CipherRow(message: m);
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

/// One DB row rendered as the ciphertext blob(s) it stores.
class _CipherRow extends StatelessWidget {
  const _CipherRow({required this.message});

  final Message message;

  @override
  Widget build(BuildContext context) {
    final encrypted = message.extra['encrypted'];
    final sender = message.senderId.substring(0, 6);
    final String body;
    if (encrypted is Map) {
      // {recipientId: {v, b}} — show each recipient's base64 ciphertext.
      body = encrypted.entries
          .map((e) {
            final blob = (e.value as Map)['b'] as String? ?? '';
            final shown = blob.length > 56 ? '${blob.substring(0, 56)}…' : blob;
            return '${(e.key as String).substring(0, 6)}→ $shown';
          })
          .join('\n');
    } else {
      body = jsonEncode(message.content); // would be plaintext if NOT encrypted
    }
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'from $sender  •  ${message.pending ? 'pending' : 'stored'}',
            style: const TextStyle(color: Colors.white38, fontSize: 10),
          ),
          Text(
            body,
            style: const TextStyle(
              color: Color(0xFF7DD3FC),
              fontFamily: 'monospace',
              fontSize: 11,
            ),
          ),
        ],
      ),
    );
  }
}
