/// Permissive (MIT) end-to-end encryption for `supabase_chat`.
///
/// A sealed box over **X25519 ECDH + HKDF-SHA256 + AES-256-GCM**: the server
/// stores only ciphertext, and `SealedChatRoom` encrypts per-recipient on send
/// and decrypts on receive. Peer public keys are distributed via a
/// `PublicKeyDirectory`; safety numbers + a `TrustStore` defend against a
/// malicious key directory (MITM).
///
/// Unlike the Signal-based `supabase_chat_e2ee` (which is GPL-licensed), this
/// package depends only on permissively licensed crypto (`cryptography`,
/// `crypto`), so it is safe to use in **closed-source** apps. The trade-off is
/// no forward secrecy — the pairwise key is static. Choose this for permissive
/// licensing; choose `supabase_chat_e2ee` for forward secrecy.
library;

export 'src/public_key_directory.dart';
export 'src/safety_number.dart';
export 'src/seal_identity.dart';
export 'src/seal_manager.dart';
export 'src/sealed_chat_room.dart';
export 'src/sealed_envelope.dart';
export 'src/trust_store.dart';
