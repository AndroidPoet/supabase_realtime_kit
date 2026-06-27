import 'dart:convert';
import 'dart:typed_data';

import 'package:libsignal_protocol_dart/libsignal_protocol_dart.dart';
import 'package:supabase_chat_e2ee/src/cipher_envelope.dart';
import 'package:supabase_chat_e2ee/src/e2ee_identity.dart';
import 'package:supabase_chat_e2ee/src/prekey_directory.dart';
import 'package:supabase_chat_e2ee/src/safety_number.dart';
import 'package:supabase_chat_e2ee/src/trust_store.dart';
import 'package:supabase_realtime_kit/supabase_realtime_kit.dart';

/// Thrown when a recipient has no published keys, so no session can be built.
class MissingKeysException implements Exception {
  /// Creates the exception for [userId].
  const MissingKeysException(this.userId);

  /// The user whose keys could not be found.
  final String userId;

  @override
  String toString() => 'MissingKeysException: no published keys for $userId';
}

/// Thrown when a peer's identity key does not match the one we trusted before —
/// the hallmark of a man-in-the-middle attempt (or a legitimate reinstall).
///
/// Messaging stays blocked until the user re-verifies the safety number and
/// calls `E2eeManager.acceptIdentityChange`.
class IdentityChangedException implements Exception {
  /// Creates the exception for [userId].
  const IdentityChangedException(this.userId);

  /// The peer whose identity key changed.
  final String userId;

  @override
  String toString() =>
      'IdentityChangedException: identity key for $userId changed; '
      're-verify the safety number before continuing';
}

/// Thrown by [E2eeManager.encryptFor] in strict mode when a recipient's safety
/// number has not been verified yet.
class UnverifiedRecipientException implements Exception {
  /// Creates the exception for [userId].
  const UnverifiedRecipientException(this.userId);

  /// The unverified recipient.
  final String userId;

  @override
  String toString() =>
      'UnverifiedRecipientException: refusing to encrypt to unverified peer '
      '$userId (verify the safety number, or disable requireVerified)';
}

/// Orchestrates Signal sessions on top of an [E2eeIdentity] and a
/// [PreKeyDirectory]: builds sessions on demand, encrypts a plaintext for a set
/// of recipients (one ciphertext each), decrypts incoming ciphertext, and
/// manages identity verification.
///
/// In the default **strict** mode ([requireVerified] = `true`) it refuses to
/// encrypt to a peer until the user has confirmed that peer's safety number,
/// and it rejects any later identity-key change as tampering. For drop-in chat
/// use, wrap a room with `EncryptedChatRoom`, which calls into a manager.
class E2eeManager {
  /// Creates a manager for [currentUserId] using [identity] and [directory].
  ///
  /// With [requireVerified] (default `true`), [encryptFor] throws
  /// [UnverifiedRecipientException] for any not-yet-verified recipient.
  E2eeManager({
    required this.identity,
    required this.directory,
    required this.currentUserId,
    this.requireVerified = true,
  });

  /// This device's local key material and trust ledger.
  final E2eeIdentity identity;

  /// Where recipient public bundles are fetched from / published to.
  final PreKeyDirectory directory;

  /// The local user's id (the author of messages this manager encrypts).
  final String currentUserId;

  /// Whether plaintext may only be encrypted to verified recipients.
  final bool requireVerified;

  SignalProtocolStore get _store => identity.store;
  TrustStore get _trust => identity.trustStore;

  SignalProtocolAddress _addressOf(String userId, int deviceId) =>
      SignalProtocolAddress(userId, deviceId);

  /// Publishes this device's public bundle so others can message it.
  Future<void> publishOwnKeys() async {
    final bundle = await identity.publicBundle();
    final result = await directory.publish(currentUserId, bundle);
    if (result case Err(:final error)) {
      throw StateError('failed to publish keys: $error');
    }
  }

  /// Ensures a session with [userId]'s [deviceId] exists, fetching and
  /// processing their published bundle if needed.
  ///
  /// Throws [IdentityChangedException] if the fetched key conflicts with a
  /// previously trusted one, and [MissingKeysException] if the peer has none.
  Future<void> ensureSession(String userId, {int deviceId = 1}) async {
    final address = _addressOf(userId, deviceId);
    if (await _store.containsSession(address)) return;

    final fetched = await directory.fetch(userId);
    final bundle = switch (fetched) {
      Ok(:final value) => value,
      Err(:final error) => throw StateError('failed to fetch keys: $error'),
    };
    if (bundle == null) throw MissingKeysException(userId);

    final one = bundle.takeOnePreKey();
    final preKey = one.preKeys.isEmpty ? null : one.preKeys.first;
    final preKeyBundle = PreKeyBundle(
      one.registrationId,
      deviceId,
      preKey?.id,
      preKey == null ? null : Curve.decodePoint(preKey.publicKey, 0),
      one.signedPreKeyId,
      Curve.decodePoint(one.signedPreKey, 0),
      one.signedPreKeySignature,
      IdentityKey.fromBytes(one.identityKey, 0),
    );

    try {
      await SessionBuilder.fromSignalStore(
        _store,
        address,
      ).processPreKeyBundle(preKeyBundle);
    } on UntrustedIdentityException {
      throw IdentityChangedException(userId);
    }
  }

  /// The current [TrustLevel] for [userId].
  Future<TrustLevel> verificationLevel(String userId) async {
    final entry = await _trust.get(userId);
    return entry?.level ?? TrustLevel.unknown;
  }

  /// Whether [userId]'s identity has been verified out of band.
  Future<bool> isVerified(String userId) async =>
      (await verificationLevel(userId)) == TrustLevel.verified;

  /// Computes the [SafetyNumber] between the current user and [userId] so the
  /// two can compare it out of band. Establishes a session first if needed, so
  /// the number reflects the exact key in use.
  Future<SafetyNumber> safetyNumber(String userId, {int deviceId = 1}) async {
    await ensureSession(userId, deviceId: deviceId);
    final remote = await _store.getIdentity(_addressOf(userId, deviceId));
    if (remote == null) throw MissingKeysException(userId);
    return SafetyNumber.compute(
      localUserId: currentUserId,
      localIdentityKey: identity.identityKey,
      remoteUserId: userId,
      remoteIdentityKey: remote,
    );
  }

  /// Marks [userId]'s currently-recorded identity as verified. Call this only
  /// after the user has confirmed the [safetyNumber] out of band.
  Future<void> markVerified(String userId) async {
    final entry = await _trust.get(userId);
    if (entry == null) {
      throw StateError('no identity recorded for $userId; call safetyNumber()');
    }
    await _trust.put(userId, entry.withLevel(TrustLevel.verified));
  }

  /// Accepts a changed identity for [userId] (e.g. after a verified reinstall):
  /// forgets the old key and session so the next contact re-runs trust-on-
  /// first-use. The peer starts unverified again until re-confirmed.
  Future<void> acceptIdentityChange(String userId) async {
    await _trust.remove(userId);
    await _store.deleteAllSessions(userId);
  }

  /// Encrypts [plaintext] once per recipient in [userIds], returning a map of
  /// `userId -> envelope JSON`. Sessions are established as needed.
  ///
  /// In strict mode, throws [UnverifiedRecipientException] for any recipient
  /// whose safety number has not been verified.
  ///
  /// Do not include [currentUserId] for the *same* device: Signal's ratchet
  /// can't encrypt-to-self on one address. To let the sender re-read their own
  /// messages, cache the plaintext locally (as `EncryptedChatRoom` does);
  /// cross-device self-sync would use a distinct device id (future work).
  Future<Map<String, dynamic>> encryptFor(
    Iterable<String> userIds,
    String plaintext, {
    int deviceId = 1,
  }) async {
    final bytes = Uint8List.fromList(utf8.encode(plaintext));
    final out = <String, dynamic>{};
    for (final userId in userIds) {
      await ensureSession(userId, deviceId: deviceId);
      if (requireVerified && !await isVerified(userId)) {
        throw UnverifiedRecipientException(userId);
      }
      final cipher = SessionCipher.fromStore(
        _store,
        _addressOf(userId, deviceId),
      );
      final message = await cipher.encrypt(bytes);
      out[userId] = CipherEnvelope.fromMessage(message).toJson();
    }
    return out;
  }

  /// Decrypts the [envelopeJson] addressed to the current user, sent by
  /// [fromUserId]. Returns the recovered plaintext.
  ///
  /// Throws [IdentityChangedException] if the sender's identity key changed.
  /// A Signal ciphertext can only be decrypted **once** (the ratchet advances),
  /// so callers must not re-decrypt the same message — cache the result.
  Future<String> decrypt(
    Map<String, dynamic> envelopeJson,
    String fromUserId, {
    int deviceId = 1,
  }) async {
    final envelope = CipherEnvelope.fromJson(envelopeJson);
    final address = _addressOf(fromUserId, deviceId);
    final cipher = SessionCipher.fromStore(_store, address);
    try {
      final Uint8List plain;
      if (envelope.isPreKey) {
        plain = await cipher.decrypt(PreKeySignalMessage(envelope.body));
      } else {
        plain = await cipher.decryptFromSignal(
          SignalMessage.fromSerialized(envelope.body),
        );
      }
      return utf8.decode(plain);
    } on UntrustedIdentityException {
      throw IdentityChangedException(fromUserId);
    }
  }
}
