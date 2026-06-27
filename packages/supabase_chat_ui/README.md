# supabase_chat_ui

Optional Flutter widgets for [`supabase_chat`](../supabase_chat). Drop in a full chat screen, or compose your own from the pieces.

```yaml
dependencies:
  supabase_chat_ui: ^0.1.0
```

```dart
import 'package:supabase_chat_ui/supabase_chat_ui.dart';

Scaffold(
  appBar: AppBar(title: const Text('general')),
  body: ChatView(room: chat.room(roomId)),  // joins on mount, leaves on dispose
);
```

Building blocks (use directly for custom layouts): `MessageBubble`, `MessageComposer`, `TypingIndicator`.

Theming follows your app's `ColorScheme` — no hard-coded brand colors. License: MIT.
