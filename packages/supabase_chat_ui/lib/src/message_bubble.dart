import 'package:flutter/material.dart';
import 'package:supabase_chat/supabase_chat.dart';

/// A single chat message bubble, aligned and tinted by authorship.
class MessageBubble extends StatelessWidget {
  /// Creates a message bubble for [message].
  const MessageBubble({required this.message, required this.isMine, super.key});

  /// The message to render.
  final Message message;

  /// Whether the current user authored [message].
  final bool isMine;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final bg = isMine ? scheme.primary : scheme.surfaceContainerHighest;
    final fg = isMine ? scheme.onPrimary : scheme.onSurface;

    return Align(
      alignment: isMine ? Alignment.centerRight : Alignment.centerLeft,
      child: Opacity(
        opacity: message.pending ? 0.6 : 1, // dim until the server echo lands
        child: Container(
          margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 3),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
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
            crossAxisAlignment: CrossAxisAlignment.end,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                message.isDeleted ? 'Message deleted' : (message.content ?? ''),
                style: TextStyle(
                  color: fg,
                  fontStyle: message.isDeleted
                      ? FontStyle.italic
                      : FontStyle.normal,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                _formatTime(message.createdAt.toLocal()),
                style: TextStyle(
                  color: fg.withValues(alpha: 0.7),
                  fontSize: 10,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _formatTime(DateTime t) {
    final h = t.hour.toString().padLeft(2, '0');
    final m = t.minute.toString().padLeft(2, '0');
    return '$h:$m';
  }
}
