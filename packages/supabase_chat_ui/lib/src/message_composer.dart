import 'package:flutter/material.dart';

/// A message input row with a send button.
///
/// Reports typing transitions via [onTypingChanged] (debounced to fire on the
/// first keystroke and again when the field is cleared) and submitted text via
/// [onSend].
class MessageComposer extends StatefulWidget {
  /// Creates a composer.
  const MessageComposer({
    required this.onSend,
    super.key,
    this.onTypingChanged,
    this.hintText = 'Message',
  });

  /// Called with the trimmed text when the user sends.
  final ValueChanged<String> onSend;

  /// Called with `true` when the user starts typing and `false` when the field
  /// becomes empty.
  final ValueChanged<bool>? onTypingChanged;

  /// Placeholder text for the input field.
  final String hintText;

  @override
  State<MessageComposer> createState() => _MessageComposerState();
}

class _MessageComposerState extends State<MessageComposer> {
  final TextEditingController _controller = TextEditingController();
  bool _wasTyping = false;

  void _handleChange(String value) {
    final typing = value.trim().isNotEmpty;
    if (typing != _wasTyping) {
      _wasTyping = typing;
      widget.onTypingChanged?.call(typing);
    }
  }

  void _submit() {
    final text = _controller.text.trim();
    if (text.isEmpty) return;
    widget.onSend(text);
    _controller.clear();
    _wasTyping = false;
    widget.onTypingChanged?.call(false);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 6, 8, 6),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Expanded(
              child: TextField(
                controller: _controller,
                minLines: 1,
                maxLines: 5,
                textInputAction: TextInputAction.send,
                onChanged: _handleChange,
                onSubmitted: (_) => _submit(),
                decoration: InputDecoration(
                  hintText: widget.hintText,
                  filled: true,
                  fillColor: scheme.surfaceContainerHighest,
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 10,
                  ),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(24),
                    borderSide: BorderSide.none,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 4),
            IconButton.filled(
              onPressed: _submit,
              icon: const Icon(Icons.arrow_upward_rounded),
            ),
          ],
        ),
      ),
    );
  }
}
