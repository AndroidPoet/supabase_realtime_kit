import 'package:supabase_realtime_kit/supabase_realtime_kit.dart';
import 'package:test/test.dart';

void main() {
  group('Result', () {
    test('Ok carries a value and reports isOk', () {
      const result = Result<int>.ok(42);
      expect(result.isOk, isTrue);
      expect(result.isErr, isFalse);
      expect(result.valueOrNull, 42);
      expect(result.valueOr(0), 42);
    });

    test('Err carries an error and reports isErr', () {
      final result = Result<int>.err(StateError('boom'));
      expect(result.isErr, isTrue);
      expect(result.valueOrNull, isNull);
      expect(result.valueOr(7), 7);
    });

    test('map transforms Ok and passes Err through', () {
      expect(const Result<int>.ok(2).map((v) => v * 2), const Ok<int>(4));
      const err = Result<int>.err('x');
      expect(err.map((v) => v * 2).isErr, isTrue);
    });

    test('guard captures thrown errors', () async {
      final ok = await Result.guard<int>(() async => 1);
      expect(ok, const Ok<int>(1));

      final err = await Result.guard<int>(() async => throw StateError('no'));
      expect(err.isErr, isTrue);
    });
  });
}
