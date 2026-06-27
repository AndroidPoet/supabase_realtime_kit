import 'package:meta/meta.dart';
import 'package:supabase_chat/src/models/attachment.dart';

/// The kind of content a [Message] carries.
enum MessageType {
  /// A plain text message.
  text,

  /// An image attachment (optionally with a caption in [Message.content]).
  image,

  /// A video attachment.
  video,

  /// An audio clip / voice note.
  audio,

  /// A generic file/document.
  file,

  /// A system event (e.g. "X joined"), not authored by a user.
  system;

  /// Parses a type string from the database, defaulting to [text].
  static MessageType fromName(String? name) => MessageType.values.firstWhere(
    (type) => type.name == name,
    orElse: () => MessageType.text,
  );
}

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
    this.type = MessageType.text,
    this.content,
    this.attachments = const [],
    this.replyToId,
    this.clientId,
    this.editedAt,
    this.deletedAt,
    this.pending = false,
    this.extra = const <String, dynamic>{},
  });

  /// Builds a [Message] from a `messages` row.
  factory Message.fromJson(Map<String, dynamic> json) => Message(
    id: json['id'] as String,
    roomId: json['room_id'] as String,
    senderId: json['sender_id'] as String,
    type: MessageType.fromName(json['type'] as String?),
    content: json['content'] as String?,
    attachments: [
      for (final a in (json['attachments'] as List? ?? const []))
        Attachment.fromJson(Map<String, dynamic>.from(a as Map)),
    ],
    replyToId: json['reply_to'] as String?,
    clientId: json['client_id'] as String?,
    createdAt: DateTime.parse(json['created_at'] as String).toUtc(),
    editedAt: json['edited_at'] == null
        ? null
        : DateTime.parse(json['edited_at'] as String).toUtc(),
    deletedAt: json['deleted_at'] == null
        ? null
        : DateTime.parse(json['deleted_at'] as String).toUtc(),
    extra: {
      if (json['encrypted'] != null)
        'encrypted': Map<String, dynamic>.from(json['encrypted'] as Map),
    },
  );

  /// Server primary key (or a temporary `tmp:` id while [pending]).
  final String id;

  /// The room this message belongs to.
  final String roomId;

  /// The author's user id.
  final String senderId;

  /// What kind of content this message carries.
  final MessageType type;

  /// Text body / caption, if any.
  final String? content;

  /// Attachment descriptors.
  final List<Attachment> attachments;

  /// The id of the message this one replies to, if any.
  final String? replyToId;

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

  /// Extra, non-core columns carried verbatim to/from the row (e.g. the
  /// `encrypted` payload added by `supabase_chat_e2ee`). Keeps the core schema
  /// agnostic: anything here is merged into the insert and read back as-is.
  final Map<String, dynamic> extra;

  /// Whether the message has been soft-deleted.
  bool get isDeleted => deletedAt != null;

  /// Whether the message has been edited.
  bool get isEdited => editedAt != null;

  /// Whether this message quotes another.
  bool get isReply => replyToId != null;

  /// The insert payload for `messages` (server-managed fields omitted).
  Map<String, dynamic> toInsert() => {
    'room_id': roomId,
    'sender_id': senderId,
    'type': type.name,
    if (content != null) 'content': content,
    'attachments': [for (final a in attachments) a.toJson()],
    if (replyToId != null) 'reply_to': replyToId,
    if (clientId != null) 'client_id': clientId,
    ...extra,
  };

  /// Returns a copy with selected fields replaced.
  Message copyWith({String? id, bool? pending}) => Message(
    id: id ?? this.id,
    roomId: roomId,
    senderId: senderId,
    type: type,
    content: content,
    attachments: attachments,
    replyToId: replyToId,
    clientId: clientId,
    createdAt: createdAt,
    editedAt: editedAt,
    deletedAt: deletedAt,
    pending: pending ?? this.pending,
    extra: extra,
  );

  @override
  bool operator ==(Object other) => other is Message && other.id == id;

  @override
  int get hashCode => id.hashCode;

  @override
  String toString() => 'Message($id, $type, pending: $pending)';
}
