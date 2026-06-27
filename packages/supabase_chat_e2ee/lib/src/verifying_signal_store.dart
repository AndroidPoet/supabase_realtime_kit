import 'package:libsignal_protocol_dart/libsignal_protocol_dart.dart';
import 'package:supabase_chat_e2ee/src/trust_store.dart';

/// A Signal store whose identity layer is backed by a [TrustStore], adding two
/// guarantees on top of the in-memory session/prekey storage:
///
/// 1. **Trust on first use, reject silent changes.** The first identity key
///    seen for a peer is recorded. If the key later differs — e.g. a
///    compromised server tries to swap in its own key for a man-in-the-middle —
///    [isTrustedIdentity] returns `false`, so the library throws an
///    `UntrustedIdentityException` and the new key is never saved.
/// 2. **Verification state survives.** Whether the user confirmed a peer's
///    safety number lives in the (persistable) [TrustStore], not in volatile
///    memory.
///
/// All four identity methods are overridden so the library's session machinery
/// consults the trust ledger rather than the base in-memory identity store.
class VerifyingSignalStore extends InMemorySignalProtocolStore {
  /// Wraps [identityKeyPair]/[registrationId] with a [trustStore]-backed
  /// identity layer.
  VerifyingSignalStore(
    super.identityKeyPair,
    super.registrationId,
    this.trustStore,
  ) : _identityKeyPair = identityKeyPair;

  /// The peer-identity / verification ledger.
  final TrustStore trustStore;

  final IdentityKeyPair _identityKeyPair;

  @override
  Future<IdentityKeyPair> getIdentityKeyPair() async => _identityKeyPair;

  @override
  Future<IdentityKey?> getIdentity(SignalProtocolAddress address) async {
    final entry = await trustStore.get(address.getName());
    if (entry == null) return null;
    return IdentityKey.fromBytes(entry.identityKey, 0);
  }

  @override
  Future<bool> isTrustedIdentity(
    SignalProtocolAddress address,
    IdentityKey? identityKey,
    Direction? direction,
  ) async {
    if (identityKey == null) return false;
    final entry = await trustStore.get(address.getName());
    if (entry == null) return true; // trust on first use
    // Reject any later key change outright — the caller must explicitly accept
    // it (TrustStore.remove) after re-verifying the safety number.
    return bytesEqual(entry.identityKey, identityKey.serialize());
  }

  @override
  Future<bool> saveIdentity(
    SignalProtocolAddress address,
    IdentityKey? identityKey,
  ) async {
    if (identityKey == null) return false;
    final userId = address.getName();
    final bytes = identityKey.serialize();
    final entry = await trustStore.get(userId);
    if (entry == null) {
      await trustStore.put(
        userId,
        TrustEntry(identityKey: bytes, level: TrustLevel.unverified),
      );
      return true;
    }
    if (!bytesEqual(entry.identityKey, bytes)) {
      // A change reached save only because it was explicitly accepted; a new
      // key always starts unverified.
      await trustStore.put(
        userId,
        TrustEntry(identityKey: bytes, level: TrustLevel.unverified),
      );
      return true;
    }
    return false;
  }
}
