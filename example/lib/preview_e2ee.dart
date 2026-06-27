// A backend-free preview of end-to-end-encrypted chat. Run with:
//   flutter run -t lib/preview_e2ee.dart
//
// No Supabase, no network. Two in-memory Signal identities (Alice & Bob) share
// an InMemoryPreKeyDirectory and *actually* encrypt/decrypt every message, so
// you can see the real flow: compare the safety number, verify, then send a
// message that is encrypted, round-trips through Bob, and renders decrypted.

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:supabase_chat/supabase_chat.dart';
import 'package:supabase_chat_e2ee/supabase_chat_e2ee.dart';
import 'package:supabase_chat_ui/supabase_chat_ui.dart';

const _alice = 'alice';
const _bob = 'bob';

void main() => runApp(const E2eePreviewApp());

/// Preview application root.
class E2eePreviewApp extends StatelessWidget {
  /// Creates the preview app.
  const E2eePreviewApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'supabase_chat_e2ee preview',
      theme: ThemeData(
        colorSchemeSeed: const Color(0xFF4F46E5), // indigo
        useMaterial3: true,
      ),
      home: const E2eePreviewScreen(),
    );
  }
}

/// A two-party encrypted conversation driven entirely on-device.
class E2eePreviewScreen extends StatefulWidget {
  /// Creates the preview screen.
  const E2eePreviewScreen({super.key});

  @override
  State<E2eePreviewScreen> createState() => _E2eePreviewScreenState();
}

class _E2eePreviewScreenState extends State<E2eePreviewScreen> {
  late final E2eeManager _aliceMgr;
  late final E2eeManager _bobMgr;

  bool _ready = false;
  bool _verified = false;
  String? _safetyNumber;
  String? _lastCiphertext;
  final List<Message> _messages = [];
  int _seq = 0;

  @override
  void initState() {
    super.initState();
    _setup();
  }

  Future<void> _setup() async {
    final directory = InMemoryPreKeyDirectory();
    final aliceId = await E2eeIdentity.generate(preKeyCount: 5);
    final bobId = await E2eeIdentity.generate(preKeyCount: 5);

    _aliceMgr = E2eeManager(
      identity: aliceId,
      directory: directory,
      currentUserId: _alice,
    );
    _bobMgr = E2eeManager(
      identity: bobId,
      directory: directory,
      currentUserId: _bob,
    );

    await _aliceMgr.publishOwnKeys();
    await _bobMgr.publishOwnKeys();

    final safety = await _aliceMgr.safetyNumber(_bob);
    if (!mounted) return;
    setState(() {
      _safetyNumber = safety.formatted;
      _ready = true;
    });
  }

  Future<void> _verify() async {
    await _aliceMgr.markVerified(_bob);
    await _bobMgr.markVerified(_alice);
    if (!mounted) return;
    setState(() => _verified = true);
  }

  DateTime _now() => DateTime.now().toUtc();

  void _append(String senderId, String text) {
    _messages.add(
      Message(
        id: 'm${_seq++}',
        roomId: 'preview',
        senderId: senderId,
        content: text,
        createdAt: _now(),
      ),
    );
  }

  Future<void> _send(String text) async {
    final messenger = ScaffoldMessenger.of(context);
    if (!_verified) {
      messenger.showSnackBar(
        const SnackBar(content: Text('Verify the safety number first.')),
      );
      return;
    }

    // 1. Alice encrypts for Bob. This map is all the "server" would ever see.
    final envelopes = await _aliceMgr.encryptFor([_bob], text);
    final forBob = Map<String, dynamic>.from(envelopes[_bob] as Map);
    final cipher = forBob['b'] as String;

    // 2. Bob receives the ciphertext and decrypts it — the round-trip.
    final bobReads = await _bobMgr.decrypt(forBob, _alice);

    // 3. Bob replies, encrypted; Alice decrypts it back.
    final reply = 'Got it: "$bobReads" 🔐';
    final replyEnvelopes = await _bobMgr.encryptFor([_alice], reply);
    final forAlice = Map<String, dynamic>.from(replyEnvelopes[_alice] as Map);
    final aliceReads = await _aliceMgr.decrypt(forAlice, _bob);

    if (!mounted) return;
    setState(() {
      _append(_alice, text);
      _append(_bob, aliceReads);
      _lastCiphertext = cipher;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (!_ready) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Bob'),
        actions: const [Icon(Icons.lock_rounded), SizedBox(width: 16)],
      ),
      body: Column(
        children: [
          EncryptedChatBanner(
            verified: _verified,
            safetyNumber: _safetyNumber,
            peerLabel: 'Bob',
            onVerify: _verify,
          ),
          Expanded(
            child: _messages.isEmpty
                ? const Center(child: Text('Say hello — encrypted 🔐'))
                : ListView(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    children: [
                      for (final m in _messages)
                        MessageBubble(message: m, isMine: m.senderId == _alice),
                    ],
                  ),
          ),
          if (_lastCiphertext != null)
            Container(
              width: double.infinity,
              color: scheme.surfaceContainerHighest,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
              child: Text(
                'Server only sees: ${_preview(_lastCiphertext!)}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontFamily: 'monospace',
                  fontSize: 11,
                  color: scheme.onSurfaceVariant,
                ),
              ),
            ),
          MessageComposer(onSend: _send),
        ],
      ),
    );
  }

  String _preview(String base64Body) {
    final bytes = base64Decode(base64Body);
    final hex = bytes
        .take(16)
        .map((b) => b.toRadixString(16).padLeft(2, '0'))
        .join();
    return '$hex… (${bytes.length} bytes)';
  }
}
