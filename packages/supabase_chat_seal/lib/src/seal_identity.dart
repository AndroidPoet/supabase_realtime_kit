import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';

/// A long-term X25519 key pair identifying one device/user.
///
/// The **public** key is published to a `PublicKeyDirectory` so peers can reach
/// you; the **private** key never leaves the device. Persist
/// [exportPrivateKey] + [publicKey] yourself (secure storage / encrypted file)
/// and use [restore] so your identity — and therefore your safety numbers and
/// verifications — survive restarts. This package bundles no platform storage.
class SealIdentity {
  SealIdentity._(this.keyPair, this.publicKey);

  /// The X25519 key-exchange algorithm instance.
  static final X25519 algorithm = Cryptography.instance.x25519();

  /// The underlying key pair (private material stays inside).
  final SimpleKeyPair keyPair;

  /// The 32-byte X25519 public key, safe to publish.
  final Uint8List publicKey;

  /// Generates a fresh identity.
  static Future<SealIdentity> generate() async {
    final keyPair = await algorithm.newKeyPair();
    final pub = await keyPair.extractPublicKey();
    return SealIdentity._(keyPair, Uint8List.fromList(pub.bytes));
  }

  /// Restores an identity from a previously [exportPrivateKey]ed private key
  /// and its matching [publicKey].
  static Future<SealIdentity> restore({
    required Uint8List privateKey,
    required Uint8List publicKey,
  }) async {
    final keyPair = SimpleKeyPairData(
      privateKey,
      publicKey: SimplePublicKey(publicKey, type: KeyPairType.x25519),
      type: KeyPairType.x25519,
    );
    return SealIdentity._(keyPair, publicKey);
  }

  /// Exports the 32-byte private key for your own secure persistence.
  Future<Uint8List> exportPrivateKey() async {
    final data = await keyPair.extract();
    return Uint8List.fromList(data.bytes);
  }
}
