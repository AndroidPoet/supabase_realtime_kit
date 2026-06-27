import 'package:flutter/material.dart';

/// A compact "X is typing…" line. Renders nothing when [userIds] is empty.
class TypingIndicator extends StatelessWidget {
  /// Creates a typing indicator for the given [userIds].
  const TypingIndicator({required this.userIds, super.key, this.nameFor});

  /// The ids of users currently typing.
  final List<String> userIds;

  /// Optional resolver from a user id to a display name.
  final String Function(String userId)? nameFor;

  @override
  Widget build(BuildContext context) {
    if (userIds.isEmpty) return const SizedBox.shrink();
    final names = userIds.map((id) => nameFor?.call(id) ?? 'Someone').toList();
    final label = switch (names.length) {
      1 => '${names.first} is typing…',
      2 => '${names[0]} and ${names[1]} are typing…',
      _ => 'Several people are typing…',
    };
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 2, 16, 6),
      child: Align(
        alignment: Alignment.centerLeft,
        child: Text(
          label,
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
            fontStyle: FontStyle.italic,
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
      ),
    );
  }
}
