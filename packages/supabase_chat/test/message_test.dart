import 'package:supabase_chat/supabase_chat.dart';
import 'package:test/test.dart';

void main() {
  group('Message', () {
    final row = <String, dynamic>{
      'id': 'm1',
      'room_id': 'r1',
      'sender_id': 'u1',
      'type': 'image',
      'content': 'hello',
      'attachments': [
        {'path': 'r1/a.png', 'mime_type': 'image/png', 'size': 12},
      ],
      'reply_to': 'm0',
      'client_id': 'c1',
      'created_at': '2026-06-27T10:00:00Z',
      'edited_at': '2026-06-27T10:05:00Z',
      'deleted_at': null,
    };

    test('parses a database row', () {
      final message = Message.fromJson(row);
      expect(message.id, 'm1');
      expect(message.roomId, 'r1');
      expect(message.type, MessageType.image);
      expect(message.content, 'hello');
      expect(message.clientId, 'c1');
      expect(message.attachments.single.path, 'r1/a.png');
      expect(message.attachments.single.mimeType, 'image/png');
      expect(message.replyToId, 'm0');
      expect(message.isReply, isTrue);
      expect(message.isEdited, isTrue);
      expect(message.createdAt.isUtc, isTrue);
      expect(message.isDeleted, isFalse);
      expect(message.pending, isFalse);
    });

    test('defaults type to text and tolerates missing fields', () {
      final message = Message.fromJson(const {
        'id': 'm2',
        'room_id': 'r1',
        'sender_id': 'u1',
        'created_at': '2026-06-27T10:00:00Z',
      });
      expect(message.type, MessageType.text);
      expect(message.attachments, isEmpty);
      expect(message.replyToId, isNull);
      expect(message.isReply, isFalse);
    });

    test('toInsert serializes type, attachments, reply and omits id', () {
      final insert = Message.fromJson(row).toInsert();
      expect(insert.containsKey('id'), isFalse);
      expect(insert.containsKey('created_at'), isFalse);
      expect(insert['room_id'], 'r1');
      expect(insert['type'], 'image');
      expect(insert['reply_to'], 'm0');
      expect(insert['client_id'], 'c1');
      expect(
        (insert['attachments'] as List).single,
        containsPair('path', 'r1/a.png'),
      );
    });

    test('identity is by id', () {
      final a = Message.fromJson(row);
      final b = a.copyWith(pending: true);
      expect(a, equals(b)); // same id
      expect(a.copyWith(id: 'other'), isNot(equals(a)));
    });

    test('detects soft-deletion', () {
      final deleted = Message.fromJson({
        ...row,
        'deleted_at': '2026-06-27T11:00:00Z',
      });
      expect(deleted.isDeleted, isTrue);
    });
  });
}
