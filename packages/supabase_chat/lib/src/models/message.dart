import 'package:meta/meta.dart';

/// A single chat message.
///
/// Optimistic (not-yet-persisted) messages carry [pending] `= true` and a
/// temporary [id]; they share their [clientId] with the eventual server row so
/// the live query can reconcile the two.
@immutable
class Message {
  /// Creates a message.
  const Message({
    required this.id,
    required this.roomId,
    required this.senderId,
    required this.createdAt,
    this.content,
    this.attachments = const [],
    this.clientId,
    this.editedAt,
    this.deletedAt,
    this.pending = false,
  });

  /// Builds a [Message] from a `messages` row.
  factory Message.fromJson(Map<String, dynamic> json) => Message(
    id: json['id'] as String,
    roomId: json['room_id'] as String,
    senderId: json['sender_id'] as String,
    content: json['content'] as String?,
    attachments: [
      for (final a in (json['attachments'] as List? ?? const []))
        Map<String, dynamic>.from(a as Map),
    ],
    clientId: json['client_id'] as String?,
    createdAt: DateTime.parse(json['created_at'] as String).toUtc(),
    editedAt: json['edited_at'] == null
        ? null
        : DateTime.parse(json['edited_at'] as String).toUtc(),
    deletedAt: json['deleted_at'] == null
        ? null
        : DateTime.parse(json['deleted_at'] as String).toUtc(),
  );

  /// Server primary key (or a temporary `tmp:` id while [pending]).
  final String id;

  /// The room this message belongs to.
  final String roomId;

  /// The author's user id.
  final String senderId;

  /// Text body, if any.
  final String? content;

  /// Attachment descriptors (e.g. storage paths + metadata).
  final List<Map<String, dynamic>> attachments;

  /// Client-generated idempotency / reconciliation key.
  final String? clientId;

  /// When the message was created (UTC).
  final DateTime createdAt;

  /// When the message was last edited (UTC), if ever.
  final DateTime? editedAt;

  /// When the message was soft-deleted (UTC), if ever.
  final DateTime? deletedAt;

  /// Whether this is an optimistic message awaiting its server echo.
  final bool pending;

  /// Whether the message has been soft-deleted.
  bool get isDeleted => deletedAt != null;

  /// The insert payload for `messages` (server-managed fields omitted).
  Map<String, dynamic> toInsert() => {
    'room_id': roomId,
    'sender_id': senderId,
    if (content != null) 'content': content,
    'attachments': attachments,
    if (clientId != null) 'client_id': clientId,
  };

  /// Returns a copy with selected fields replaced.
  Message copyWith({String? id, bool? pending}) => Message(
    id: id ?? this.id,
    roomId: roomId,
    senderId: senderId,
    content: content,
    attachments: attachments,
    clientId: clientId,
    createdAt: createdAt,
    editedAt: editedAt,
    deletedAt: deletedAt,
    pending: pending ?? this.pending,
  );

  @override
  bool operator ==(Object other) => other is Message && other.id == id;

  @override
  int get hashCode => id.hashCode;

  @override
  String toString() => 'Message($id, pending: $pending)';
}
