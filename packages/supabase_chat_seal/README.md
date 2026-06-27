# supabase_chat_seal

**Permissive (MIT) end-to-end encryption** for [`supabase_chat`](../supabase_chat) —
a sealed box over **X25519 ECDH → HKDF-SHA256 → AES-256-GCM**. The Supabase
server stores **only ciphertext**; plaintext never leaves the device.

This is the **closed-source-friendly** sibling of
[`supabase_chat_e2ee`](../supabase_chat_e2ee). Both give real E2EE with
safety-number verification; they differ in license and crypto:

| | `supabase_chat_seal` (this) | `supabase_chat_e2ee` |
|---|---|---|
| Crypto | X25519 ECDH + AES-256-GCM (sealed box) | Signal Protocol (X3DH + Double Ratchet) |
| Forward secrecy | ❌ static pairwise key | ✅ ratchets every message |
| Dependencies | `cryptography` (Apache-2.0), `crypto` (BSD-3) | `libsignal_protocol_dart` (**GPL-3.0**) |
| **Use in a closed-source app** | ✅ **yes** | ❌ no (GPL forces your app open-source) |

**Pick this package** if you ship a proprietary/closed-source app, or simply
want permissive licensing. **Pick `supabase_chat_e2ee`** if you need forward
secrecy and your app is GPL/open-source.

## Why the license matters

`supabase_chat_e2ee` depends on `libsignal_protocol_dart`, which is **GPL-3.0**.
Distributing a GPL-3.0 dependency (App Store / Play Store counts) requires
releasing your **whole app's** source under GPL. `supabase_chat_seal` depends
only on permissively licensed crypto, so it carries no such obligation.

## Security model

The server is treated as **untrusted**. Key distribution flows through it, so
the package hardens the classic weak point:

- **MITM protection — safety numbers.** Both parties compute the *same*
  60-digit `SafetyNumber` from their public keys; comparing it out of band
  (read aloud / QR) proves there is no man-in-the-middle. In the default
  **strict mode** (`requireVerified: true`), `send`/`encryptFor` refuse to
  encrypt to a peer until you've called `markVerified`.
- **Key-change rejection.** Once you trust a peer's key, any later change (a
  compromised server swapping in its own key) is rejected with
  `IdentityChangedException` until you re-verify and call
  `acceptIdentityChange`.
- **Authenticated encryption.** AES-256-GCM provides confidentiality **and**
  integrity (tampered ciphertext fails to decrypt).
- **Pluggable, persistable trust.** Persist your `SealIdentity`
  (`exportPrivateKey` + `publicKey`) and a `TrustStore` so identities, safety
  numbers and verifications survive restarts. No platform secure-storage is
  bundled — bring your own.

> Honest caveats: **no forward secrecy** — the pairwise key is static, so a
> leaked private key exposes past messages to/from that peer (use
> `supabase_chat_e2ee` if that matters). Metadata (sender, timestamps,
> membership, reactions) is not encrypted. Group E2EE and multi-device are not
> implemented; built for **1:1 / small direct rooms**.

## Setup

1. Apply `supabase/migrations/0003_e2ee_public_keys.sql` (adds the public
   `e2ee_public_keys` directory; reuses the `messages.encrypted` column from
   `0002`).
2. Generate an identity once per install, publish its public key, and persist
   the private key + trust store yourself.

```dart
import 'package:supabase_chat_seal/supabase_chat_seal.dart';

final identity = await SealIdentity.generate();        // once per install
final manager = SealManager(
  identity: identity,
  directory: SupabasePublicKeyDirectory(supabase),     // your SupabaseClient
  currentUserId: myUserId,
);
await manager.publishOwnKeys();
```

## Sending & receiving

Wrap a `ChatRoom` with `SealedChatRoom` — the API mirrors the plain room, but
`messages` yields `DecryptedMessage`s:

```dart
final room = await chat.directRoom(peerId);            // from supabase_chat
final secure = SealedChatRoom(
  room.value!,
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

Reactions, typing, presence and read receipts pass through unencrypted; only
message bodies are encrypted. To skip verification (trust-on-first-use only,
less safe), construct the manager with `requireVerified: false`.

## How it works

- **Identity** — `SealIdentity` is an X25519 key pair. The public key goes to a
  `PublicKeyDirectory` (`SupabasePublicKeyDirectory` / `InMemoryPublicKeyDirectory`).
- **Session** — `SealManager.ensureSession` derives the pairwise secret with
  `ECDH(myPrivate, peerPublic)`, then `HKDF-SHA256` → a 32-byte AES key. Both
  sides derive the **same** key (ECDH is symmetric).
- **Envelope** — each recipient's ciphertext is a `SealedEnvelope`
  (`{v, b}` where `b` = base64 of `nonce || ciphertext || mac`) stored under
  their user id in `messages.encrypted`.
- **Self-readback** — because the key is static and symmetric, the sender can
  re-derive it to read their own history; no plaintext cache is required for
  correctness.

## Testing

`dart test` runs a full two-party round-trip (ECDH handshake, multi-turn
conversation, self-readback, MITM rejection) against an in-memory directory —
no Supabase needed. A console walkthrough lives at `example/seal_demo.dart`:

```bash
dart run example/seal_demo.dart
```

## License

MIT
