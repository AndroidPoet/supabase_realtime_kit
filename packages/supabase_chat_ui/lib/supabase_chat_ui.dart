/// Optional Flutter widgets for `supabase_chat`.
///
/// `ChatView` is a complete drop-in chat body; the pieces (`MessageBubble`,
/// `MessageComposer`, `TypingIndicator`) are exported for custom layouts.
///
/// This package is **MIT** and carries **no** encryption dependency. For an
/// end-to-end-encrypted screen, pair the presentational `EncryptedChatBanner`
/// with your chosen E2EE room — `supabase_chat_seal` (MIT) or
/// `supabase_chat_e2ee` (GPL); see the `EncryptedChatView` recipe in the
/// `supabase_chat_e2ee` README.
library;

export 'src/chat_view.dart';
export 'src/encrypted_chat_banner.dart';
export 'src/message_bubble.dart';
export 'src/message_composer.dart';
export 'src/typing_indicator.dart';
