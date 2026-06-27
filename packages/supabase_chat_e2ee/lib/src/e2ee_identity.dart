import 'dart:typed_data';

import 'package:libsignal_protocol_dart/libsignal_protocol_dart.dart';
import 'package:supabase_chat_e2ee/src/device_key_bundle.dart';
import 'package:supabase_chat_e2ee/src/trust_store.dart';
import 'package:supabase_chat_e2ee/src/verifying_signal_store.dart';

/// A device's local Signal identity: the long-term key pair, registration id,
/// and a [VerifyingSignalStore] holding session/prekey state plus the peer
/// trust ledger.
///
/// The session store is **pluggable** (BYO persistence). [generate] seeds an
/// in-memory store for convenience; persist [exportIdentityKeyPair] +
/// [registrationId] + the [TrustStore] and use [restore] so the identity (and
/// therefore safety numbers and verifications) stay stable across restarts.
/// Per project policy this package never bundles a platform secure-storage
/// dependency.
class E2eeIdentity {
  /// Wraps already-generated key material around a [store].
  E2eeIdentity({
    required this.store,
    required this.identityKeyPair,
    required this.registrationId,
    this.deviceId = 1,
  });

  /// Generates a fresh identity and seeds a [VerifyingSignalStore] with
  /// [preKeyCount] one-time prekeys and a signed prekey.
  ///
  /// Pass a persistent [trustStore] to keep verifications across restarts; the
  /// default is in-memory (verifications lost on restart).
  static Future<E2eeIdentity> generate({
    int preKeyCount = 100,
    int deviceId = 1,
    TrustStore? trustStore,
  }) async {
    final identityKeyPair = generateIdentityKeyPair();
    final registrationId = generateRegistrationId(false);
    return _seed(
      identityKeyPair: identityKeyPair,
      registrationId: registrationId,
      deviceId: deviceId,
      preKeyCount: preKeyCount,
      trustStore: trustStore ?? InMemoryTrustStore(),
    );
  }

  /// Restores an identity from its persisted [identityKeyPair] bytes (see
  /// [exportIdentityKeyPair]) and [registrationId], keeping the same long-term
  /// key so safety numbers and peer verifications remain valid.
  ///
  /// Fresh one-time prekeys are generated and must be re-published. Active
  /// sessions are *not* restored here (they re-establish on next contact); for
  /// full session persistence, supply your own [SignalProtocolStore].
  static Future<E2eeIdentity> restore({
    required Uint8List identityKeyPair,
    required int registrationId,
    required TrustStore trustStore,
    int preKeyCount = 100,
    int deviceId = 1,
  }) async {
    return _seed(
      identityKeyPair: IdentityKeyPair.fromSerialized(identityKeyPair),
      registrationId: registrationId,
      deviceId: deviceId,
      preKeyCount: preKeyCount,
      trustStore: trustStore,
    );
  }

  static Future<E2eeIdentity> _seed({
    required IdentityKeyPair identityKeyPair,
    required int registrationId,
    required int deviceId,
    required int preKeyCount,
    required TrustStore trustStore,
  }) async {
    final store = VerifyingSignalStore(
      identityKeyPair,
      registrationId,
      trustStore,
    );

    final preKeys = generatePreKeys(1, preKeyCount);
    for (final p in preKeys) {
      await store.storePreKey(p.id, p);
    }
    final signedPreKey = generateSignedPreKey(identityKeyPair, 1);
    await store.storeSignedPreKey(signedPreKey.id, signedPreKey);

    return E2eeIdentity(
      store: store,
      identityKeyPair: identityKeyPair,
      registrationId: registrationId,
      deviceId: deviceId,
    );
  }

  /// The session/prekey store with the trust-ledger identity layer.
  final VerifyingSignalStore store;

  /// The long-term identity key pair.
  final IdentityKeyPair identityKeyPair;

  /// This device's Signal registration id.
  final int registrationId;

  /// This device's id (1 for single-device).
  final int deviceId;

  /// The peer trust / verification ledger (shared with [store]).
  TrustStore get trustStore => store.trustStore;

  /// This identity's public key (used to compute safety numbers).
  IdentityKey get identityKey => identityKeyPair.getPublicKey();

  /// Serializes the long-term key pair for persistence. **Secret** — store it
  /// only in platform secure storage / an encrypted file, never in plaintext.
  Uint8List exportIdentityKeyPair() => identityKeyPair.serialize();

  /// Builds the *public* bundle to publish via `PreKeyDirectory.publish`, using
  /// up to [maxPreKeys] of the one-time prekeys currently in the store.
  Future<DeviceKeyBundle> publicBundle({int maxPreKeys = 100}) async {
    final signed = await store.loadSignedPreKey(1);
    final preKeys = <PreKeyEntry>[];
    for (var id = 1; id <= maxPreKeys; id++) {
      if (await store.containsPreKey(id)) {
        final record = await store.loadPreKey(id);
        final publicKey = record.getKeyPair().publicKey.serialize();
        preKeys.add((id: id, publicKey: publicKey));
      }
    }
    return DeviceKeyBundle(
      registrationId: registrationId,
      deviceId: deviceId,
      identityKey: identityKeyPair.getPublicKey().serialize(),
      signedPreKeyId: signed.id,
      signedPreKey: signed.getKeyPair().publicKey.serialize(),
      signedPreKeySignature: signed.signature,
      preKeys: preKeys,
    );
  }
}
