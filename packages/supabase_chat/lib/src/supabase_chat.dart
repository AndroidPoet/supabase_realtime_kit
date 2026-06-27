import 'dart:typed_data';

import 'package:supabase/supabase.dart';
import 'package:supabase_chat/src/chat_room.dart';
import 'package:supabase_chat/src/models/attachment.dart';
import 'package:supabase_chat/src/models/room.dart';
import 'package:supabase_realtime_kit/supabase_realtime_kit.dart';

/// Entry point for the chat domain. Wraps a [SupabaseClient] (via
/// [RealtimeKit]) and hands out [ChatRoom] handles.
///
/// ```dart
/// final chat = SupabaseChat(supabaseClient);
/// final created = await chat.createRoom(name: 'general', memberIds: [bobId]);
/// final room = chat.room(created.valueOrNull!.id);
/// await room.join();
/// ```
class SupabaseChat {
  /// Creates a chat client over [client]. Pass a durable [outbox] for offline
  /// send persistence and override [attachmentsBucket] to use a different
  /// Storage bucket for media.
  SupabaseChat(
    SupabaseClient client, {
    Outbox? outbox,
    this.attachmentsBucket = 'chat-attachments',
  }) : kit = RealtimeKit(client, outbox: outbox);

  /// The underlying realtime kit (escape hatch for advanced use).
  final RealtimeKit kit;

  /// The Storage bucket media attachments are uploaded to.
  final String attachmentsBucket;

  SupabaseClient get _client => kit.client;

  /// The signed-in user's id, or `null` if not authenticated.
  String? get currentUserId => _client.auth.currentUser?.id;

  /// Opens a live handle on [roomId] for the signed-in user.
  ///
  /// Throws [StateError] if there is no authenticated user.
  ChatRoom room(
    String roomId, {
    Map<String, dynamic> presenceState = const {},
  }) {
    final userId = currentUserId;
    if (userId == null) {
      throw StateError('Cannot open a room without an authenticated user');
    }
    return ChatRoom(
      kit: kit,
      roomId: roomId,
      currentUserId: userId,
      presenceState: presenceState,
    );
  }

  /// Creates a room and adds the creator plus [memberIds] as members.
  Future<Result<Room>> createRoom({
    String? name,
    bool isDirect = false,
    List<String> memberIds = const [],
  }) => Result.guard(() async {
    final userId = currentUserId;
    if (userId == null) {
      throw StateError('Cannot create a room without an authed user');
    }
    final row = await _client
        .from('rooms')
        .insert({
          if (name != null) 'name': name,
          'is_direct': isDirect,
          'created_by': userId,
        })
        .select()
        .single();
    final room = Room.fromJson(row);

    final memberRows = <Map<String, dynamic>>[
      {'room_id': room.id, 'user_id': userId, 'role': 'owner'},
      for (final id in memberIds)
        if (id != userId) {'room_id': room.id, 'user_id': id},
    ];
    await _client.from('room_members').insert(memberRows);
    return room;
  });

  /// Creates (or returns a fresh handle for) a 1:1 direct room with
  /// [otherUserId]. Convenience over [createRoom] with `isDirect: true`.
  Future<Result<Room>> directRoom(String otherUserId) =>
      createRoom(isDirect: true, memberIds: [otherUserId]);

  /// Uploads [bytes] as a chat attachment under `roomId/` in the
  /// [attachmentsBucket] and returns its [Attachment] descriptor (with a public
  /// URL). Pass the result to `ChatRoom.sendMedia`.
  Future<Result<Attachment>> uploadAttachment({
    required String roomId,
    required String fileName,
    required Uint8List bytes,
    String? contentType,
  }) => Result.guard(() async {
    final path = '$roomId/${DateTime.now().microsecondsSinceEpoch}-$fileName';
    await _client.storage
        .from(attachmentsBucket)
        .uploadBinary(
          path,
          bytes,
          fileOptions: FileOptions(contentType: contentType),
        );
    final url = _client.storage.from(attachmentsBucket).getPublicUrl(path);
    return Attachment(
      path: path,
      url: url,
      name: fileName,
      mimeType: contentType,
      size: bytes.length,
    );
  });

  /// Lists rooms visible to the signed-in user (RLS scopes this to rooms they
  /// belong to), newest first.
  Future<Result<List<Room>>> myRooms() => Result.guard(() async {
    final rows = await _client
        .from('rooms')
        .select()
        .order('created_at', ascending: false);
    return rows.map(Room.fromJson).toList();
  });
}
