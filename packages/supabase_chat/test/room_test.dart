import 'package:supabase_chat/supabase_chat.dart';
import 'package:test/test.dart';

void main() {
  group('Room', () {
    test('parses a row', () {
      final room = Room.fromJson(const {
        'id': 'r1',
        'name': 'general',
        'is_direct': false,
        'created_by': 'u1',
        'created_at': '2026-06-27T10:00:00Z',
      });
      expect(room.id, 'r1');
      expect(room.name, 'general');
      expect(room.isDirect, isFalse);
      expect(room.createdBy, 'u1');
      expect(room.createdAt.isUtc, isTrue);
    });

    test('defaults is_direct and allows null name', () {
      final room = Room.fromJson(const {
        'id': 'r2',
        'name': null,
        'created_by': 'u1',
        'created_at': '2026-06-27T10:00:00Z',
      });
      expect(room.name, isNull);
      expect(room.isDirect, isFalse);
    });

    test('identity is by id', () {
      final base = Room.fromJson(const {
        'id': 'r1',
        'created_by': 'u1',
        'created_at': '2026-06-27T10:00:00Z',
      });
      final same = Room.fromJson(const {
        'id': 'r1',
        'name': 'renamed',
        'created_by': 'u2',
        'created_at': '2026-06-28T10:00:00Z',
      });
      expect(base, equals(same));
      expect(base.hashCode, same.hashCode);
    });
  });
}
