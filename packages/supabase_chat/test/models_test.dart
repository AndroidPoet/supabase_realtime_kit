import 'package:supabase_chat/supabase_chat.dart';
import 'package:test/test.dart';

void main() {
  group('Attachment', () {
    test('round-trips through JSON and omits null fields', () {
      const attachment = Attachment(
        path: 'r1/a.png',
        url: 'https://x/a.png',
        name: 'a.png',
        mimeType: 'image/png',
        size: 1024,
        width: 100,
        height: 80,
      );
      final json = attachment.toJson();
      expect(json.containsKey('duration_ms'), isFalse);
      final restored = Attachment.fromJson(json);
      expect(restored.path, 'r1/a.png');
      expect(restored.mimeType, 'image/png');
      expect(restored.size, 1024);
      expect(restored.width, 100);
      expect(restored, equals(attachment)); // identity by path
    });
  });

  group('MessageType', () {
    test('parses known values and defaults to text', () {
      expect(MessageType.fromName('image'), MessageType.image);
      expect(MessageType.fromName('audio'), MessageType.audio);
      expect(MessageType.fromName('weird'), MessageType.text);
      expect(MessageType.fromName(null), MessageType.text);
    });
  });

  group('Reaction', () {
    test('parses a row and is keyed by (message, user, emoji)', () {
      final reaction = Reaction.fromJson(const {
        'id': 'x1',
        'message_id': 'm1',
        'user_id': 'u1',
        'emoji': '👍',
        'created_at': '2026-06-27T10:00:00Z',
      });
      expect(reaction.id, 'x1');
      expect(reaction.messageId, 'm1');
      expect(reaction.emoji, '👍');

      final sameLogical = Reaction.fromJson(const {
        'id': 'x2', // different surrogate id
        'message_id': 'm1',
        'user_id': 'u1',
        'emoji': '👍',
        'created_at': '2026-06-27T11:00:00Z',
      });
      expect(reaction, equals(sameLogical));
    });
  });
}
