# supabase_chat_ui

Optional Flutter widgets for [`supabase_chat`](../supabase_chat). Drop in a
complete chat screen with one widget, or compose your own UI from the same
building blocks. Nothing here is required — `supabase_chat` is headless and
works with any UI — but this package saves you from rebuilding a message list,
composer, and typing indicator for every app.

- **`ChatView`** — a full, scrollable chat body: live messages, optimistic
  send, replies, reactions, media, and typing, all wired to a `ChatRoom`.
- **`EncryptedChatView`** — the same screen for an `EncryptedChatRoom` from
  [`supabase_chat_e2ee`](../supabase_chat_e2ee), with a built-in safety-number
  verification banner.
- **Building blocks** — `MessageBubble`, `MessageComposer`, `TypingIndicator`,
  and `EncryptedChatBanner` are all exported for custom layouts.

Theming follows your app's `ThemeData` / `ColorScheme` — there are **no
hard-coded brand colors**, so the widgets adopt your light/dark theme
automatically.

## Install

```yaml
dependencies:
  supabase_chat: ^0.1.0
  supabase_chat_ui: ^0.1.0
```

This package depends on Flutter; the underlying `supabase_chat` and
`supabase_realtime_kit` are pure Dart.

## Quick start

Hand a joined (or not-yet-joined) `ChatRoom` to `ChatView` and you have a
working chat screen:

```dart
import 'package:flutter/material.dart';
import 'package:supabase_chat/supabase_chat.dart';
import 'package:supabase_chat_ui/supabase_chat_ui.dart';

class RoomScreen extends StatelessWidget {
  const RoomScreen({required this.room, super.key});

  final ChatRoom room;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('general')),
      // Live messages, optimistic send, replies, reactions, media, and
      // typing — all wired. Long-press a bubble to toggle 👍 by default.
      body: ChatView(room: room),
    );
  }
}
```

By default `ChatView` **manages the room lifecycle**: it calls `room.join()`
when the widget mounts and `room.leave()` when it disposes. If you join/leave
the room yourself (e.g. the room outlives the screen), pass
`manageLifecycle: false`.

## `ChatView`

| Parameter | Type | Default | Purpose |
|---|---|---|---|
| `room` | `ChatRoom` | required | The room to render. Subscribes to its `messages`, `typingUserIds`, and presence streams. |
| `manageLifecycle` | `bool` | `true` | When `true`, joins on mount and leaves on dispose. Set `false` if you control the room's lifecycle. |

What it renders for you:

- A reverse-scrolling message list with optimistic ("sending…") states.
- Reply quoting (a bubble shows the message it replies to).
- Emoji reaction chips under bubbles, with per-emoji counts.
- Image / video / audio / file attachments.
- A live typing indicator above the composer.
- A `MessageComposer` that sends on submit and emits typing changes.

## Encrypted chat — `EncryptedChatView`

For end-to-end-encrypted rooms, use `EncryptedChatView` with an
`EncryptedChatRoom` (see [`supabase_chat_e2ee`](../supabase_chat_e2ee)). It adds
a verification banner backed by the room's safety number, and only sends once
the peer is verified (in strict mode).

```dart
import 'package:supabase_chat_e2ee/supabase_chat_e2ee.dart';
import 'package:supabase_chat_ui/supabase_chat_ui.dart';

EncryptedChatView(
  room: encryptedRoom,        // EncryptedChatRoom
  peerLabel: 'Alice',         // shown in the verification banner
);
```

| Parameter | Type | Default | Purpose |
|---|---|---|---|
| `room` | `EncryptedChatRoom` | required | The encrypted room to render and decrypt. |
| `manageLifecycle` | `bool` | `true` | Join on mount / leave on dispose. |
| `peerLabel` | `String?` | `null` | Human-friendly peer name shown in the banner. |

The banner surfaces the 60-digit safety number and a **Verify** action; until
the user confirms it matches on the other device, strict-mode sends are
blocked. See the e2ee package for the underlying trust model.

## Building blocks

Use these directly when `ChatView` doesn't match your layout.

### `MessageBubble`

A single message bubble: text, reply quote, reaction chips, and "mine vs
theirs" alignment.

| Parameter | Type | Default | Purpose |
|---|---|---|---|
| `message` | `Message` | required | The message to display. |
| `isMine` | `bool` | required | Right-align + use the primary color when `true`. |
| `repliedTo` | `Message?` | `null` | The quoted message rendered above the body. |
| `reactions` | `List<Reaction>` | `const []` | Reaction chips, grouped and counted by emoji. |

### `MessageComposer`

A text field with a send button; emits the typed text and (optionally) typing
state.

| Parameter | Type | Default | Purpose |
|---|---|---|---|
| `onSend` | `ValueChanged<String>` | required | Called with the message text on submit. |
| `onTypingChanged` | `ValueChanged<bool>?` | `null` | Called as the user starts/stops typing; wire to `room.setTyping`. |
| `hintText` | `String` | `'Message'` | Placeholder text. |

### `TypingIndicator`

Renders "X is typing…" for the given user ids.

| Parameter | Type | Default | Purpose |
|---|---|---|---|
| `userIds` | `List<String>` | required | Who is currently typing. |
| `nameFor` | `String Function(String id)?` | `null` | Maps a user id to a display name. |

### `EncryptedChatBanner`

The verification banner used by `EncryptedChatView`; reusable on its own.

| Parameter | Type | Default | Purpose |
|---|---|---|---|
| `verified` | `bool` | required | Whether the peer is verified (controls banner state). |
| `onVerify` | `VoidCallback` | required | Invoked when the user taps **Verify**. |
| `loading` | `bool` | `false` | Shows a progress state while computing the safety number. |
| `safetyNumber` | `String?` | `null` | The 60-digit number to display for out-of-band comparison. |
| `peerLabel` | `String?` | `null` | Human-friendly peer name. |

## Custom layout example

Compose the pieces yourself when you need a bespoke screen:

```dart
Column(
  children: [
    Expanded(
      child: StreamBuilder<List<Message>>(
        stream: room.messages,
        builder: (context, snapshot) {
          final messages = snapshot.data ?? const [];
          return ListView(
            reverse: true,
            children: [
              for (final m in messages.reversed)
                MessageBubble(message: m, isMine: m.senderId == myId),
            ],
          );
        },
      ),
    ),
    StreamBuilder<List<String>>(
      stream: room.typingUserIds,
      builder: (context, s) => TypingIndicator(userIds: s.data ?? const []),
    ),
    MessageComposer(
      onSend: (text) => room.send(text: text),
      onTypingChanged: (typing) => room.setTyping(typing: typing),
    ),
  ],
)
```

## Theming

All widgets read from `Theme.of(context)`:

- Bubbles use `colorScheme.primary` / `surfaceContainerHighest` for
  mine/theirs, with matching `onPrimary` / `onSurface` text.
- The composer and banner inherit your input and card styling.

To restyle, wrap the view in a `Theme` with the `ColorScheme` you want — no
widget-level color parameters needed.

## License

MIT
