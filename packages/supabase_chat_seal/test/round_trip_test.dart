import 'package:supabase_chat_seal/supabase_chat_seal.dart';
import 'package:test/test.dart';

const alice = 'alice';
const bob = 'bob';

void main() {
  group('SealManager round trip', () {
    late InMemoryPublicKeyDirectory directory;
    late SealManager aliceMgr;
    late SealManager bobMgr;

    setUp(() async {
      directory = InMemoryPublicKeyDirectory();
      aliceMgr = SealManager(
        identity: await SealIdentity.generate(),
        directory: directory,
        currentUserId: alice,
      );
      bobMgr = SealManager(
        identity: await SealIdentity.generate(),
        directory: directory,
        currentUserId: bob,
      );
      await aliceMgr.publishOwnKeys();
      await bobMgr.publishOwnKeys();
    });

    Future<void> verifyBothWays() async {
      await aliceMgr.safetyNumber(bob);
      await bobMgr.safetyNumber(alice);
      await aliceMgr.markVerified(bob);
      await bobMgr.markVerified(alice);
    }

    test('both parties compute the same safety number', () async {
      final a = await aliceMgr.safetyNumber(bob);
      final b = await bobMgr.safetyNumber(alice);
      expect(a.digits, b.digits);
      expect(a.digits.length, 60);
      expect(a.formatted.split(' '), hasLength(12));
    });

    test('strict mode refuses to encrypt to an unverified peer', () async {
      await expectLater(
        aliceMgr.encryptFor([bob], 'secret'),
        throwsA(isA<UnverifiedRecipientException>()),
      );
    });

    test('after verifying, encryption succeeds and decrypts', () async {
      await verifyBothWays();
      final encrypted = await aliceMgr.encryptFor([bob], 'top secret');
      final plain = await bobMgr.decrypt(
        Map<String, dynamic>.from(encrypted[bob] as Map),
        alice,
      );
      expect(plain, 'top secret');
    });

    test('sender can re-read its own message (static pairwise key)', () async {
      await verifyBothWays();
      final encrypted = await aliceMgr.encryptFor([bob], 'note to self too');
      // Alice re-derives the pairwise key with bob to read her own ciphertext.
      final readback = await aliceMgr.decrypt(
        Map<String, dynamic>.from(encrypted[bob] as Map),
        bob,
      );
      expect(readback, 'note to self too');
    });

    test('a two-way conversation decrypts across turns', () async {
      await verifyBothWays();
      for (final text in ['hi', 'how are you', 'great 🙂']) {
        final e = await aliceMgr.encryptFor([bob], text);
        final got = await bobMgr.decrypt(
          Map<String, dynamic>.from(e[bob] as Map),
          alice,
        );
        expect(got, text);
      }
      for (final text in ['hello back', 'doing well']) {
        final e = await bobMgr.encryptFor([alice], text);
        final got = await aliceMgr.decrypt(
          Map<String, dynamic>.from(e[alice] as Map),
          bob,
        );
        expect(got, text);
      }
    });

    test('missing keys throws MissingKeysException', () async {
      await expectLater(
        aliceMgr.encryptFor(['ghost'], 'hi'),
        throwsA(isA<MissingKeysException>()),
      );
    });

    test(
      'a swapped public key is rejected as IdentityChanged (MITM)',
      () async {
        await aliceMgr.safetyNumber(bob);
        await aliceMgr.markVerified(bob);
        await aliceMgr.encryptFor([bob], 'hi real bob');

        // An attacker republishes "bob" with a different key.
        final imposter = SealManager(
          identity: await SealIdentity.generate(),
          directory: directory,
          currentUserId: bob,
        );
        await imposter.publishOwnKeys();

        await expectLater(
          aliceMgr.safetyNumber(bob),
          throwsA(isA<IdentityChangedException>()),
        );
      },
    );

    test('acceptIdentityChange clears trust for a legit re-key', () async {
      await aliceMgr.safetyNumber(bob);
      await aliceMgr.markVerified(bob);

      final reinstalled = SealManager(
        identity: await SealIdentity.generate(),
        directory: directory,
        currentUserId: bob,
      );
      await reinstalled.publishOwnKeys();

      await aliceMgr.acceptIdentityChange(bob);
      // The old entry is forgotten; the next contact re-runs trust-on-first-use
      // against the new key (which must be re-verified).
      expect(await aliceMgr.verificationLevel(bob), TrustLevel.unknown);
      await aliceMgr.safetyNumber(bob); // re-TOFU the new key
      expect(await aliceMgr.verificationLevel(bob), TrustLevel.unverified);
    });

    test('exported identity restores to the same public key', () async {
      final identity = await SealIdentity.generate();
      final priv = await identity.exportPrivateKey();
      final restored = await SealIdentity.restore(
        privateKey: priv,
        publicKey: identity.publicKey,
      );
      expect(restored.publicKey, identity.publicKey);
    });
  });
}
