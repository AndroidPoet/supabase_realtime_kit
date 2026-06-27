## 0.1.0

- Initial release.
- `SupabaseChat` facade: create/list rooms, 1:1 `directRoom`, `uploadAttachment`
  (Storage), open a live `ChatRoom`.
- `ChatRoom`: live messages, optimistic send, replies, edit, soft-delete, emoji
  reactions (`reactionsByMessage`), typing indicators, presence, read receipts,
  unread counts, media (`sendMedia`), pagination.
- Models: `Message` (+ `MessageType`), `Attachment`, `Reaction`, `Room`,
  `ChatMember`/`MemberRole`.
- Pure `TypingTracker` (auto-expiry), unit-tested with `fake_async`.
