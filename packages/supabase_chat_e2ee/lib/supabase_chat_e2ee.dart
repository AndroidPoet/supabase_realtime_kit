/// Opt-in end-to-end encryption for `supabase_chat`, built on the Signal
/// Protocol via `libsignal_protocol_dart`.
///
/// The server stores only ciphertext. Plaintext never leaves the device:
/// `EncryptedChatRoom` encrypts per-recipient on send and decrypts on
/// receive, using sessions established from public bundles served by a
/// `PreKeyDirectory`.
///
/// Key material lives in a pluggable Signal store (`E2eeIdentity`); this
/// package never bundles platform secure-storage — bring your own persistence.
library;

export 'src/cipher_envelope.dart';
export 'src/device_key_bundle.dart';
export 'src/e2ee_identity.dart';
export 'src/e2ee_manager.dart';
export 'src/encrypted_chat_room.dart';
export 'src/prekey_directory.dart';
export 'src/safety_number.dart';
export 'src/trust_store.dart';
export 'src/verifying_signal_store.dart';
