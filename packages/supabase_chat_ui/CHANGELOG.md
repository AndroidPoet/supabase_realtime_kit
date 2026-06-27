## 0.1.0

- Initial release.
- `ChatView` drop-in chat body (list + typing indicator + composer).
- `MessageBubble`, `MessageComposer`, `TypingIndicator` building blocks.
- `EncryptedChatBanner` presentational verification banner (no crypto
  dependency — works above either E2EE flavor).
- Package is MIT with **no** encryption dependency, so it can't pull GPL code
  into your app. The E2EE-bound `EncryptedChatView` ships as a recipe in the
  `supabase_chat_e2ee` README instead.
