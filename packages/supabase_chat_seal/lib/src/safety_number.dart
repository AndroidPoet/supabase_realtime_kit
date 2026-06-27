import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

/// Hash iterations folded into each party's fingerprint (matches the order of
/// magnitude Signal uses, for an equivalent brute-force cost).
const int _iterations = 5200;

/// Fingerprint format version, mixed into the hash for domain separation.
const int _version = 1;

/// A human-comparable identity fingerprint for a pair of users.
///
/// Both sides compute the **same** 60-digit number (it is order-independent),
/// so two people can read it aloud / compare on screen to confirm there is no
/// man-in-the-middle. This is the out-of-band step that turns
/// trust-on-first-use into cryptographically verified trust.
///
/// The number is derived purely from the two long-term X25519 public keys (and
/// the stable user ids), so it is stable across sessions and reinstalls of the
/// app as long as the keys do not change.
class SafetyNumber {
  /// Wraps the raw [digits].
  const SafetyNumber(this.digits);

  /// Computes the safety number between the local and remote identities.
  ///
  /// [localUserId]/[remoteUserId] are stable identifiers and must match on both
  /// devices for the numbers to agree.
  factory SafetyNumber.compute({
    required String localUserId,
    required Uint8List localPublicKey,
    required String remoteUserId,
    required Uint8List remotePublicKey,
  }) {
    final local = _fingerprint(localUserId, localPublicKey);
    final remote = _fingerprint(remoteUserId, remotePublicKey);
    // Sort so both sides concatenate in the same order.
    final ordered = [local, remote]..sort();
    return SafetyNumber('${ordered[0]}${ordered[1]}');
  }

  /// The 60-digit safety number (no separators; see [formatted]).
  final String digits;

  /// The safety number grouped into space-separated 5-digit blocks for display.
  String get formatted {
    final chunks = <String>[];
    for (var i = 0; i < digits.length; i += 5) {
      final end = (i + 5 <= digits.length) ? i + 5 : digits.length;
      chunks.add(digits.substring(i, end));
    }
    return chunks.join(' ');
  }

  @override
  String toString() => formatted;
}

/// Produces a stable 30-digit fingerprint for one party.
String _fingerprint(String userId, Uint8List publicKey) {
  var hash = Uint8List.fromList([
    _version,
    ...publicKey,
    ...utf8.encode(userId),
  ]);
  for (var i = 0; i < _iterations; i++) {
    hash = Uint8List.fromList(sha512.convert([...hash, ...publicKey]).bytes);
  }
  // 30 bytes -> six 5-byte chunks -> six 5-digit groups.
  final buffer = StringBuffer();
  for (var offset = 0; offset < 30; offset += 5) {
    buffer.write(_encodeChunk(hash, offset));
  }
  return buffer.toString();
}

/// Encodes 5 bytes (a 40-bit big-endian number) as a zero-padded 5-digit group.
/// Multiplication (not `<<`) keeps the high byte exact on the JS number type.
String _encodeChunk(Uint8List hash, int offset) {
  final value =
      hash[offset] * 0x100000000 +
      (hash[offset + 1] << 24) +
      (hash[offset + 2] << 16) +
      (hash[offset + 3] << 8) +
      hash[offset + 4];
  return (value % 100000).toString().padLeft(5, '0');
}
