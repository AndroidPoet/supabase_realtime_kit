import 'dart:typed_data';

/// How much we trust a peer's identity key.
enum TrustLevel {
  /// We have never seen this user's identity key.
  unknown,

  /// We have the key (trust-on-first-use) but the user has **not** confirmed
  /// the safety number out of band. A network attacker could have supplied
  /// this key; treat messages as not-yet-authenticated.
  unverified,

  /// The user compared and confirmed the safety number out of band. The key is
  /// cryptographically bound to the real peer.
  verified,
}

/// A recorded identity for one peer: the key bytes plus its [TrustLevel].
class TrustEntry {
  /// Creates an entry.
  const TrustEntry({required this.identityKey, required this.level});

  /// The peer's serialized identity public key.
  final Uint8List identityKey;

  /// How much we trust [identityKey].
  final TrustLevel level;

  /// Returns a copy with a new [level].
  TrustEntry withLevel(TrustLevel level) =>
      TrustEntry(identityKey: identityKey, level: level);
}

/// Persists the per-peer identity ledger: which identity key we have seen for
/// each user and whether the user verified it.
///
/// **Bring your own persistence.** Back this with secure storage / SQLite so
/// verifications and trust-on-first-use survive restarts; otherwise a fresh
/// ledger re-trusts whatever the server serves next time. This package never
/// bundles a platform storage dependency.
abstract class TrustStore {
  /// Returns the recorded entry for [userId], or `null` if unseen.
  Future<TrustEntry?> get(String userId);

  /// Stores or replaces the entry for [userId].
  Future<void> put(String userId, TrustEntry entry);

  /// Forgets [userId] entirely (used to accept a legitimate key change, e.g.
  /// the peer reinstalled — the next contact re-runs trust-on-first-use).
  Future<void> remove(String userId);
}

/// A non-persistent [TrustStore] for tests and prototyping. Verifications are
/// lost on restart — do not use in production.
class InMemoryTrustStore implements TrustStore {
  final Map<String, TrustEntry> _entries = {};

  @override
  Future<TrustEntry?> get(String userId) async => _entries[userId];

  @override
  Future<void> put(String userId, TrustEntry entry) async =>
      _entries[userId] = entry;

  @override
  Future<void> remove(String userId) async => _entries.remove(userId);
}

/// Constant-time-ish byte equality (length-checked) for comparing public keys.
bool bytesEqual(Uint8List a, Uint8List b) {
  if (a.length != b.length) return false;
  var diff = 0;
  for (var i = 0; i < a.length; i++) {
    diff |= a[i] ^ b[i];
  }
  return diff == 0;
}
