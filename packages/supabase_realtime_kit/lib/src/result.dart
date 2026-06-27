import 'package:meta/meta.dart';

/// A success-or-failure value, used across the kit so callers handle errors
/// explicitly instead of relying on thrown exceptions.
///
/// Pattern-match with Dart's sealed-class exhaustiveness:
/// ```dart
/// switch (await room.send(text: 'hi')) {
///   case Ok(:final value):   print('sent ${value.id}');
///   case Err(:final error):  print('failed: $error');
/// }
/// ```
@immutable
sealed class Result<T> {
  const Result();

  /// Wraps [value] as a success.
  const factory Result.ok(T value) = Ok<T>;

  /// Wraps [error] (and optional [stackTrace]) as a failure.
  const factory Result.err(Object error, [StackTrace? stackTrace]) = Err<T>;

  /// Runs [body], capturing any thrown error into an [Err].
  static Future<Result<T>> guard<T>(Future<T> Function() body) async {
    try {
      return Ok<T>(await body());
    } on Object catch (error, stackTrace) {
      return Err<T>(error, stackTrace);
    }
  }

  /// Whether this is an [Ok].
  bool get isOk => this is Ok<T>;

  /// Whether this is an [Err].
  bool get isErr => this is Err<T>;

  /// The value if [Ok], otherwise `null`.
  T? get valueOrNull => switch (this) {
    Ok<T>(:final value) => value,
    Err<T>() => null,
  };

  /// The value if [Ok], otherwise [fallback].
  T valueOr(T fallback) => valueOrNull ?? fallback;

  /// Transforms the success value, leaving an [Err] untouched.
  Result<R> map<R>(R Function(T value) transform) => switch (this) {
    Ok<T>(:final value) => Ok<R>(transform(value)),
    Err<T>(:final error, :final stackTrace) => Err<R>(error, stackTrace),
  };
}

/// The success case of a [Result].
@immutable
final class Ok<T> extends Result<T> {
  /// Creates a success holding [value].
  const Ok(this.value);

  /// The successful value.
  final T value;

  @override
  bool operator ==(Object other) => other is Ok<T> && other.value == value;

  @override
  int get hashCode => value.hashCode;

  @override
  String toString() => 'Ok($value)';
}

/// The failure case of a [Result].
@immutable
final class Err<T> extends Result<T> {
  /// Creates a failure holding [error] and an optional [stackTrace].
  const Err(this.error, [this.stackTrace]);

  /// The captured error.
  final Object error;

  /// The stack trace at the point of failure, if available.
  final StackTrace? stackTrace;

  @override
  bool operator ==(Object other) => other is Err<T> && other.error == error;

  @override
  int get hashCode => error.hashCode;

  @override
  String toString() => 'Err($error)';
}
