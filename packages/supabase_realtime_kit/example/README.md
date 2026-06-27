# supabase_realtime_kit example

A live, optimistic, self-healing list backed by a Supabase table — the core use
case in a few lines.

```dart
import 'package:supabase/supabase.dart';
import 'package:supabase_realtime_kit/supabase_realtime_kit.dart';

Future<void> main() async {
  final client = SupabaseClient('https://YOUR.supabase.co', 'YOUR_ANON_KEY');
  final kit = RealtimeKit(client);

  // Initial REST load + live postgres_changes tail + optimistic merge.
  final messages = kit.liveQuery<Map<String, dynamic>>(
    table: 'messages',
    fromJson: (row) => row,
    idOf: (row) => row['id'] as String,
    compare: (a, b) =>
        (a['created_at'] as String).compareTo(b['created_at'] as String),
  );

  messages.stream.listen((rows) => print('now ${rows.length} messages'));
  await messages.start();

  // Optimistic insert — shows immediately, reconciles with the server echo,
  // and is buffered in the outbox + retried if offline.
  await kit.insert(
    table: 'messages',
    payload: {'body': 'hello realtime'},
    outboxId: 'client-generated-id',
  );

  // ...later
  await messages.dispose();
  await kit.dispose();
}
```

See the repository's `example/` app for a full Flutter integration.
