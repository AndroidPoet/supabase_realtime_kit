# supabase_chat_widgets example

Drop a full chat screen into your app with one widget.

```dart
import 'package:flutter/material.dart';
import 'package:supabase_chat/supabase_chat.dart';
import 'package:supabase_chat_widgets/supabase_chat_widgets.dart';

class RoomScreen extends StatelessWidget {
  const RoomScreen({required this.room, super.key});

  final ChatRoom room;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Chat')),
      // Live messages, optimistic send, replies, reactions, media, typing —
      // all wired. Long-press toggles 👍 by default.
      body: ChatView(room: room),
    );
  }
}
```

For the end-to-end encrypted variant, use `EncryptedChatView` with an
`EncryptedChatRoom` from `supabase_chat_e2ee` (includes a safety-number
verification banner). A complete, backend-free demo lives in the repository at
`example/lib/preview_e2ee.dart`.
