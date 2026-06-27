import 'dart:convert';
import 'dart:typed_data';

import 'package:supabase/supabase.dart';
import 'package:supabase_realtime_kit/supabase_realtime_kit.dart';

/// Stores and serves the *public* key for each user, so a sender can fetch a
/// recipient's key and derive a shared session.
///
/// Implementations only ever handle public key material — never private keys.
/// There is one stable key per user (no prekeys); identity-change detection is
/// handled by the manager comparing fetched keys against a `TrustStore`.
abstract class PublicKeyDirectory {
  /// Publishes (replaces) this user's public key.
  Future<Result<void>> publish(String userId, Uint8List publicKey);

  /// Fetches a user's public key, or `Ok(null)` if they have not published one.
  Future<Result<Uint8List?>> fetch(String userId);
}

/// A [PublicKeyDirectory] backed by a Supabase table (see the package
/// migration). Each row is `{user_id, public_key}`; RLS lets anyone read and
/// each user write only their own row.
class SupabasePublicKeyDirectory implements PublicKeyDirectory {
  /// Creates a directory over `client`.
  SupabasePublicKeyDirectory(this._client, {this.table = 'e2ee_public_keys'});

  final SupabaseClient _client;

  /// Table holding each user's public key.
  final String table;

  @override
  Future<Result<void>> publish(String userId, Uint8List publicKey) =>
      Result.guard(() async {
        await _client.from(table).upsert({
          'user_id': userId,
          'public_key': base64Encode(publicKey),
        }, onConflict: 'user_id');
      });

  @override
  Future<Result<Uint8List?>> fetch(String userId) => Result.guard(() async {
    final row = await _client
        .from(table)
        .select('public_key')
        .eq('user_id', userId)
        .maybeSingle();
    if (row == null) return null;
    return base64Decode(row['public_key'] as String);
  });
}

/// An in-memory [PublicKeyDirectory] for tests and local prototyping.
class InMemoryPublicKeyDirectory implements PublicKeyDirectory {
  final Map<String, Uint8List> _keys = {};

  @override
  Future<Result<void>> publish(String userId, Uint8List publicKey) async {
    _keys[userId] = publicKey;
    return const Ok<void>(null);
  }

  @override
  Future<Result<Uint8List?>> fetch(String userId) async => Ok(_keys[userId]);
}
