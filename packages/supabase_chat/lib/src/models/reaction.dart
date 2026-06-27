import 'package:meta/meta.dart';

/// A single emoji reaction by one user on one message.
@immutable
class Reaction {
  /// Creates a reaction.
  const Reaction({
    required this.id,
    required this.messageId,
    required this.userId,
    required this.emoji,
    required this.createdAt,
  });

  /// Builds a [Reaction] from a `message_reactions` row.
  factory Reaction.fromJson(Map<String, dynamic> json) => Reaction(
    id: json['id'] as String,
    messageId: json['message_id'] as String,
    userId: json['user_id'] as String,
    emoji: json['emoji'] as String,
    createdAt: DateTime.parse(json['created_at'] as String).toUtc(),
  );

  /// Server primary key.
  final String id;

  /// The message reacted to.
  final String messageId;

  /// The reacting user.
  final String userId;

  /// The emoji.
  final String emoji;

  /// When the reaction was added (UTC).
  final DateTime createdAt;

  @override
  bool operator ==(Object other) =>
      other is Reaction &&
      other.messageId == messageId &&
      other.userId == userId &&
      other.emoji == emoji;

  @override
  int get hashCode => Object.hash(messageId, userId, emoji);

  @override
  String toString() => 'Reaction($emoji by $userId on $messageId)';
}
