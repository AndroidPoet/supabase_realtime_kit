# supabase_chat

A plug-and-play chat domain on top of [`supabase_realtime_kit`](../supabase_realtime_kit). Rooms, messages with optimistic send, typing indicators, presence, and read receipts — over Supabase Postgres + Realtime.

## Setup

1. Apply the schema in [`supabase/migrations/0001_chat_schema.sql`](../../supabase/migrations/0001_chat_schema.sql) (tables, RLS policies, realtime publication).
2. Add the dependency:

```yaml
dependencies:
  supabase_chat: ^0.1.0
```

## Usage

```dart
import 'package:supabase_chat/supabase_chat.dart';

final chat = SupabaseChat(supabaseClient); // user must be signed in

// Create a room with another member.
final created = await chat.createRoom(name: 'general', memberIds: [bobId]);
final roomId = created.valueOrNull!.id;

// Open it live.
final room = chat.room(roomId);
await room.join();

room.messages.listen((messages) => render(messages));   // optimistic + live
room.typingUserIds.listen((ids) => showTyping(ids));
room.presentUsers.listen((users) => showOnline(users));

await room.setTyping(typing: true);
await room.send(text: 'hello');                          // renders instantly
await room.loadMore();                                   // older history

await room.leave();                                      // releases channels
```

## What you get for free

- **Optimistic send** — messages appear instantly and reconcile with the server echo (no duplicates), via `client_id` idempotency.
- **Offline outbox** — failed sends queue and retry on reconnect.
- **Typing** over realtime broadcast (ephemeral, auto-expiring; no DB writes).
- **Presence** — who's in the room right now.
- **RLS-enforced** — membership is the security boundary; see the migration.

## License

MIT
