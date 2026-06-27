// Minimal example: anonymous sign-in, open (or create) a room, render ChatView.
//
// Run with your project credentials:
//   flutter run \
//     --dart-define=SUPABASE_URL=https://xyz.supabase.co \
//     --dart-define=SUPABASE_ANON_KEY=ey...
//
// Requires the schema in supabase/migrations/0001_chat_schema.sql and anonymous
// sign-ins enabled in your Supabase Auth settings.

import 'package:flutter/material.dart';
import 'package:supabase_chat/supabase_chat.dart';
import 'package:supabase_chat_ui/supabase_chat_ui.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

const _supabaseUrl = String.fromEnvironment('SUPABASE_URL');
const _supabaseAnonKey = String.fromEnvironment('SUPABASE_ANON_KEY');
const _demoRoomName = 'demo-room';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // ignore: deprecated_member_use  — anonKey kept for broad SDK compatibility.
  await Supabase.initialize(url: _supabaseUrl, anonKey: _supabaseAnonKey);
  await Supabase.instance.client.auth.signInAnonymously();
  runApp(const ChatApp());
}

/// The example application root.
class ChatApp extends StatelessWidget {
  /// Creates the example app.
  const ChatApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'supabase_chat example',
      theme: ThemeData(
        colorSchemeSeed: const Color(0xFF4F46E5), // indigo
        useMaterial3: true,
      ),
      home: const RoomLoader(),
    );
  }
}

/// Resolves (or creates) the demo room, then shows the chat.
class RoomLoader extends StatefulWidget {
  /// Creates the loader.
  const RoomLoader({super.key});

  @override
  State<RoomLoader> createState() => _RoomLoaderState();
}

class _RoomLoaderState extends State<RoomLoader> {
  late final SupabaseChat _chat = SupabaseChat(Supabase.instance.client);
  late final Future<ChatRoom> _room = _openRoom();

  Future<ChatRoom> _openRoom() async {
    final rooms = (await _chat.myRooms()).valueOr(const []);
    final existing = rooms.where((r) => r.name == _demoRoomName).firstOrNull;
    final roomId =
        existing?.id ??
        (await _chat.createRoom(name: _demoRoomName)).valueOrNull?.id;
    if (roomId == null) {
      throw StateError('Could not open or create the demo room');
    }
    return _chat.room(roomId);
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<ChatRoom>(
      future: _room,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return Scaffold(
            body: Center(child: Text('Error: ${snapshot.error}')),
          );
        }
        final room = snapshot.data;
        if (room == null) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }
        return Scaffold(
          appBar: AppBar(title: const Text(_demoRoomName)),
          body: ChatView(room: room),
        );
      },
    );
  }
}
