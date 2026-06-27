# supabase_chat example

Create a room, send an optimistic message, and listen to the live timeline.

```dart
import 'package:supabase/supabase.dart';
import 'package:supabase_chat/supabase_chat.dart';

Future<void> main() async {
  final client = SupabaseClient('https://YOUR.supabase.co', 'YOUR_ANON_KEY');
  await client.auth.signInAnonymously();
  final chat = SupabaseChat(client);

  // A 1:1 direct room (created/looked up idempotently).
  final result = await chat.directRoom('the-other-user-id');
  final room = switch (result) {
    Ok(:final value) => value,
    Err(:final error) => throw error,
  };

  room.messages.listen((messages) {
    for (final m in messages) {
      print('${m.senderId}: ${m.content}${m.pending ? ' (sending…)' : ''}');
    }
  });
  await room.join();

  await room.send(text: 'hey 👋');           // optimistic
  await room.setTyping(typing: true);        // typing indicator
  await room.react(someMessageId, '👍');     // reaction
  await room.markRead();                     // read receipt

  await room.leave();
}
```
