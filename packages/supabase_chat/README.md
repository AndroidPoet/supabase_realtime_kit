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

## WhatsApp-grade features

| Feature | API |
|---|---|
| Optimistic send (no dupes, `client_id` reconcile) | `room.send(text: …)` |
| Offline outbox + retry on reconnect | automatic |
| Replies / quotes | `room.reply(toMessageId: …, text: …)` |
| Edit message | `room.editMessage(id, newText)` |
| Soft-delete ("message deleted") | `room.deleteMessage(id)` |
| Emoji reactions | `room.react(id, '👍')` / `removeReaction` · `room.reactionsByMessage` |
| Media (image/video/audio/file) | `chat.uploadAttachment(...)` → `room.sendMedia(attachments: …)` |
| Typing indicators (auto-expiring) | `room.setTyping(typing: true)` · `room.typingUserIds` |
| Presence (who's online) | `room.presentUsers` |
| Read receipts + unread counts | `room.markRead()` · `room.unreadCount` |
| Pagination (infinite scroll) | `room.loadMore()` |
| 1:1 direct chats & groups | `chat.directRoom(userId)` / `chat.createRoom(...)` |

All ephemeral signals (typing/presence) ride realtime — no DB writes. Membership-based **RLS is the security boundary**; see the migration. Media uses a Storage bucket with room-scoped policies.

## License

MIT
