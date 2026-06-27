import 'package:flutter/material.dart';
import 'package:supabase_chat/supabase_chat.dart';

/// A single chat message bubble: renders text, replies, media attachments,
/// reactions, and edited/deleted states, aligned and tinted by authorship.
class MessageBubble extends StatelessWidget {
  /// Creates a message bubble for [message].
  const MessageBubble({
    required this.message,
    required this.isMine,
    super.key,
    this.repliedTo,
    this.reactions = const [],
    this.onLongPress,
  });

  /// The message to render.
  final Message message;

  /// Whether the current user authored [message].
  final bool isMine;

  /// The message [message] replies to, resolved for quoting (if any).
  final Message? repliedTo;

  /// Reactions on this message.
  final List<Reaction> reactions;

  /// Called on long-press (e.g. to react or reply).
  final void Function(Message message)? onLongPress;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final bg = isMine ? scheme.primary : scheme.surfaceContainerHighest;
    final fg = isMine ? scheme.onPrimary : scheme.onSurface;

    return Align(
      alignment: isMine ? Alignment.centerRight : Alignment.centerLeft,
      child: Opacity(
        opacity: message.pending ? 0.6 : 1, // dim until the server echo lands
        child: GestureDetector(
          onLongPress: onLongPress == null ? null : () => onLongPress!(message),
          child: Container(
            margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 3),
            padding: const EdgeInsets.all(10),
            constraints: const BoxConstraints(maxWidth: 320),
            decoration: BoxDecoration(
              color: bg,
              borderRadius: BorderRadius.only(
                topLeft: const Radius.circular(18),
                topRight: const Radius.circular(18),
                bottomLeft: Radius.circular(isMine ? 18 : 4),
                bottomRight: Radius.circular(isMine ? 4 : 18),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                if (repliedTo != null) _ReplyQuote(message: repliedTo!, fg: fg),
                if (!message.isDeleted) _media(context, fg),
                _body(context, fg),
                if (reactions.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  _Reactions(reactions: reactions),
                ],
                const SizedBox(height: 2),
                _meta(fg),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _body(BuildContext context, Color fg) {
    final text = message.isDeleted
        ? 'Message deleted'
        : (message.content ?? '');
    if (text.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 2),
      child: Text(
        text,
        style: TextStyle(
          color: fg,
          fontStyle: message.isDeleted ? FontStyle.italic : FontStyle.normal,
        ),
      ),
    );
  }

  Widget _media(BuildContext context, Color fg) {
    if (message.attachments.isEmpty) return const SizedBox.shrink();
    final attachment = message.attachments.first;

    if (message.type == MessageType.image && attachment.url != null) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(10),
        child: Image.network(
          attachment.url!,
          fit: BoxFit.cover,
          errorBuilder: (_, _, _) => _fileRow(attachment, fg),
        ),
      );
    }
    return _fileRow(attachment, fg);
  }

  Widget _fileRow(Attachment attachment, Color fg) {
    final icon = switch (message.type) {
      MessageType.video => Icons.videocam_rounded,
      MessageType.audio => Icons.mic_rounded,
      _ => Icons.insert_drive_file_rounded,
    };
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 18, color: fg),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              attachment.name ?? attachment.path.split('/').last,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: fg),
            ),
          ),
        ],
      ),
    );
  }

  Widget _meta(Color fg) {
    final time = _formatTime(message.createdAt.toLocal());
    return Align(
      alignment: Alignment.centerRight,
      child: Text(
        message.isEdited ? 'edited · $time' : time,
        style: TextStyle(color: fg.withValues(alpha: 0.7), fontSize: 10),
      ),
    );
  }

  String _formatTime(DateTime t) {
    final h = t.hour.toString().padLeft(2, '0');
    final m = t.minute.toString().padLeft(2, '0');
    return '$h:$m';
  }
}

class _ReplyQuote extends StatelessWidget {
  const _ReplyQuote({required this.message, required this.fg});

  final Message message;
  final Color fg;

  @override
  Widget build(BuildContext context) {
    final preview = message.isDeleted
        ? 'Message deleted'
        : (message.content ?? _typeLabel(message.type));
    return Container(
      margin: const EdgeInsets.only(bottom: 4),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: fg.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(6),
        border: Border(
          left: BorderSide(color: fg.withValues(alpha: 0.5), width: 3),
        ),
      ),
      child: Text(
        preview,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(color: fg.withValues(alpha: 0.85), fontSize: 12),
      ),
    );
  }

  String _typeLabel(MessageType type) => switch (type) {
    MessageType.image => '📷 Photo',
    MessageType.video => '🎥 Video',
    MessageType.audio => '🎙️ Audio',
    MessageType.file => '📎 File',
    _ => 'Message',
  };
}

class _Reactions extends StatelessWidget {
  const _Reactions({required this.reactions});

  final List<Reaction> reactions;

  @override
  Widget build(BuildContext context) {
    final counts = <String, int>{};
    for (final reaction in reactions) {
      counts[reaction.emoji] = (counts[reaction.emoji] ?? 0) + 1;
    }
    final scheme = Theme.of(context).colorScheme;
    return Wrap(
      spacing: 4,
      children: [
        for (final entry in counts.entries)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: scheme.surface,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Text(
              entry.value > 1 ? '${entry.key} ${entry.value}' : entry.key,
              style: const TextStyle(fontSize: 12),
            ),
          ),
      ],
    );
  }
}
