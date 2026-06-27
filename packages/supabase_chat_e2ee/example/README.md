# supabase_chat_e2ee example

End-to-end encrypt a 1:1 room: verify the peer, then send. The server only ever
sees ciphertext.

```dart
import 'package:supabase_chat/supabase_chat.dart';
import 'package:supabase_chat_e2ee/supabase_chat_e2ee.dart';

Future<void> main() async {
  // One-time per install (persist the store + bundle yourself afterwards).
  final identity = await E2eeIdentity.generate();

  final manager = E2eeManager(
    identity: identity,
    directory: SupabasePreKeyDirectory(supabase), // your SupabaseClient
    currentUserId: myUserId,
  );
  await manager.publishOwnKeys();

  // Wrap a ChatRoom from supabase_chat.
  final secure = EncryptedChatRoom(
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
