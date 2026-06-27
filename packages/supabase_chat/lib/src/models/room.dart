import 'package:meta/meta.dart';

/// A chat room (group or direct conversation).
@immutable
class Room {
  /// Creates a room.
  const Room({
    required this.id,
    required this.createdBy,
    required this.createdAt,
    this.name,
    this.isDirect = false,
  });

  /// Builds a [Room] from a `rooms` row.
  factory Room.fromJson(Map<String, dynamic> json) => Room(
    id: json['id'] as String,
    name: json['name'] as String?,
    isDirect: json['is_direct'] as bool? ?? false,
    createdBy: json['created_by'] as String,
    createdAt: DateTime.parse(json['created_at'] as String).toUtc(),
  );

  /// Server primary key.
  final String id;

  /// Display name (null for direct messages, which derive a name from members).
  final String? name;

  /// Whether this is a 1:1 direct conversation.
  final bool isDirect;

  /// The user who created the room.
  final String createdBy;

  /// When the room was created (UTC).
  final DateTime createdAt;

  @override
  bool operator ==(Object other) => other is Room && other.id == id;

  @override
  int get hashCode => id.hashCode;

  @override
  String toString() => 'Room($id, name: $name)';
}
