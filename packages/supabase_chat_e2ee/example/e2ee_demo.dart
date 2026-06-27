// A backend-free, runnable demonstration of end-to-end encryption.
//
//   dart run example/e2ee_demo.dart
//
// Two parties (Alice and Bob) share one in-memory key directory standing in
// for Supabase. The demo shows: X3DH key exchange, matching safety numbers
// (MITM check), strict-mode refusing to send before verification, the exact
// ciphertext the server would store, decryption back to plaintext, and a
// tampered-key rejection.
import 'dart:convert';

import 'package:supabase_chat_e2ee/supabase_chat_e2ee.dart';

const _alice = 'alice';
const _bob = 'bob';

Future<void> main() async {
  _h('1. Generate identities (one-time, per install)');
  final aliceId = await E2eeIdentity.generate();
  final bobId = await E2eeIdentity.generate();
  print('  Alice and Bob each generated a long-term identity key pair.');

  // One shared directory plays the role of the Supabase `device_keys` table.
  final directory = InMemoryPreKeyDirectory();

  final alice = E2eeManager(
    identity: aliceId,
    directory: directory,
    currentUserId: _alice,
  );
  final bob = E2eeManager(
    identity: bobId,
    directory: directory,
    currentUserId: _bob,
  );

  _h('2. Publish public key bundles to the directory');
  await alice.publishOwnKeys();
  await bob.publishOwnKeys();
  print('  Only PUBLIC keys + prekeys are uploaded. Private keys never leave.');

  _h('3. Safety numbers (man-in-the-middle check)');
  final aliceSeesBob = await alice.safetyNumber(_bob);
  final bobSeesAlice = await bob.safetyNumber(_alice);
  print('  Alice computes: ${aliceSeesBob.formatted}');
  print('  Bob computes:   ${bobSeesAlice.formatted}');
  final match = aliceSeesBob.formatted == bobSeesAlice.formatted;
  print('  Identical on both sides? $match  ${match ? '✅' : '❌'}');
  print('  (Comparing these out of band proves nobody sits in the middle.)');

  _h('4. Strict mode: sending before verification is refused');
  try {
    await alice.encryptFor([_bob], 'should not go through');
    print('  ❌ unexpectedly allowed');
  } on UnverifiedRecipientException catch (e) {
    print('  Blocked as expected: $e');
  }

  _h('5. Verify the peer, then encrypt a message');
  await alice.markVerified(_bob);
  await bob.markVerified(_alice);
  const plaintext = 'hello Bob — this is end-to-end encrypted 🔐';
  print('  Alice types: "$plaintext"');
  final envelope = await alice.encryptFor([_bob], plaintext);

  _h('6. What the Supabase server actually stores');
  final forBob = envelope[_bob] as Map<String, dynamic>;
  final ciphertext = forBob['b'] as String;
  print('  messages.encrypted -> ${jsonEncode(envelope)}');
  print('  Ciphertext (base64, ${ciphertext.length} chars):');
  print('    ${ciphertext.substring(0, ciphertext.length.clamp(0, 72))}...');
  print('  The server sees only this blob — no plaintext, ever.');

  _h('7. Bob decrypts with his private key');
  final recovered = await bob.decrypt(forBob, _alice);
  print('  Bob reads: "$recovered"');
  print('  Round-trip OK? ${recovered == plaintext ? '✅' : '❌'}');

  _h('8. A multi-turn conversation (Double Ratchet)');
  for (final line in ['How are you?', 'Doing great 🙂', 'See you tonight!']) {
    final env = await alice.encryptFor([_bob], line);
    final got = await bob.decrypt(env[_bob] as Map<String, dynamic>, _alice);
    print('  Alice -> Bob: "$got"');
  }

  _h('9. Tamper check: a swapped identity key is rejected');
  // Alice already verified the real Bob in steps 3 & 5. Now an attacker
  // republishes "bob" in the directory with a DIFFERENT identity key.
  final imposter = E2eeManager(
    identity: await E2eeIdentity.generate(preKeyCount: 5),
    directory: directory,
    currentUserId: _bob,
  );
  await imposter.publishOwnKeys(); // overwrites Bob's bundle in the directory
  print('  An attacker swapped Bob\'s key in the directory.');

  // Force Alice to contact Bob fresh, so she fetches the now-swapped bundle.
  await alice.identity.store.deleteAllSessions(_bob);
  try {
    await alice.ensureSession(_bob);
    print('  ❌ swapped key accepted');
  } on IdentityChangedException catch (e) {
    print('  Rejected as expected: $e');
    print('  Messaging stays blocked until Alice re-verifies the new key.');
  }

  print('\nDone. The server only ever held ciphertext.');
}

void _h(String title) => print('\n=== $title ===');
