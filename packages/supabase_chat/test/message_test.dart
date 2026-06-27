import 'package:supabase_chat/supabase_chat.dart';
import 'package:test/test.dart';

void main() {
  group('Message', () {
    final row = <String, dynamic>{
      'id': 'm1',
      'room_id': 'r1',
      'sender_id': 'u1',
      'content': 'hello',
      'attachments': [
        {'path': 'a.png'},
      ],
      'client_id': 'c1',
      'created_at': '2026-06-27T10:00:00Z',
      'edited_at': null,
      'deleted_at': null,
    };

    test('parses a database row', () {
      final message = Message.fromJson(row);
      expect(message.id, 'm1');
      expect(message.roomId, 'r1');
      expect(message.content, 'hello');
      expect(message.clientId, 'c1');
      expect(message.attachments.single['path'], 'a.png');
      expect(message.createdAt.isUtc, isTrue);
      expect(message.isDeleted, isFalse);
      expect(message.pending, isFalse);
    });

    test('toInsert omits server-managed fields', () {
      final insert = Message.fromJson(row).toInsert();
      expect(insert.containsKey('id'), isFalse);
      expect(insert.containsKey('created_at'), isFalse);
      expect(insert['room_id'], 'r1');
      expect(insert['client_id'], 'c1');
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
