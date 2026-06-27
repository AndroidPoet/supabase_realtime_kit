import 'package:meta/meta.dart';

/// A member's role within a room.
enum MemberRole {
  /// The room owner (creator).
  owner,

  /// An administrator.
  admin,

  /// A regular member.
  member;

  /// Parses a role string from the database, defaulting to [member].
  static MemberRole fromName(String? name) => MemberRole.values.firstWhere(
    (role) => role.name == name,
    orElse: () => MemberRole.member,
  );
}

/// A user's membership in a room.
@immutable
class ChatMember {
  /// Creates a membership record.
  const ChatMember({
    required this.roomId,
    required this.userId,
    required this.role,
    required this.joinedAt,
  });

  /// Builds a [ChatMember] from a `room_members` row.
  factory ChatMember.fromJson(Map<String, dynamic> json) => ChatMember(
    roomId: json['room_id'] as String,
    userId: json['user_id'] as String,
    role: MemberRole.fromName(json['role'] as String?),
    joinedAt: DateTime.parse(json['joined_at'] as String).toUtc(),
  );

  /// The room.
  final String roomId;

  /// The member's user id.
  final String userId;

  /// The member's role.
  final MemberRole role;

  /// When the member joined (UTC).
  final DateTime joinedAt;

  @override
  bool operator ==(Object other) =>
      other is ChatMember && other.roomId == roomId && other.userId == userId;

  @override
  int get hashCode => Object.hash(roomId, userId);

  @override
  String toString() => 'ChatMember($userId in $roomId, $role)';
}
