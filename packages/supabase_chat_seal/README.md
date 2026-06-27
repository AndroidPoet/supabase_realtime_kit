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

## Device migration & key backup

The user's **identity private key is the "master key"** — there is no
server-side master key to recover from (that is the point of E2EE: the server
only ever holds public keys and ciphertext). What happens when a user gets a new
phone depends entirely on whether **you** carried that key over.

- **If you migrate the key** → the new device keeps the same public key, so
  **safety numbers stay stable, peers stay verified, and old ciphertext is still
  decryptable.** Seamless.
- **If you don't** (just call `SealIdentity.generate()` again) → a new identity
  is published, every peer sees the safety number change and gets an
  `IdentityChangedException` (the "security code changed" warning), and **all
  prior ciphertext on the server becomes permanently undecryptable.** Signal and
  WhatsApp behave the same way on an un-backed-up reinstall.

The migration primitives are built in (`SealIdentity.exportPrivateKey` /
`SealIdentity.restore`). This package bundles **no** storage or backup — that is
a product decision left to you. The recommended pattern is a **passphrase-
encrypted backup**: derive a key from a user passphrase and wrap the private key
with it, then store the blob anywhere (even server-side — it is opaque without
the passphrase).

```dart
import 'dart:convert';
import 'dart:typed_data';
import 'package:cryptography/cryptography.dart';
import 'package:supabase_chat_seal/supabase_chat_seal.dart';

// --- Back up (old device) ---
final raw = await identity.exportPrivateKey();            // 32 bytes
final kdf = Pbkdf2(macAlgorithm: Hmac.sha256(), iterations: 200000, bits: 256);
final wrapKey = await kdf.deriveKeyFromPassword(
  password: userPassphrase, nonce: salt /* 16 random bytes you store */);
final box = await AesGcm.with256bits().encrypt(raw, secretKey: wrapKey);
final blob = base64.encode([...box.nonce, ...box.cipherText, ...box.mac.bytes]);
// store `blob`, `salt`, and the public key wherever you like.

// --- Restore (new device) ---
final identity = await SealIdentity.restore(
  privateKey: recoveredRawKey,                            // unwrap `blob` with the passphrase
  publicKey: storedPublicKey,
);
```

## Forward secrecy & dynamic keys (what you can and can't get)

A common question: *can the key be dynamic, like WhatsApp?* The honest layering:

- You want a **stable identity key** (so safety numbers and verification survive)
  **+ dynamic message keys** (so a leaked key can't expose the whole history).
  Rotating the *identity* key itself only breaks everyone's verification.
- WhatsApp and Signal get dynamic message keys from the **Double Ratchet** — a
  fresh key per message, old keys deleted (forward secrecy + post-compromise
  security). That is what [`supabase_chat_e2ee`](../supabase_chat_e2ee) (GPL)
  provides via `libsignal`.
- **This package uses a static pairwise key — no ratchet, no forward secrecy.**
  The Double Ratchet is an algorithm, not a library, so an MIT clean-room
  implementation on top of the primitives here is *possible*, but shipping
  unaudited custom crypto is a deliberate non-goal for now.

**If you need WhatsApp-grade forward secrecy, use `supabase_chat_e2ee`.** If
permissive licensing matters more than forward secrecy, this package is the
right trade-off and the threat model above (untrusted server, MITM, key-swap)
still holds.

## What E2EE can't do (any package, not just this one)

These are fundamental to "the server only sees ciphertext" — forward secrecy or
not, no E2EE design escapes them:

| Want | Possible? | Why / what to do instead |
|---|---|---|
| Server-side search of message content | ❌ | the server can't index what it can't read |
| Server reading / moderating content | ❌ | plaintext never reaches the server |
| New device pulls full history from server | ⚠️ only with key migration | otherwise old ciphertext is undecryptable; use the encrypted backup above |
| **Local** chat export | ✅ | export the **decrypted plaintext your client already holds** (keep a local store), exactly like WhatsApp's "Export chat" |
| Metadata privacy (who/when/membership) | ❌ | only message bodies are encrypted |

The mental model: **E2EE protects keys; history/export features must live on the
plaintext side** — local device storage or an explicitly user-keyed encrypted
backup. Anything that needs the *server* to read content is off the table.

## Testing

`dart test` runs a full two-party round-trip (ECDH handshake, multi-turn
conversation, self-readback, MITM rejection) against an in-memory directory —
no Supabase needed. A console walkthrough lives at `example/seal_demo.dart`:

```bash
dart run example/seal_demo.dart
```

## License

MIT
