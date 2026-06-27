import 'package:supabase_chat/supabase_chat.dart';
import 'package:test/test.dart';

void main() {
  group('MemberRole', () {
    test('parses known roles', () {
      expect(MemberRole.fromName('owner'), MemberRole.owner);
      expect(MemberRole.fromName('admin'), MemberRole.admin);
      expect(MemberRole.fromName('member'), MemberRole.member);
    });

    test('defaults unknown/null to member', () {
      expect(MemberRole.fromName('superuser'), MemberRole.member);
      expect(MemberRole.fromName(null), MemberRole.member);
    });
  });

  group('ChatMember', () {
    test('parses a row', () {
      final member = ChatMember.fromJson(const {
        'room_id': 'r1',
        'user_id': 'u1',
        'role': 'admin',
        'joined_at': '2026-06-27T10:00:00Z',
      });
      expect(member.roomId, 'r1');
      expect(member.userId, 'u1');
      expect(member.role, MemberRole.admin);
      expect(member.joinedAt.isUtc, isTrue);
    });

    test('identity is by (roomId, userId)', () {
      final a = ChatMember.fromJson(const {
        'room_id': 'r1',
        'user_id': 'u1',
        'role': 'member',
        'joined_at': '2026-06-27T10:00:00Z',
      });
      final sameKeyDifferentRole = ChatMember.fromJson(const {
        'room_id': 'r1',
        'user_id': 'u1',
        'role': 'owner',
        'joined_at': '2026-06-28T10:00:00Z',
      });
      final differentUser = ChatMember.fromJson(const {
        'room_id': 'r1',
        'user_id': 'u2',
        'role': 'member',
        'joined_at': '2026-06-27T10:00:00Z',
      });
      expect(a, equals(sameKeyDifferentRole));
      expect(a, isNot(equals(differentUser)));
    });
  });
}
