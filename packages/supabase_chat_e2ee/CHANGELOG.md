## 0.1.0

- Initial release.
- Opt-in end-to-end encryption for `supabase_chat` via the Signal Protocol
  (`libsignal_protocol_dart`): the server only ever stores ciphertext.
- `E2eeIdentity` (generate/restore, BYO-persistable Signal store) and
  `E2eeManager` (sessions, per-recipient encrypt, decrypt).
- `DeviceKeyBundle` + `PreKeyDirectory` (`SupabasePreKeyDirectory` /
  `InMemoryPreKeyDirectory`) for X3DH prekey distribution over Supabase, with
  atomic server-side one-time-prekey consumption.
- `EncryptedChatRoom` decorator: verify-first encrypt-on-send / decrypt-on-receive
  for 1:1 rooms.
- Safety numbers + strict `requireVerified` mode (MITM protection) and
  `IdentityChangedException` (key-change rejection).
- SQL migration for `device_keys` / `one_time_prekeys` (+ `claim_one_time_prekey`
  RPC) and `messages.encrypted`.
