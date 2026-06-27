import 'dart:async';

import 'package:flutter/material.dart';
import 'package:supabase_chat/supabase_chat.dart';
import 'package:supabase_chat_e2ee/supabase_chat_e2ee.dart';
import 'package:supabase_chat_ui/src/message_bubble.dart';
import 'package:supabase_chat_ui/src/message_composer.dart';
import 'package:supabase_chat_ui/src/typing_indicator.dart';
import 'package:supabase_realtime_kit/supabase_realtime_kit.dart';

/// A drop-in chat screen body for an [EncryptedChatRoom].
///
/// Identical in spirit to `ChatView`, but bodies are end-to-end encrypted: it
/// renders [DecryptedMessage]s (showing a lock placeholder when a message can't
/// be decrypted), and shows a verification banner so the user can confirm the
/// peer's safety number before sending — required in the room's strict mode.
///
/// ```dart
/// Scaffold(
///   appBar: AppBar(title: const Text('Alice')),
///   body: EncryptedChatView(room: encryptedRoom),
/// );
/// ```
class EncryptedChatView extends StatefulWidget {
  /// Creates an encrypted chat view bound to [room].
  const EncryptedChatView({
    required this.room,
    super.key,
    this.manageLifecycle = true,
    this.peerLabel,
    this.nameFor,
  });

  /// The encrypted room to display.
  final EncryptedChatRoom room;

  /// Whether this widget calls [EncryptedChatRoom.join]/`leave` automatically.
  final bool manageLifecycle;

  /// A human label for the peer, shown in the verification banner.
  final String? peerLabel;

  /// Optional resolver from user id to display name (for typing indicator).
  final String Function(String userId)? nameFor;

  @override
  State<EncryptedChatView> createState() => _EncryptedChatViewState();
}

class _EncryptedChatViewState extends State<EncryptedChatView> {
  final ScrollController _scroll = ScrollController();
  StreamSubscription<Map<String, List<Reaction>>>? _reactionsSub;
  Map<String, List<Reaction>> _reactions = const {};

  bool _verified = false;
  String? _safetyNumber;
  bool _loadingTrust = true;

  @override
  void initState() {
    super.initState();
    if (widget.manageLifecycle) widget.room.join();
    _reactionsSub = widget.room.reactionsByMessage.listen((grouped) {
      if (mounted) setState(() => _reactions = grouped);
    });
    unawaited(_loadTrust());
  }

  @override
  void dispose() {
    _reactionsSub?.cancel();
    if (widget.manageLifecycle) widget.room.leave();
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _loadTrust() async {
    final verified = await widget.room.isVerified();
    final safety = verified
        ? null
        : (await widget.room.safetyNumber()).formatted;
    if (!mounted) return;
    setState(() {
      _verified = verified;
      _safetyNumber = safety;
      _loadingTrust = false;
    });
  }

  Future<void> _verify() async {
    await widget.room.markVerified();
    await _loadTrust();
  }

  Future<void> _send(String text) async {
    final messenger = ScaffoldMessenger.of(context);
    final result = await widget.room.send(text);
    if (result case Err(:final error)) {
      messenger.showSnackBar(SnackBar(content: Text(_describeError(error))));
    }
  }

  String _describeError(Object error) => switch (error) {
    UnverifiedRecipientException() =>
      'Verify ${widget.peerLabel ?? 'this contact'} before sending.',
    IdentityChangedException() =>
      'Security code changed — re-verify before sending.',
    _ => 'Message could not be sent.',
  };

  Message _displayMessage(DecryptedMessage dm) {
    final m = dm.message;
    final text =
        dm.plaintext ?? (dm.decryptFailed ? '🔒 Unable to decrypt' : '');
    return Message(
      id: m.id,
      roomId: m.roomId,
      senderId: m.senderId,
      createdAt: m.createdAt,
      content: text,
      replyToId: m.replyToId,
      editedAt: m.editedAt,
      deletedAt: m.deletedAt,
      pending: m.pending,
    );
  }

  @override
  Widget build(BuildContext context) {
    final room = widget.room;
    return Column(
      children: [
        EncryptedChatBanner(
          verified: _verified,
          loading: _loadingTrust,
          safetyNumber: _safetyNumber,
          peerLabel: widget.peerLabel,
          onVerify: _verify,
        ),
        Expanded(
          child: StreamBuilder<List<DecryptedMessage>>(
            stream: room.messages,
            builder: (context, snapshot) {
              final decrypted = snapshot.data ?? const <DecryptedMessage>[];
              if (decrypted.isEmpty) {
                return const Center(child: Text('No messages yet'));
              }
              final display = [for (final d in decrypted) _displayMessage(d)];
              final byId = {for (final m in display) m.id: m};
              return ListView.builder(
                controller: _scroll,
                reverse: true, // newest at the bottom, grows upward
                padding: const EdgeInsets.symmetric(vertical: 8),
                itemCount: display.length,
                itemBuilder: (context, index) {
                  final message = display[display.length - 1 - index];
                  return MessageBubble(
                    message: message,
                    isMine: message.senderId == room.currentUserId,
                    repliedTo: message.replyToId == null
                        ? null
                        : byId[message.replyToId],
                    reactions: _reactions[message.id] ?? const [],
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
          onSend: _send,
          onTypingChanged: (typing) => room.setTyping(typing: typing),
        ),
      ],
    );
  }
}

/// A header banner showing the end-to-end-encryption verification state.
///
/// When [verified] is false it shows the [safetyNumber] (to compare out of
/// band) and a "Verify" button; once verified it collapses to a slim
/// "verified" indicator. Purely presentational so it can be reused and tested
/// without an [EncryptedChatRoom].
class EncryptedChatBanner extends StatelessWidget {
  /// Creates a verification banner.
  const EncryptedChatBanner({
    required this.verified,
    required this.onVerify,
    super.key,
    this.loading = false,
    this.safetyNumber,
    this.peerLabel,
  });

  /// Whether the peer's identity has been verified.
  final bool verified;

  /// Whether trust state is still loading (renders a slim placeholder).
  final bool loading;

  /// The formatted safety number to compare out of band, when unverified.
  final String? safetyNumber;

  /// A human label for the peer.
  final String? peerLabel;

  /// Called when the user taps "Verify".
  final VoidCallback onVerify;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    if (loading) {
      return const SizedBox(height: 2, child: LinearProgressIndicator());
    }

    if (verified) {
      return Container(
        width: double.infinity,
        color: scheme.secondaryContainer,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.verified_user_rounded,
              size: 16,
              color: scheme.onSecondaryContainer,
            ),
            const SizedBox(width: 6),
            Text(
              'End-to-end encrypted · verified',
              style: TextStyle(
                color: scheme.onSecondaryContainer,
                fontSize: 12,
              ),
            ),
          ],
        ),
      );
    }

    final peer = peerLabel ?? 'this contact';
    return Container(
      width: double.infinity,
      color: scheme.surfaceContainerHighest,
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.lock_outline_rounded, size: 18, color: scheme.primary),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Verify $peer',
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
              ),
              FilledButton.tonal(
                onPressed: onVerify,
                child: const Text('Verify'),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            'Compare this security code on both devices, then tap Verify.',
            style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
          ),
          if (safetyNumber != null) ...[
            const SizedBox(height: 8),
            SelectableText(
              safetyNumber!,
              style: const TextStyle(
                fontFamily: 'monospace',
                fontSize: 13,
                letterSpacing: 0.5,
              ),
            ),
          ],
        ],
      ),
    );
  }
}
