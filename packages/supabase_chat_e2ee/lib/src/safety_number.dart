import 'dart:convert';
import 'dart:typed_data';

import 'package:libsignal_protocol_dart/libsignal_protocol_dart.dart';

/// Signal's default fingerprint hash iteration count.
const int _fingerprintIterations = 5200;

/// The combined-fingerprint protocol version.
const int _fingerprintVersion = 2;

/// A human-comparable identity fingerprint for a pair of users.
///
/// Both sides compute the **same** 60-digit number (it is order-independent),
/// so two people can read it aloud / compare on screen to confirm there is no
/// man-in-the-middle. This is the out-of-band step that turns
/// trust-on-first-use into cryptographically verified trust.
class SafetyNumber {
  /// Wraps the raw [digits] and the underlying [_scannable] for QR comparison.
  const SafetyNumber(this.digits, this._scannable);

  /// Computes the safety number between the local and remote identities.
  ///
  /// [localUserId]/[remoteUserId] are stable identifiers (used as-is, UTF-8
  /// encoded) and must match on both devices for the numbers to agree.
  factory SafetyNumber.compute({
    required String localUserId,
    required IdentityKey localIdentityKey,
    required String remoteUserId,
    required IdentityKey remoteIdentityKey,
  }) {
    final generator = NumericFingerprintGenerator(_fingerprintIterations);
    final fingerprint = generator.createFor(
      _fingerprintVersion,
      Uint8List.fromList(utf8.encode(localUserId)),
      localIdentityKey,
      Uint8List.fromList(utf8.encode(remoteUserId)),
      remoteIdentityKey,
    );
    return SafetyNumber(
      fingerprint.displayableFingerprint.getDisplayText(),
      fingerprint.scannableFingerprint,
    );
  }

  /// The 60-digit safety number, e.g. `"01234 56789 ..."` once [formatted].
  final String digits;

  final ScannableFingerprint _scannable;

  /// The safety number grouped into space-separated 5-digit blocks for display.
  String get formatted {
    final chunks = <String>[];
    for (var i = 0; i < digits.length; i += 5) {
      final end = (i + 5 <= digits.length) ? i + 5 : digits.length;
      chunks.add(digits.substring(i, end));
    }
    return chunks.join(' ');
  }

  /// Compares this safety number against QR data scanned from a peer's device.
  ///
  /// Returns `true` only if both identities match. Throws if the scanned data
  /// is malformed or uses a different version.
  bool matchesScanned(Uint8List scannedQrData) =>
      _scannable.compareTo(scannedQrData);
}
