# supabase_chat_e2ee

[![pub package](https://img.shields.io/pub/v/supabase_chat_e2ee.svg)](https://pub.dev/packages/supabase_chat_e2ee) [![pub points](https://img.shields.io/pub/points/supabase_chat_e2ee.svg)](https://pub.dev/packages/supabase_chat_e2ee/score)

Opt-in **end-to-end encryption** for [`supabase_chat`](../supabase_chat),
built on the [Signal Protocol](https://signal.org/docs/) via
[`libsignal_protocol_dart`](https://pub.dev/packages/libsignal_protocol_dart).

> ## ⚠️ License: GPL-3.0 — you must open-source your app
>
> This package depends on `libsignal_protocol_dart`, which is licensed under
> **GPL-3.0**. GPL is *strong copyleft*: when you **distribute** an app that
> links it — and shipping to the App Store / Play Store counts as distribution —
> you must release your app's **complete source code** under GPL-3.0.
>
> Because shipping it is GPL-governed, **this package is licensed GPL-3.0** too
> (see `LICENSE`) so the obligation is explicit rather than hidden behind an
> MIT badge.
>
> | You are building… | Use |
> |---|---|
> | A **GPL / open-source** app | ✅ `supabase_chat_e2ee` (this package) |
> | A **closed-source / proprietary** app | ❌ this package → use [`supabase_chat_seal`](../supabase_chat_seal) instead (**MIT**, ECDH+AES-GCM, same API; no forward secrecy) |
>
> If you are not certain your project can comply with GPL-3.0, **do not use this
> package** — use `supabase_chat_seal`.

The Supabase server stores **only ciphertext**. Plaintext never leaves the
device: messages are encrypted per-recipient before insert and decrypted on
receive. Forward secrecy and post-compromise security come from Signal's
Double Ratchet.

## Security model

The server is treated as **untrusted**. Because key distribution flows through
it, the package hardens the two classic weak points:

- **MITM protection — safety numbers.** Both parties compute the *same*
  60-digit `SafetyNumber`; comparing it out of band (read aloud / QR) proves
  there is no man-in-the-middle. In the default **strict mode**
  (`requireVerified: true`), `send`/`encryptFor` refuse to encrypt to a peer
  until you've called `markVerified`.
- **Key-change rejection.** Once you trust a peer's identity key, any later
  change (a compromised server swapping in its own key) is rejected with
  `IdentityChangedException` — messaging stays blocked until you re-verify and
  call `acceptIdentityChange`.
- **No prekey reuse.** One-time prekeys are consumed **atomically server-side**
  (`claim_one_time_prekey` RPC + `SKIP LOCKED`), so a prekey is never handed
  out twice; the signed prekey is the fallback once the pool drains.
- **Stable, persistable identity.** Persist `exportIdentityKeyPair()` +
  `registrationId` + your `TrustStore` and use `E2eeIdentity.restore` so
  identities, safety numbers and verifications survive restarts.

> Honest caveats: `libsignal_protocol_dart` is a community port (not Signal's
> audited library); metadata (sender, timestamps, membership, reactions) is not
> encrypted; group E2EE (SenderKey) and multi-device are not yet implemented.

## Scope

- ✅ **1:1 / small direct rooms** — one ciphertext per recipient.
- ✅ Pluggable key store — bring your own persistence (OS keystore, encrypted
  file, SQLite…). This package never bundles platform secure-storage.
- ⏳ Large group rooms (Signal SenderKey fan-out) — not yet implemented.
- ⏳ Cross-device self-sync — the sender reads their own history from a local
  plaintext cache; multi-device would use a distinct device id.

## Setup

1. Apply `supabase/migrations/0002_e2ee_keys.sql` (adds the public `device_keys`
   directory and a `messages.encrypted` column, both RLS-guarded).
2. Generate an identity once per install, publish its public bundle, and
   **persist the store** so sessions survive restarts.

```dart
import 'package:supabase_chat_e2ee/supabase_chat_e2ee.dart';

// One-time per install (persist the store yourself afterwards).
final identity = await E2eeIdentity.generate();

final manager = E2eeManager(
  identity: identity,
  directory: SupabasePreKeyDirectory(supabase),
  currentUserId: myUserId,
);
await manager.publishOwnKeys();
```

## Sending & receiving

Wrap a `ChatRoom` with `EncryptedChatRoom` — the rest of the API mirrors the
plain room, but `messages` yields `DecryptedMessage`s:

```dart
final room = await chat.directRoom(peerId);          // from supabase_chat
final secure = EncryptedChatRoom(
  room.value,
  manager,
  recipientUserIds: [peerId],
);
await secure.join();

secure.messages.listen((items) {
  for (final m in items) {
    print(m.plaintext ?? (m.decryptFailed ? '🔒 (cannot decrypt)' : ''));
  }
});

// Strict mode (default): verify the peer before the first send.
final number = await secure.safetyNumber();   // 60 digits, same on both sides
print('Compare with $peerId: ${number.formatted}');
// …after the user confirms it matches on the other device:
await secure.markVerified();

final result = await secure.send('hello, end-to-end 🔐');
// result is Err(UnverifiedRecipientException) if you skip verification,
// or Err(IdentityChangedException) if the peer's key was swapped.
```

Reactions, typing, presence and read receipts pass through unencrypted (emoji
and presence are not secret); only message bodies are encrypted.

To skip verification (trust-on-first-use only, less safe), construct the
manager with `requireVerified: false`.

## How it works

- **Bundles** — `E2eeIdentity.publicBundle()` produces a `DeviceKeyBundle`
  (identity key, signed prekey + signature, one-time prekeys). Published to
  `device_keys` via a `PreKeyDirectory`.
- **Sessions** — `E2eeManager.ensureSession` fetches a peer's bundle and runs
  X3DH (`SessionBuilder.processPreKeyBundle`). The first message is a *prekey*
  message; once the peer replies, the ratchet switches to *whisper* messages.
- **Envelopes** — each recipient's ciphertext is a `CipherEnvelope`
  (`{t, b}` = type + base64 body) stored under their user id in
  `messages.encrypted`.

> ⚠️ A Signal ciphertext can be decrypted **once** (the ratchet advances).
> `EncryptedChatRoom` caches decrypted plaintext by client/message id so a
> message is never decrypted twice.

## Flutter UI (recipe)

`supabase_chat_widgets` is **MIT and does not depend on this package**, so it can't
ship a widget bound to the GPL `EncryptedChatRoom`. Drop this `EncryptedChatView`
into **your** app instead — combining the MIT widgets with this GPL package in
your (GPL) app is exactly the supported case. It reuses the presentational
`EncryptedChatBanner` from `supabase_chat_widgets` (no crypto dependency):

```dart
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:supabase_chat/supabase_chat.dart';
import 'package:supabase_chat_e2ee/supabase_chat_e2ee.dart';
import 'package:supabase_chat_widgets/supabase_chat_widgets.dart';

/// A drop-in chat screen body for an [EncryptedChatRoom].
class EncryptedChatView extends StatefulWidget {
  const EncryptedChatView({
    required this.room,
    super.key,
    this.manageLifecycle = true,
    this.peerLabel,
    this.nameFor,
  });

  final EncryptedChatRoom room;
  final bool manageLifecycle;
  final String? peerLabel;
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
    final safety =
        verified ? null : (await widget.room.safetyNumber()).formatted;
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
                reverse: true,
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
```

The same recipe works for `supabase_chat_seal` — swap `EncryptedChatRoom` for
`SealedChatRoom` and the import for `package:supabase_chat_seal/...`.

## Testing

`dart test` runs a full two-party round-trip (X3DH handshake, multi-turn
ratchet, failure cases) against an in-memory directory — no Supabase needed.

## License

GPL-3.0 (this package links `libsignal_protocol_dart`). See the warning at the
top — for closed-source apps use [`supabase_chat_seal`](../supabase_chat_seal)
(MIT).
