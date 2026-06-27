import 'dart:convert';
import 'dart:typed_data';

/// A self-contained AES-GCM ciphertext for one recipient.
///
/// [bytes] is the `SecretBox` concatenation `nonce || ciphertext || mac`, so a
/// single blob carries everything needed to decrypt (given the shared key).
/// Unlike a Signal ciphertext this is **not** one-shot — the pairwise key is
/// static, so the same envelope can be decrypted repeatedly (including by the
/// sender, who can re-derive the key).
class SealedEnvelope {
  /// Wraps the raw concatenated [bytes].
  const SealedEnvelope(this.bytes);

  /// Restores an envelope from its [toJson] form.
  factory SealedEnvelope.fromJson(Map<String, dynamic> json) =>
      SealedEnvelope(base64Decode(json['b'] as String));

  /// `nonce || ciphertext || mac`.
  final Uint8List bytes;

  /// Serializes to a JSON-safe map (`v` = format version, `b` = base64 body).
  Map<String, dynamic> toJson() => {'v': 1, 'b': base64Encode(bytes)};
}
