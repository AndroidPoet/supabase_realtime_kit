// Single-user encrypted chat — one user per device, for running on two
// emulators. Each device signs in as its own anonymous user, publishes its
// public key, and chats end-to-end encrypted (permissive supabase_chat_seal).
// A collapsible panel shows the exact ciphertext stored in Supabase.
//
// Handshake (no open-join in the API, so we pair explicitly):
//   1. Both devices launch and show "My ID" (tap to copy).
//   2. On device A: paste B's ID, tap "Create & invite".
//   3. On device B: paste A's ID, tap "Join" (finds the room A just created).
//
//   flutter run -t lib/encrypted_device.dart -d <device-id> \
//     --dart-define=SUPABASE_URL=https://xyz.supabase.co \
//     --dart-define=SUPABASE_ANON_KEY=ey...
//
// Requires migrations 0001_chat_schema.sql + 0003_e2ee_public_keys.sql and
// anonymous sign-ins enabled.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_chat/supabase_chat.dart';
import 'package:supabase_chat_seal/supabase_chat_seal.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

const _supabaseUrl = String.fromEnvironment('SUPABASE_URL');
const _supabaseAnonKey = String.fromEnvironment('SUPABASE_ANON_KEY');

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const EncryptedDeviceApp());
}

/// The per-device encrypted chat app root.
class EncryptedDeviceApp extends StatelessWidget {
  /// Creates the app.
  const EncryptedDeviceApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Encrypted chat (device)',
      theme: ThemeData(
        colorSchemeSeed: const Color(0xFF0EA5A4), // teal
        useMaterial3: true,
      ),
      home: const _Boot(),
    );
  }
}

/// Signs in, builds the manager, and shows the pairing screen.
class _Boot extends StatefulWidget {
  const _Boot();

  @override
  State<_Boot> createState() => _BootState();
}

class _BootState extends State<_Boot> {
  late final Future<_Session> _session = _start();

  Future<_Session> _start() async {
    final client = SupabaseClient(_supabaseUrl, _supabaseAnonKey);
    await client.auth.signInAnonymously();
    final myId = client.auth.currentUser!.id;
    final chat = SupabaseChat(client);
    final manager = SealManager(
      identity: await SealIdentity.generate(),
      directory: SupabasePublicKeyDirectory(client),
      currentUserId: myId,
    );
    await manager.publishOwnKeys();
    return _Session(client: client, chat: chat, manager: manager, myId: myId);
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<_Session>(
      future: _session,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return Scaffold(
            body: Center(child: Text('Error: ${snapshot.error}')),
          );
        }
        final session = snapshot.data;
        if (session == null) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }
        return _PairScreen(session: session);
      },
    );
  }
}

/// Per-device session state.
class _Session {
  _Session({
    required this.client,
    required this.chat,
    required this.manager,
    required this.myId,
  });

  final SupabaseClient client;
  final SupabaseChat chat;
  final SealManager manager;
  final String myId;
}

/// Pairing: show my id, take the peer id, then create or join the room.
class _PairScreen extends StatefulWidget {
  const _PairScreen({required this.session});

  final _Session session;

  @override
  State<_PairScreen> createState() => _PairScreenState();
}

class _PairScreenState extends State<_PairScreen> {
  final _peerController = TextEditingController();
  String? _status;
  bool _busy = false;

  _Session get _s => widget.session;

  @override
  void dispose() {
    _peerController.dispose();
    super.dispose();
  }

  Future<void> _create() async {
    final peerId = _peerController.text.trim();
    if (peerId.isEmpty) {
      setState(() => _status = 'Paste the other device’s ID first');
      return;
    }
    setState(() {
      _busy = true;
      _status = 'Creating room…';
    });
    final created = await _s.chat.directRoom(peerId);
    final roomId = created.valueOrNull?.id;
    if (roomId == null) {
      setState(() {
        _busy = false;
        _status = 'Could not create room';
      });
      return;
    }
    await _open(roomId: roomId, peerId: peerId);
  }

  Future<void> _join() async {
    final peerId = _peerController.text.trim();
    if (peerId.isEmpty) {
      setState(() => _status = 'Paste the other device’s ID first');
      return;
    }
    setState(() {
      _busy = true;
      _status = 'Looking for the invite…';
    });
    // The creator added us as a member, so the room shows up in myRooms.
    final rooms = (await _s.chat.myRooms()).valueOr(const []);
    final direct = rooms.where((r) => r.isDirect).toList();
    if (direct.isEmpty) {
      setState(() {
        _busy = false;
        _status = 'No invite yet — create on the other device first.';
      });
      return;
    }
    await _open(roomId: direct.first.id, peerId: peerId);
  }

  Future<void> _open({required String roomId, required String peerId}) async {
    final secure = SealedChatRoom(
      _s.chat.room(roomId),
      _s.manager,
      recipientUserIds: [peerId],
    );
    await secure.join();
    // Auto-verify for the demo (safety numbers match on both sides).
    await secure.safetyNumber();
    await secure.markVerified();
    if (!mounted) return;
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => _ChatScreen(session: _s, room: secure),
      ),
    );
    if (mounted) setState(() => _busy = false);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Pair the two devices')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('My ID (tap to copy)', style: theme.textTheme.labelLarge),
            const SizedBox(height: 4),
            InkWell(
              onTap: () {
                Clipboard.setData(ClipboardData(text: _s.myId));
                ScaffoldMessenger.of(
                  context,
                ).showSnackBar(const SnackBar(content: Text('Copied my ID')));
              },
              child: Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: theme.colorScheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: SelectableText(
                  _s.myId,
                  style: const TextStyle(fontFamily: 'monospace'),
                ),
              ),
            ),
            const SizedBox(height: 24),
            TextField(
              controller: _peerController,
              decoration: const InputDecoration(
                labelText: 'Other device’s ID',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: _busy ? null : _create,
              icon: const Icon(Icons.add_link),
              label: const Text('① Create & invite  (press on ONE phone)'),
            ),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: _busy ? null : _join,
              icon: const Icon(Icons.login),
              label: const Text('② Join  (press on the OTHER phone)'),
            ),
            const SizedBox(height: 16),
            if (_status != null)
              Text(_status!, style: theme.textTheme.bodySmall),
          ],
        ),
      ),
    );
  }
}

/// The encrypted chat for this device, with a collapsible server-ciphertext
/// panel showing what Supabase stores.
class _ChatScreen extends StatefulWidget {
  const _ChatScreen({required this.session, required this.room});

  final _Session session;
  final SealedChatRoom room;

  @override
  State<_ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<_ChatScreen> {
  final _controller = TextEditingController();
  Timer? _typingStop;
  bool _typing = false;
  bool _showServer = false;

  SealedChatRoom get _room => widget.room;

  @override
  void dispose() {
    _typingStop?.cancel();
    _controller.dispose();
    _room.leave();
    super.dispose();
  }

  void _onChanged(String _) {
    if (!_typing) {
      _typing = true;
      _room.setTyping(typing: true);
    }
    _typingStop?.cancel();
    _typingStop = Timer(const Duration(seconds: 2), () {
      _typing = false;
      _room.setTyping(typing: false);
    });
  }

  Future<void> _send() async {
    final text = _controller.text.trim();
    if (text.isEmpty) return;
    _controller.clear();
    await _room.send(text);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: const Text('🔒 Encrypted chat'),
        actions: [
          IconButton(
            tooltip: 'Show what Supabase stores',
            icon: Icon(_showServer ? Icons.storage : Icons.storage_outlined),
            onPressed: () => setState(() => _showServer = !_showServer),
          ),
        ],
      ),
      body: Column(
        children: [
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
                  return const Center(child: Text('Say hello 🔐'));
                }
                return ListView.builder(
                  reverse: true,
                  padding: const EdgeInsets.all(12),
                  itemCount: messages.length,
                  itemBuilder: (context, i) {
                    final m = messages[messages.length - 1 - i];
                    return _Bubble(
                      message: m,
                      isMine: m.message.senderId == _room.currentUserId,
                    );
                  },
                );
              },
            ),
          ),
          StreamBuilder<List<String>>(
            stream: _room.typingUserIds,
            builder: (context, s) {
              final typing = s.data ?? const [];
              return SizedBox(
                height: 18,
                child: typing.isEmpty
                    ? null
                    : Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 14),
                        child: Text(
                          'typing…',
                          style: theme.textTheme.bodySmall?.copyWith(
                            fontStyle: FontStyle.italic,
                          ),
                        ),
                      ),
              );
            },
          ),
          if (_showServer) _ServerStrip(room: _room.raw),
          Padding(
            padding: const EdgeInsets.all(8),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _controller,
                    onChanged: _onChanged,
                    onSubmitted: (_) => _send(),
                    decoration: const InputDecoration(
                      isDense: true,
                      hintText: 'Type a secret…',
                      border: OutlineInputBorder(),
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
      ),
    );
  }
}

/// A compact strip showing the raw ciphertext rows Supabase holds.
class _ServerStrip extends StatelessWidget {
  const _ServerStrip({required this.room});

  final ChatRoom room;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 110,
      width: double.infinity,
      color: const Color(0xFF0B1021),
      padding: const EdgeInsets.all(8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            '🗄 Supabase · messages.encrypted',
            style: TextStyle(color: Colors.white70, fontSize: 11),
          ),
          const SizedBox(height: 4),
          Expanded(
            child: StreamBuilder<List<Message>>(
              stream: room.messages,
              builder: (context, s) {
                final rows = s.data ?? const [];
                if (rows.isEmpty) {
                  return const Text(
                    'no rows yet',
                    style: TextStyle(color: Colors.white38, fontSize: 11),
                  );
                }
                return ListView(
                  reverse: true,
                  children: [for (final m in rows.reversed) _cipher(m)],
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _cipher(Message m) {
    final enc = m.extra['encrypted'];
    final text = enc is Map
        ? enc.entries
              .map((e) {
                final blob = (e.value as Map)['b'] as String? ?? '';
                final shown = blob.length > 48
                    ? '${blob.substring(0, 48)}…'
                    : blob;
                return shown;
              })
              .join(' ')
        : '${m.content}';
    return Text(
      text,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: const TextStyle(
        color: Color(0xFF7DD3FC),
        fontFamily: 'monospace',
        fontSize: 11,
      ),
    );
  }
}

/// A decrypted message bubble.
class _Bubble extends StatelessWidget {
  const _Bubble({required this.message, required this.isMine});

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
        constraints: const BoxConstraints(maxWidth: 280),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(14),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(text, style: TextStyle(color: fg)),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  message.pending ? Icons.schedule : Icons.check,
                  size: 12,
                  color: fg.withValues(alpha: 0.7),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
