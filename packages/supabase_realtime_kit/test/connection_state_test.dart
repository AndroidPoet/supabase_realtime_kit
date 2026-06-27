import 'package:supabase_realtime_kit/supabase_realtime_kit.dart';
import 'package:test/test.dart';

void main() {
  group('KitConnectionState', () {
    test('isLive is true only when connected', () {
      expect(KitConnectionState.connected.isLive, isTrue);
      expect(KitConnectionState.connecting.isLive, isFalse);
      expect(KitConnectionState.disconnected.isLive, isFalse);
    });
  });
}
