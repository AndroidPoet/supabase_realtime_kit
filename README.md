# supabase_realtime_kit

A monorepo of **plug-and-play realtime libraries for Flutter & Dart on top of Supabase**.

| Package | What it is |
|---|---|
| [`supabase_realtime_kit`](packages/supabase_realtime_kit) | **Pure-Dart core.** Headless realtime primitives: live queries with optimistic merge, presence, broadcast, offline outbox. |
| [`supabase_chat`](packages/supabase_chat) | **Chat domain** on the core: rooms, messages, typing, presence, read receipts. |
| [`supabase_chat_ui`](packages/supabase_chat_ui) | **Optional Flutter widgets**: a drop-in `ChatView` + building blocks. |
| [`example/`](example) | A runnable Flutter chat app. |

The core is deliberately **headless and pure Dart** — chat is just the flagship consumer. Live cursors, dashboards, and collaborative docs reuse the same primitives.

## Why

Raw Supabase realtime is low-level: you stitch together `postgres_changes`, `broadcast`, and `presence`, then re-implement optimistic sends, reconnect backfill, and an offline queue every time. This kit does that once, cleanly.

## Quick start

1. **Backend** — apply [`supabase/migrations/0001_chat_schema.sql`](supabase/migrations/0001_chat_schema.sql) to your Supabase project (tables, RLS, realtime publication).
2. **Run the example:**

   ```bash
   dart pub global activate melos
   melos bootstrap            # or: flutter pub get  (native pub workspace)
   cd example
   flutter run \
     --dart-define=SUPABASE_URL=https://YOUR.supabase.co \
     --dart-define=SUPABASE_ANON_KEY=YOUR_ANON_KEY
   ```

3. **Use it:**

   ```dart
   final chat = SupabaseChat(supabaseClient);
   final room = chat.room(roomId)..join();
   // Flutter:
   ChatView(room: room);
   ```

## Develop

This is a native Dart pub workspace (Dart 3.6+) managed with [Melos](https://melos.invertase.dev):

```bash
melos run format     # dart format
melos run analyze    # strict very_good_analysis lints
melos run test       # unit tests
melos run check      # all of the above (pre-commit gate)
```

## Design principles

- **Thin over the SDK, no magic** — predictable wrappers, not a framework.
- **Result-first** — errors are returned (`Ok`/`Err`), not thrown across the API.
- **Pluggable, not bundled** — bring your own outbox persistence; nothing platform-specific in the core.
- **RLS is the security boundary** — the client trusts the policies in the migration.

## License

MIT © Ranbir Singh
