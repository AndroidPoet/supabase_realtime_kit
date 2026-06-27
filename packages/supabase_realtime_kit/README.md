# supabase_realtime_kit

Headless, plug-and-play realtime primitives on top of the [Supabase](https://pub.dev/packages/supabase) SDK. Pure Dart — use it from Flutter, a Dart server, or a CLI.

It handles the three things people get wrong wiring Supabase realtime by hand:

1. **Live queries** — initial REST load + live `postgres_changes` tail in one stream.
2. **Optimistic merge** — show a row instantly; the server echo replaces the placeholder, no duplicates.
3. **Reconnect reconciliation + offline outbox** — backfill missed changes on resubscribe; queue and retry failed writes.

Chat is the flagship consumer (`supabase_chat`), but the kit is generic: live cursors, dashboards, collaborative docs all reuse it.

## Install

```yaml
dependencies:
  supabase_realtime_kit: ^0.1.0
```

## Quick start

```dart
import 'package:supabase_realtime_kit/supabase_realtime_kit.dart';

final kit = RealtimeKit(supabaseClient);

final query = kit.liveQuery<Message>(
  table: 'messages',
  filterColumn: 'room_id', filterValue: roomId,
  fromJson: Message.fromJson,
  idOf: (m) => m.id,
  pendingKeyOf: (m) => m.clientId,                 // optimistic reconciliation
  compare: (a, b) => a.createdAt.compareTo(b.createdAt),
);

await query.start();
query.stream.listen((messages) => render(messages));

// Optimistic send via the outbox-backed write path:
query.addPending(optimisticMessage);
await kit.insert(table: 'messages', payload: row, outboxId: clientId);
```

## API

| Type | Purpose |
|---|---|
| `RealtimeKit` | Entry point: live queries, presence, broadcast, outbox writes, connection state |
| `LiveQuery<T>` | Realtime list with optimistic merge + pagination |
| `PresenceTracker` | Who's online on a channel |
| `BroadcastHub` | Ephemeral signals (typing, reactions, cursors) |
| `Outbox` | Pluggable offline write queue (in-memory default; bring your own persistence) |
| `Result<T>` | Error-honest return type (`Ok` / `Err`) |

## License

MIT
