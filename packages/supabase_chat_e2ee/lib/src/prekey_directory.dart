import 'dart:convert';

import 'package:supabase/supabase.dart';
import 'package:supabase_chat_e2ee/src/device_key_bundle.dart';
import 'package:supabase_realtime_kit/supabase_realtime_kit.dart';

/// Stores and serves the *public* key material for each user, so a sender can
/// fetch a recipient's keys and start an encrypted session.
///
/// Implementations only ever handle public key material — never private keys.
/// [fetch] consumes a single one-time prekey per call (forward secrecy), so two
/// fetches for the same user return *different* one-time prekeys until the pool
/// is exhausted, after which the signed prekey is the fallback.
abstract class PreKeyDirectory {
  /// Publishes (replaces) this user's identity, signed prekey and one-time
  /// prekey pool.
  Future<Result<void>> publish(String userId, DeviceKeyBundle bundle);

  /// Fetches a user's identity bundle with **one** freshly-claimed one-time
  /// prekey (or none if the pool is empty), or `Ok(null)` if the user has not
  /// published keys.
  Future<Result<DeviceKeyBundle?>> fetch(String userId);
}

/// A [PreKeyDirectory] backed by the `device_keys` / `one_time_prekeys` tables
/// and the `claim_one_time_prekey` RPC (see the package migration).
///
/// One-time prekeys are popped server-side and atomically, so a prekey is never
/// served twice — closing the prekey-reuse weakness of a naive jsonb blob.
class SupabasePreKeyDirectory implements PreKeyDirectory {
  /// Creates a directory over `client`.
  SupabasePreKeyDirectory(
    this._client, {
    this.deviceKeysTable = 'device_keys',
    this.preKeysTable = 'one_time_prekeys',
    this.claimRpc = 'claim_one_time_prekey',
  });

  final SupabaseClient _client;

  /// Table holding each user's identity + signed prekey.
  final String deviceKeysTable;

  /// Table holding the one-time prekey pool.
  final String preKeysTable;

  /// Name of the atomic claim function.
  final String claimRpc;

  @override
  Future<Result<void>> publish(String userId, DeviceKeyBundle bundle) =>
      Result.guard(() async {
        await _client.from(deviceKeysTable).upsert({
          'user_id': userId,
          'registration_id': bundle.registrationId,
          'device_id': bundle.deviceId,
          'identity_key': base64Encode(bundle.identityKey),
          'signed_pre_key_id': bundle.signedPreKeyId,
          'signed_pre_key': base64Encode(bundle.signedPreKey),
          'signed_pre_key_signature': base64Encode(
            bundle.signedPreKeySignature,
          ),
        }, onConflict: 'user_id');

        // Replace the pool: clear old prekeys, then insert the fresh batch.
        await _client.from(preKeysTable).delete().eq('user_id', userId);
        if (bundle.preKeys.isNotEmpty) {
          await _client.from(preKeysTable).insert([
            for (final p in bundle.preKeys)
              {
                'user_id': userId,
                'key_id': p.id,
                'public_key': base64Encode(p.publicKey),
              },
          ]);
        }
      });

  @override
  Future<Result<DeviceKeyBundle?>> fetch(String userId) =>
      Result.guard(() async {
        final row = await _client
            .from(deviceKeysTable)
            .select()
            .eq('user_id', userId)
            .maybeSingle();
        if (row == null) return null;

        final claimed =
            await _client.rpc<dynamic>(claimRpc, params: {'target': userId})
                as List<dynamic>?;
        final preKeys = <PreKeyEntry>[];
        if (claimed != null && claimed.isNotEmpty) {
          final p = claimed.first as Map<String, dynamic>;
          preKeys.add((
            id: p['key_id'] as int,
            publicKey: base64Decode(p['public_key'] as String),
          ));
        }

        return DeviceKeyBundle(
          registrationId: row['registration_id'] as int,
          deviceId: row['device_id'] as int,
          identityKey: base64Decode(row['identity_key'] as String),
          signedPreKeyId: row['signed_pre_key_id'] as int,
          signedPreKey: base64Decode(row['signed_pre_key'] as String),
          signedPreKeySignature: base64Decode(
            row['signed_pre_key_signature'] as String,
          ),
          preKeys: preKeys,
        );
      });
}

/// An in-memory [PreKeyDirectory] for tests and local prototyping. Mirrors the
/// server's behaviour: each [fetch] pops one one-time prekey from the pool.
class InMemoryPreKeyDirectory implements PreKeyDirectory {
  final Map<String, DeviceKeyBundle> _identities = {};
  final Map<String, List<PreKeyEntry>> _pools = {};

  @override
  Future<Result<void>> publish(String userId, DeviceKeyBundle bundle) async {
    _identities[userId] = bundle;
    _pools[userId] = List.of(bundle.preKeys);
    return const Ok<void>(null);
  }

  @override
  Future<Result<DeviceKeyBundle?>> fetch(String userId) async {
    final identity = _identities[userId];
    if (identity == null) return const Ok(null);
    final pool = _pools[userId] ?? [];
    final claimed = pool.isEmpty ? <PreKeyEntry>[] : [pool.removeAt(0)];
    return Ok(
      DeviceKeyBundle(
        registrationId: identity.registrationId,
        deviceId: identity.deviceId,
        identityKey: identity.identityKey,
        signedPreKeyId: identity.signedPreKeyId,
        signedPreKey: identity.signedPreKey,
        signedPreKeySignature: identity.signedPreKeySignature,
        preKeys: claimed,
      ),
    );
  }
}
