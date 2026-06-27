## 0.1.0

- Initial release.
- Permissive (MIT) opt-in end-to-end encryption for `supabase_chat`: a sealed
  box over X25519 ECDH + HKDF-SHA256 + AES-256-GCM. The server only ever stores
  ciphertext.
- No copyleft dependencies (uses `cryptography` Apache-2.0 + `crypto` BSD-3), so
  it is safe to use in closed-source apps — unlike the GPL-licensed
  `supabase_chat_e2ee`.
- `SealIdentity` (generate/restore, BYO-persistable X25519 key pair) and
  `SealManager` (per-recipient encrypt, decrypt, trust).
- `PublicKeyDirectory` (`SupabasePublicKeyDirectory` / `InMemoryPublicKeyDirectory`)
  for public-key distribution over Supabase.
- `SealedChatRoom` decorator: verify-first encrypt-on-send / decrypt-on-receive
  for 1:1 rooms, with sender self-readback (static pairwise key).
- Safety numbers + strict `requireVerified` mode (MITM protection) and
  `IdentityChangedException` (key-change rejection).
- SQL migration for the `e2ee_public_keys` directory.
