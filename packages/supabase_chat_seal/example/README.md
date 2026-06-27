# supabase_chat_seal example

Permissively-licensed (MIT) end-to-end encryption for a 1:1 room: verify the
peer, then send. The server only ever sees ciphertext.

```dart
import 'package:supabase_chat/supabase_chat.dart';
import 'package:supabase_chat_seal/supabase_chat_seal.dart';

Future<void> main() async {
  // One-time per install (persist the private key + trust store yourself).
  final identity = await SealIdentity.generate();

  final manager = SealManager(
    identity: identity,
    directory: SupabasePublicKeyDirectory(supabase), // your SupabaseClient
    currentUserId: myUserId,
  );
  await manager.publishOwnKeys();

  // Wrap a ChatRoom from supabase_chat.
  final secure = SealedChatRoom(
    chatRoom,
    manager,
    recipientUserIds: [peerUserId],
  );
  await secure.join();

  secure.messages.listen((items) {
    for (final m in items) {
      print(m.plaintext ?? (m.decryptFailed ? '🔒 (cannot decrypt)' : ''));
    }
  });

  // Strict mode (default): verify the peer before the first send.
  final number = await secure.safetyNumber();      // same 60 digits on both sides
  // …after the user confirms it matches out of band:
  await secure.markVerified();

  await secure.send('hello, end-to-end 🔐');
}
```

A complete, backend-free console walkthrough lives at `seal_demo.dart`:

```bash
dart run example/seal_demo.dart
```
