import 'package:supabase_chat_e2ee/supabase_chat_e2ee.dart';
import 'package:supabase_realtime_kit/supabase_realtime_kit.dart';
import 'package:test/test.dart';

/// Two-party Signal round-trips against an in-memory directory — exercises the
/// crypto integration end to end without any Supabase connection.
void main() {
  const alice = 'alice';
  const bob = 'bob';

  late InMemoryPreKeyDirectory directory;
  late E2eeManager aliceMgr;
  late E2eeManager bobMgr;

  // Builds two managers sharing one directory. Strict verification is opt-out
  // per test so we can exercise both the relaxed and the hardened paths.
  Future<void> setup({bool requireVerified = false}) async {
    directory = InMemoryPreKeyDirectory();

    final aliceId = await E2eeIdentity.generate(preKeyCount: 5);
    final bobId = await E2eeIdentity.generate(preKeyCount: 5);

    aliceMgr = E2eeManager(
      identity: aliceId,
      directory: directory,
      currentUserId: alice,
      requireVerified: requireVerified,
    );
    bobMgr = E2eeManager(
      identity: bobId,
      directory: directory,
      currentUserId: bob,
      requireVerified: requireVerified,
    );

    await aliceMgr.publishOwnKeys();
    await bobMgr.publishOwnKeys();
  }

  group('relaxed (requireVerified: false)', () {
    setUp(setup);

    test('alice -> bob single message decrypts correctly', () async {
      final encrypted = await aliceMgr.encryptFor([bob], 'hello bob');
      final plain = await bobMgr.decrypt(
        Map<String, dynamic>.from(encrypted[bob] as Map),
        alice,
      );
      expect(plain, 'hello bob');
    });

    test(
      'first message is a prekey message; becomes whisper after a reply',
      () async {
        final first = await aliceMgr.encryptFor([bob], 'one');
        final firstEnv = CipherEnvelope.fromJson(
          Map<String, dynamic>.from(first[bob] as Map),
        );
        expect(firstEnv.isPreKey, isTrue);
        await bobMgr.decrypt(firstEnv.toJson(), alice);

        final reply = await bobMgr.encryptFor([alice], 'one back');
        final replyEnv = CipherEnvelope.fromJson(
          Map<String, dynamic>.from(reply[alice] as Map),
        );
        expect(await aliceMgr.decrypt(replyEnv.toJson(), bob), 'one back');

        final second = await aliceMgr.encryptFor([bob], 'two');
        final secondEnv = CipherEnvelope.fromJson(
          Map<String, dynamic>.from(second[bob] as Map),
        );
        expect(secondEnv.isPreKey, isFalse);
        expect(await bobMgr.decrypt(secondEnv.toJson(), alice), 'two');
      },
    );

    test('a two-way conversation ratchets across multiple turns', () async {
      Future<String> aToB(String text) async {
        final e = await aliceMgr.encryptFor([bob], text);
        return bobMgr.decrypt(Map<String, dynamic>.from(e[bob] as Map), alice);
      }

      Future<String> bToA(String text) async {
        final e = await bobMgr.encryptFor([alice], text);
        return aliceMgr.decrypt(
          Map<String, dynamic>.from(e[alice] as Map),
          bob,
        );
      }

      expect(await aToB('hi'), 'hi');
      expect(await bToA('hey'), 'hey');
      expect(await aToB('how are you?'), 'how are you?');
      expect(await bToA('good!'), 'good!');
    });

    test(
      'encrypting for an unpublished user throws MissingKeysException',
      () async {
        await expectLater(
          aliceMgr.encryptFor(['ghost'], 'hi'),
          throwsA(isA<MissingKeysException>()),
        );
      },
    );
  });

  group('verification & strict mode', () {
    setUp(() => setup(requireVerified: true));

    test('both parties compute the same safety number', () async {
      final a = await aliceMgr.safetyNumber(bob);
      final b = await bobMgr.safetyNumber(alice);
      expect(a.digits, isNotEmpty);
      expect(a.digits.length, 60);
      expect(a.digits, b.digits); // identical on both sides
      expect(a.formatted, contains(' '));
    });

    test('strict mode refuses to encrypt to an unverified peer', () async {
      await aliceMgr.ensureSession(bob);
      expect(await aliceMgr.verificationLevel(bob), TrustLevel.unverified);
      await expectLater(
        aliceMgr.encryptFor([bob], 'secret'),
        throwsA(isA<UnverifiedRecipientException>()),
      );
    });

    test('after verifying, encryption succeeds and decrypts', () async {
      // Out-of-band: both confirm the safety number, then mark verified.
      final a = await aliceMgr.safetyNumber(bob);
      final b = await bobMgr.safetyNumber(alice);
      expect(a.digits, b.digits);
      await aliceMgr.markVerified(bob);
      await bobMgr.markVerified(alice);

      expect(await aliceMgr.isVerified(bob), isTrue);
      final encrypted = await aliceMgr.encryptFor([bob], 'top secret');
      final plain = await bobMgr.decrypt(
        Map<String, dynamic>.from(encrypted[bob] as Map),
        alice,
      );
      expect(plain, 'top secret');
    });

    test(
      'a swapped identity key is rejected as IdentityChanged (MITM)',
      () async {
        // Alice verifies and talks to the real Bob.
        await aliceMgr.safetyNumber(bob);
        await aliceMgr.markVerified(bob);
        await aliceMgr.encryptFor([bob], 'hi real bob');

        // The directory is compromised: "bob" republishes a DIFFERENT identity
        // (simulating an attacker swapping keys). Alice already trusts the old
        // key, so any new contact must be rejected.
        final imposter = await E2eeIdentity.generate(preKeyCount: 5);
        final imposterMgr = E2eeManager(
          identity: imposter,
          directory: directory,
          currentUserId: bob,
        );
        await imposterMgr.publishOwnKeys(); // overwrites bob's published bundle

        // Force a fresh session attempt against the now-different key.
        await aliceMgr.identity.store.deleteAllSessions(bob);
        await expectLater(
          aliceMgr.ensureSession(bob),
          throwsA(isA<IdentityChangedException>()),
        );
      },
    );

    test(
      'acceptIdentityChange clears trust so a legit re-key can re-verify',
      () async {
        await aliceMgr.safetyNumber(bob);
        await aliceMgr.markVerified(bob);

        // Bob legitimately reinstalls with a new identity.
        final reinstalled = await E2eeIdentity.generate(preKeyCount: 5);
        final bob2 = E2eeManager(
          identity: reinstalled,
          directory: directory,
          currentUserId: bob,
        );
        await bob2.publishOwnKeys();

        // Alice accepts the change, re-verifies, then can talk again.
        await aliceMgr.acceptIdentityChange(bob);
        expect(await aliceMgr.verificationLevel(bob), TrustLevel.unknown);
        await aliceMgr.safetyNumber(bob);
        await aliceMgr.markVerified(bob);
        await bob2.safetyNumber(alice);
        await bob2.markVerified(alice);

        final e = await aliceMgr.encryptFor([bob], 'hello again');
        expect(
          await bob2.decrypt(Map<String, dynamic>.from(e[bob] as Map), alice),
          'hello again',
        );
      },
    );

    test('one-time prekeys are consumed, not reused', () async {
      final id = await E2eeIdentity.generate(preKeyCount: 2);
      final mgr = E2eeManager(
        identity: id,
        directory: directory,
        currentUserId: 'carol',
      );
      await mgr.publishOwnKeys();

      final first = await directory.fetch('carol');
      final second = await directory.fetch('carol');
      final k1 = (first as Ok<DeviceKeyBundle?>).value!.preKeys;
      final k2 = (second as Ok<DeviceKeyBundle?>).value!.preKeys;
      expect(k1, hasLength(1));
      expect(k2, hasLength(1));
      expect(k1.first.id, isNot(k2.first.id)); // different prekey each time
    });
  });
}
