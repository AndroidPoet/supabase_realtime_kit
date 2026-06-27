# supabase_chat_example

Runnable Flutter examples for `supabase_chat` / `supabase_chat_ui`. There are
two entrypoints; both need a Supabase project with the chat schema applied and
anonymous sign-ins enabled.

## Setup (once)

1. Apply [`supabase/migrations/0001_chat_schema.sql`](../supabase/migrations/0001_chat_schema.sql)
   to your project (tables, RLS, realtime publication).
2. Enable **anonymous sign-ins** in Supabase → Authentication → Providers.
3. Install deps: `flutter pub get`.

Pass your credentials via `--dart-define` on every run:

```
--dart-define=SUPABASE_URL=https://YOUR.supabase.co
--dart-define=SUPABASE_ANON_KEY=YOUR_ANON_KEY
```

## 1 · Single user — drop-in `ChatView`

The minimal integration: anonymous sign-in, open/create a room, render the
whole chat with one widget.

```bash
flutter run -t lib/main.dart \
  --dart-define=SUPABASE_URL=https://YOUR.supabase.co \
  --dart-define=SUPABASE_ANON_KEY=YOUR_ANON_KEY
```

## 2 · Two users — all live statuses side by side ⭐

Boots **two independent clients (two anonymous users)** into one shared room and
renders both sides in a single window, so you can watch every realtime status
propagate live between them:

- **Presence** — each pane's header shows how many peers are *online*.
- **Typing** — type in one pane; the other shows `typing…` (auto-stops after a
  pause).
- **Send status** — your bubbles show `sending…` (optimistic) then `sent` once
  the server echoes.
- **Read receipts** — the `unread` badge rises when a message arrives and drops
  to zero as the other pane reads it.

```bash
flutter run -t lib/two_users.dart \
  --dart-define=SUPABASE_URL=https://YOUR.supabase.co \
  --dart-define=SUPABASE_ANON_KEY=YOUR_ANON_KEY
```

Wide windows show the two users side by side; narrow ones stack them.

## 3 · Encrypted two users — see the ciphertext on the server 🔐

Two users chat **end-to-end encrypted** (permissive `supabase_chat_seal`), and a
bottom panel shows the **exact ciphertext stored in Supabase**
(`messages.encrypted`) — so you can see the humans read plaintext while the
database only ever holds an opaque blob. Each side also shows the verified
safety number and presence.

```bash
flutter run -t lib/encrypted_two_users.dart \
  --dart-define=SUPABASE_URL=https://YOUR.supabase.co \
  --dart-define=SUPABASE_ANON_KEY=YOUR_ANON_KEY
```

Requires `0003_e2ee_public_keys.sql` in addition to `0001_chat_schema.sql`.

## 4 · End-to-end encryption preview

`lib/preview_e2ee.dart` shows the encrypted chat view with the safety-number
verification banner. See [`supabase_chat_e2ee`](../packages/supabase_chat_e2ee)
(Signal, GPL) and [`supabase_chat_seal`](../packages/supabase_chat_seal)
(ECDH+AES-GCM, MIT) for backend-free console demos you can run with `dart run`.
