import 'dart:convert';
import 'dart:typed_data';

import 'package:libsignal_protocol_dart/libsignal_protocol_dart.dart';

/// A serialized Signal ciphertext for one recipient.
///
/// [type] distinguishes the two on-the-wire message kinds: a *prekey* message
/// (the first message of a session, [CiphertextMessage.prekeyType] == 3) versus
/// a normal ratchet message ([CiphertextMessage.whisperType] == 2). [body] is
/// the raw serialized ciphertext.
class CipherEnvelope {
  /// Creates an envelope.
  const CipherEnvelope({required this.type, required this.body});

  /// Wraps a freshly produced [CiphertextMessage].
  factory CipherEnvelope.fromMessage(CiphertextMessage message) =>
      CipherEnvelope(type: message.getType(), body: message.serialize());

  /// Restores an envelope from its [toJson] form.
  factory CipherEnvelope.fromJson(Map<String, dynamic> json) => CipherEnvelope(
    type: json['t'] as int,
    body: base64Decode(json['b'] as String),
  );

  /// The Signal message type (3 = prekey, 2 = whisper).
  final int type;

  /// The serialized ciphertext bytes.
  final Uint8List body;

  /// Whether this is the first (prekey) message of a session.
  bool get isPreKey => type == CiphertextMessage.prekeyType;

  /// Serializes to a JSON-safe map (body as base64).
  Map<String, dynamic> toJson() => {'t': type, 'b': base64Encode(body)};
}
