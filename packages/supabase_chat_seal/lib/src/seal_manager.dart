import 'dart:convert';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
import 'package:supabase_chat_seal/src/public_key_directory.dart';
import 'package:supabase_chat_seal/src/safety_number.dart';
import 'package:supabase_chat_seal/src/seal_identity.dart';
import 'package:supabase_chat_seal/src/sealed_envelope.dart';
import 'package:supabase_chat_seal/src/trust_store.dart';
import 'package:supabase_realtime_kit/supabase_realtime_kit.dart';

/// Thrown when a peer has no published public key in the directory.
class MissingKeysException implements Exception {
  /// Creates the exception for [userId].
  const MissingKeysException(this.userId);

  /// The user whose keys are missing.
  final String userId;

  @override
  String toString() => 'MissingKeysException: no published key for $userId';
}

/// Thrown when a peer's public key in the directory differs from the one we
/// previously trusted — a possible server-side key swap (MITM).
class IdentityChangedException implements Exception {
  /// Creates the exception for [userId].
  const IdentityChangedException(this.userId);

  /// The user whose key changed.
  final String userId;

  @override
  String toString() =>
      'IdentityChangedException: identity key for $userId changed; '
      're-verify the safety number before continuing';
}

/// Thrown in strict mode when encrypting to a peer who has not been verified.
class UnverifiedRecipientException implements Exception {
  /// Creates the exception for [userId].
  const UnverifiedRecipientException(this.userId);

  /// The unverified user.
  final String userId;

  @override
  String toString() =>
      'UnverifiedRecipientException: refusing to encrypt to unverified peer '
      '$userId (verify the safety number, or disable requireVerified)';
}

/// Encrypts and decrypts messages for peers using a static X25519 ECDH shared
/// secret per peer, run through HKDF-SHA256 into an AES-256-GCM key.
///
/// In the default **strict** mode ([requireVerified] = `true`) it refuses to
/// encrypt to a peer until you have compared the [safetyNumber] out of band and
/// called [markVerified] — closing the man-in-the-middle window that a
/// compromised key directory would otherwise open.
///
/// ⚠️ The pairwise key is **static**: this box has no forward secrecy. If a
/// device's private key leaks, past ciphertexts to/from that peer are
/// readable. For forward secrecy use the Signal-based `supabase_chat_e2ee`
/// package instead (which is GPL-licensed).
class SealManager {
  /// Creates a manager for [currentUserId] using [identity] and [directory].
  SealManager({
    required this.identity,
    required PublicKeyDirectory directory,
    required this.currentUserId,
    TrustStore? trustStore,
    this.requireVerified = true,
  }) : _directory = directory,
       _trust = trustStore ?? InMemoryTrustStore();

  /// This device's long-term identity.
  final SealIdentity identity;

  /// The local user id (used in safety-number derivation and addressing).
  final String currentUserId;

  /// Whether [encryptFor] requires each recipient to be verified first.
  final bool requireVerified;

  final PublicKeyDirectory _directory;
  final TrustStore _trust;

  static final AesGcm _aead = AesGcm.with256bits();
  static final Hkdf _hkdf = Hkdf(hmac: Hmac.sha256(), outputLength: 32);
  static final List<int> _salt = utf8.encode(
    'supabase_chat_seal/x25519-aesgcm/v1',
  );
  static final List<int> _info = utf8.encode('message-key');

  /// Derived AES keys, cached per peer.
  final Map<String, SecretKey> _sessionKeys = {};

  /// Publishes this device's public key so peers can reach it.
  Future<void> publishOwnKeys() async {
    final result = await _directory.publish(currentUserId, identity.publicKey);
    if (result case Err(:final error, :final stackTrace)) {
      Error.throwWithStackTrace(error, stackTrace ?? StackTrace.current);
    }
  }

  /// Ensures a derived session key exists for [userId], fetching and recording
  /// (trust-on-first-use) the peer's public key. Throws
  /// [IdentityChangedException] if the fetched key differs from one we trust,
  /// or [MissingKeysException] if the peer has not published a key.
  Future<SecretKey> ensureSession(String userId) async {
    final peerKey = await _ensurePeerKey(userId);
    return _sessionKeys[userId] ??= await _deriveKey(peerKey);
  }

  /// The [TrustLevel] currently recorded for [userId].
  Future<TrustLevel> verificationLevel(String userId) async =>
      (await _trust.get(userId))?.level ?? TrustLevel.unknown;

  /// Whether [userId] has been verified.
  Future<bool> isVerified(String userId) async =>
      (await _trust.get(userId))?.level == TrustLevel.verified;

  /// Computes the [SafetyNumber] to compare out of band with [userId]. Also
  /// records the peer's key (trust-on-first-use) so [markVerified] can run.
  Future<SafetyNumber> safetyNumber(String userId) async {
    final peerKey = await _ensurePeerKey(userId);
    return SafetyNumber.compute(
      localUserId: currentUserId,
      localPublicKey: identity.publicKey,
      remoteUserId: userId,
      remotePublicKey: peerKey,
    );
  }

  /// Marks [userId] verified after an out-of-band safety-number comparison.
  /// Call [safetyNumber] (or [ensureSession]) first to record the key.
  Future<void> markVerified(String userId) async {
    final entry = await _trust.get(userId);
    if (entry == null) {
      throw StateError(
        'no key recorded for $userId; call safetyNumber() first',
      );
    }
    await _trust.put(userId, entry.withLevel(TrustLevel.verified));
  }

  /// Accepts a changed key for [userId] (e.g. the peer reinstalled): forgets
  /// the old entry and clears the cached session so the next contact re-runs
  /// trust-on-first-use against the new key (which must be re-verified).
  Future<void> acceptIdentityChange(String userId) async {
    await _trust.remove(userId);
    _sessionKeys.remove(userId);
  }

  /// Encrypts [plaintext] for each of [userIds], returning a map of
  /// `userId -> envelope JSON` to store in the message row. In strict mode this
  /// throws [UnverifiedRecipientException] for any unverified recipient.
  Future<Map<String, dynamic>> encryptFor(
    Iterable<String> userIds,
    String plaintext,
  ) async {
    final out = <String, dynamic>{};
    final bytes = utf8.encode(plaintext);
    for (final userId in userIds) {
      final key = await ensureSession(userId);
      if (requireVerified && !await isVerified(userId)) {
        throw UnverifiedRecipientException(userId);
      }
      final box = await _aead.encrypt(bytes, secretKey: key);
      out[userId] = SealedEnvelope(
        Uint8List.fromList(box.concatenation()),
      ).toJson();
    }
    return out;
  }

  /// Decrypts [envelopeJson] with the pairwise key shared with [peerUserId].
  ///
  /// [peerUserId] is the *other* party of the key pair: for an incoming message
  /// it is the sender; for re-reading your own outgoing message it is the
  /// recipient it was addressed to. Throws [IdentityChangedException] if that
  /// peer's key changed.
  Future<String> decrypt(
    Map<String, dynamic> envelopeJson,
    String peerUserId,
  ) async {
    final key = await ensureSession(peerUserId);
    final envelope = SealedEnvelope.fromJson(envelopeJson);
    final box = SecretBox.fromConcatenation(
      envelope.bytes,
      nonceLength: _aead.nonceLength,
      macLength: 16,
    );
    final clear = await _aead.decrypt(box, secretKey: key);
    return utf8.decode(clear);
  }

  Future<Uint8List> _ensurePeerKey(String userId) async {
    final fetched = await _fetchKey(userId);
    final existing = await _trust.get(userId);
    if (existing != null) {
      if (!bytesEqual(existing.publicKey, fetched)) {
        throw IdentityChangedException(userId);
      }
    } else {
      await _trust.put(
        userId,
        TrustEntry(publicKey: fetched, level: TrustLevel.unverified),
      );
    }
    return fetched;
  }

  Future<Uint8List> _fetchKey(String userId) async {
    final result = await _directory.fetch(userId);
    final key = switch (result) {
      Ok(:final value) => value,
      Err(:final error, :final stackTrace) => Error.throwWithStackTrace(
        error,
        stackTrace ?? StackTrace.current,
      ),
    };
    if (key == null) throw MissingKeysException(userId);
    return key;
  }

  Future<SecretKey> _deriveKey(Uint8List peerKey) async {
    final shared = await SealIdentity.algorithm.sharedSecretKey(
      keyPair: identity.keyPair,
      remotePublicKey: SimplePublicKey(peerKey, type: KeyPairType.x25519),
    );
    return _hkdf.deriveKey(secretKey: shared, nonce: _salt, info: _info);
  }
}
