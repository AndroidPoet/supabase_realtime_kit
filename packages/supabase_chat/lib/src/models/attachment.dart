import 'package:meta/meta.dart';

/// A media/file attachment on a message (image, video, audio, document).
///
/// [path] is the object path inside the storage bucket; [url] is an optional
/// resolved (public or signed) URL for display.
@immutable
class Attachment {
  /// Creates an attachment descriptor.
  const Attachment({
    required this.path,
    this.url,
    this.name,
    this.mimeType,
    this.size,
    this.width,
    this.height,
    this.durationMs,
  });

  /// Builds an [Attachment] from its JSON representation.
  factory Attachment.fromJson(Map<String, dynamic> json) => Attachment(
    path: json['path'] as String,
    url: json['url'] as String?,
    name: json['name'] as String?,
    mimeType: json['mime_type'] as String?,
    size: json['size'] as int?,
    width: json['width'] as int?,
    height: json['height'] as int?,
    durationMs: json['duration_ms'] as int?,
  );

  /// Storage object path (e.g. `roomId/uuid-photo.jpg`).
  final String path;

  /// Optional resolved URL for display.
  final String? url;

  /// Original file name.
  final String? name;

  /// MIME type (e.g. `image/jpeg`).
  final String? mimeType;

  /// Size in bytes.
  final int? size;

  /// Pixel width (images/video).
  final int? width;

  /// Pixel height (images/video).
  final int? height;

  /// Duration in milliseconds (audio/video).
  final int? durationMs;

  /// Serializes this attachment (stored in `messages.attachments`).
  Map<String, dynamic> toJson() => {
    'path': path,
    if (url != null) 'url': url,
    if (name != null) 'name': name,
    if (mimeType != null) 'mime_type': mimeType,
    if (size != null) 'size': size,
    if (width != null) 'width': width,
    if (height != null) 'height': height,
    if (durationMs != null) 'duration_ms': durationMs,
  };

  @override
  bool operator ==(Object other) => other is Attachment && other.path == path;

  @override
  int get hashCode => path.hashCode;

  @override
  String toString() => 'Attachment($path)';
}
