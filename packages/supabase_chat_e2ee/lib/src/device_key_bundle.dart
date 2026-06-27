import 'dart:convert';
import 'dart:typed_data';

/// A single one-time prekey: its server id and public key bytes.
typedef PreKeyEntry = ({int id, Uint8List publicKey});

/// The *public* key material a device publishes so others can start an
/// encrypted session with it. Contains no private keys — only the identity
/// key, the signed prekey (+ signature) and a set of one-time prekeys.
///
/// This is what lives in the `device_keys` table and what
/// `PreKeyDirectory.fetch` returns.
class DeviceKeyBundle {
  /// Creates a bundle from raw public key material.
  const DeviceKeyBundle({
    required this.registrationId,
    required this.deviceId,
    required this.identityKey,
    required this.signedPreKeyId,
    required this.signedPreKey,
    required this.signedPreKeySignature,
    required this.preKeys,
  });

  /// Rebuilds a bundle from its [toJson] form.
  factory DeviceKeyBundle.fromJson(Map<String, dynamic> json) =>
      DeviceKeyBundle(
        registrationId: json['registration_id'] as int,
        deviceId: json['device_id'] as int,
        identityKey: _b64d(json['identity_key'] as String),
        signedPreKeyId: json['signed_pre_key_id'] as int,
        signedPreKey: _b64d(json['signed_pre_key'] as String),
        signedPreKeySignature: _b64d(
          json['signed_pre_key_signature'] as String,
        ),
        preKeys: [
          for (final p in (json['pre_keys'] as List? ?? const []))
            (id: (p as Map)['id'] as int, publicKey: _b64d(p['key'] as String)),
        ],
      );

  /// The device's Signal registration id.
  final int registrationId;

  /// The device id (1 for single-device setups).
  final int deviceId;

  /// The long-term identity public key bytes.
  final Uint8List identityKey;

  /// The signed prekey id.
  final int signedPreKeyId;

  /// The signed prekey public key bytes.
  final Uint8List signedPreKey;

  /// The identity-key signature over [signedPreKey].
  final Uint8List signedPreKeySignature;

  /// One-time prekeys still available for new sessions.
  final List<PreKeyEntry> preKeys;

  /// Serializes the bundle to a JSON-safe map (bytes as base64).
  Map<String, dynamic> toJson() => {
    'registration_id': registrationId,
    'device_id': deviceId,
    'identity_key': _b64e(identityKey),
    'signed_pre_key_id': signedPreKeyId,
    'signed_pre_key': _b64e(signedPreKey),
    'signed_pre_key_signature': _b64e(signedPreKeySignature),
    'pre_keys': [
      for (final p in preKeys) {'id': p.id, 'key': _b64e(p.publicKey)},
    ],
  };

  /// Returns a copy carrying only the first available one-time prekey, used
  /// when handing a single bundle to a session builder.
  DeviceKeyBundle takeOnePreKey() => DeviceKeyBundle(
    registrationId: registrationId,
    deviceId: deviceId,
    identityKey: identityKey,
    signedPreKeyId: signedPreKeyId,
    signedPreKey: signedPreKey,
    signedPreKeySignature: signedPreKeySignature,
    preKeys: preKeys.isEmpty ? const [] : [preKeys.first],
  );
}

String _b64e(Uint8List bytes) => base64Encode(bytes);

Uint8List _b64d(String s) => base64Decode(s);
