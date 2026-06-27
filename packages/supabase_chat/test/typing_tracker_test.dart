import 'package:fake_async/fake_async.dart';
import 'package:supabase_chat/supabase_chat.dart';
import 'package:test/test.dart';

void main() {
  group('TypingTracker', () {
    test('adds a peer and ignores the current user', () {
      final tracker = TypingTracker(currentUserId: 'me')
        ..apply(userId: 'bob', typing: true);
      expect(tracker.users, ['bob']);

      tracker
        ..apply(userId: 'me', typing: true) // self — ignored
        ..apply(userId: null, typing: true); // null — ignored
      expect(tracker.users, ['bob']);
    });

    test('typing:false removes a peer', () {
      final tracker = TypingTracker(currentUserId: 'me')
        ..apply(userId: 'bob', typing: true)
        ..apply(userId: 'bob', typing: false);
      expect(tracker.users, isEmpty);
    });

    test('auto-expires a peer after the timeout', () {
      fakeAsync((async) {
        final tracker = TypingTracker(currentUserId: 'me')
          ..apply(userId: 'bob', typing: true);

        async.elapse(const Duration(seconds: 3));
        expect(tracker.users, ['bob'], reason: 'still typing before timeout');

        async.elapse(const Duration(seconds: 2));
        expect(tracker.users, isEmpty, reason: 'expired after timeout');
      });
    });

    test('a refresh resets the expiry timer', () {
      fakeAsync((async) {
        final tracker = TypingTracker(currentUserId: 'me')
          ..apply(userId: 'bob', typing: true);

        async.elapse(const Duration(seconds: 3));
        tracker.apply(userId: 'bob', typing: true); // refresh
        async.elapse(const Duration(seconds: 3));
        expect(tracker.users, ['bob'], reason: 'refresh extended the window');

        async.elapse(const Duration(seconds: 2));
        expect(tracker.users, isEmpty);
      });
    });
  });
}
