// A command-line walkthrough is expected to print to stdout.
// ignore_for_file: avoid_print
//
// A backend-free, runnable demonstration of the permissive (MIT) sealed-box
// end-to-end encryption.
//
//   dart run example/seal_demo.dart
//
// Two parties (Alice and Bob) share one in-memory key directory standing in
// for Supabase. The demo shows: X25519 key publish, matching safety numbers
// (MITM check), strict mode refusing to send before verification, the exact
// ciphertext the server would store, decryption, the sender re-reading its own
// message (a property of the static pairwise key), and a key-swap rejection.
import 'dart:convert';

import 'package:supabase_chat_seal/supabase_chat_seal.dart';

const _alice = 'alice';
const _bob = 'bob';

Future<void> main() async {
  _h('1. Generate X25519 identities (one-time, per install)');
  final alice = SealManager(
    identity: await SealIdentity.generate(),
    directory: _directory,
    currentUserId: _alice,
  );
  final bob = SealManager(
    identity: await SealIdentity.generate(),
    directory: _directory,
    currentUserId: _bob,
  );
  print('  Alice and Bob each generated a long-term key pair.');

  _h('2. Publish PUBLIC keys to the directory');
  await alice.publishOwnKeys();
  await bob.publishOwnKeys();
  print('  Only public keys are uploaded. Private keys never leave.');

  _h('3. Safety numbers (man-in-the-middle check)');
  final aliceSeesBob = await alice.safetyNumber(_bob);
  final bobSeesAlice = await bob.safetyNumber(_alice);
  print('  Alice computes: ${aliceSeesBob.formatted}');
  print('  Bob computes:   ${bobSeesAlice.formatted}');
  final match = aliceSeesBob.digits == bobSeesAlice.digits;
  print('  Identical on both sides? $match  ${match ? '✅' : '❌'}');

  _h('4. Strict mode: sending before verification is refused');
  try {
    await alice.encryptFor([_bob], 'should not go through');
    print('  ❌ unexpectedly allowed');
  } on UnverifiedRecipientException catch (e) {
    print('  Blocked as expected: $e');
  }

  _h('5. Verify the peer, then encrypt');
  await alice.markVerified(_bob);
  await bob.markVerified(_alice);
  const plaintext = 'hello Bob — sealed-box encrypted 🔐';
  print('  Alice types: "$plaintext"');
  final envelope = await alice.encryptFor([_bob], plaintext);

  _h('6. What the Supabase server actually stores');
  final forBob = envelope[_bob] as Map<String, dynamic>;
  final blob = forBob['b'] as String;
  print('  messages.encrypted -> ${jsonEncode(envelope)}');
  print('  Ciphertext (base64, ${blob.length} chars):');
  print('    ${blob.substring(0, blob.length.clamp(0, 72))}...');
  print('  The server sees only this blob — no plaintext, ever.');

  _h('7. Bob decrypts with his private key');
  final recovered = await bob.decrypt(forBob, _alice);
  print('  Bob reads: "$recovered"');
  print('  Round-trip OK? ${recovered == plaintext ? '✅' : '❌'}');

  _h('8. Alice re-reads her own message (static pairwise key)');
  final self = await alice.decrypt(forBob, _bob);
  print('  Alice reads back: "$self"  ${self == plaintext ? '✅' : '❌'}');

  _h('9. Tamper check: a swapped public key is rejected');
  final imposter = SealManager(
    identity: await SealIdentity.generate(),
    directory: _directory,
    currentUserId: _bob,
  );
  await imposter.publishOwnKeys(); // overwrites Bob's published key
  print("  An attacker swapped Bob's key in the directory.");
  try {
    await alice.safetyNumber(_bob);
    print('  ❌ swapped key accepted');
  } on IdentityChangedException catch (e) {
    print('  Rejected as expected: $e');
  }

  print('\nDone. The server only ever held ciphertext.');
}

final InMemoryPublicKeyDirectory _directory = InMemoryPublicKeyDirectory();

void _h(String title) => print('\n=== $title ===');
