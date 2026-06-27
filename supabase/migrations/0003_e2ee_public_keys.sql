-- ════════════════════════════════════════════════════════════════════════════
-- supabase_chat_seal — permissive (MIT) end-to-end encryption (ECDH + AES-GCM)
-- ════════════════════════════════════════════════════════════════════════════
-- Apply this only if you use the `supabase_chat_seal` package. It adds:
--   1. `e2ee_public_keys` — each user's long-term X25519 public key, and
--   2. reuses the `encrypted` jsonb column on `messages` (added in 0002).
--
-- The server never sees plaintext or private keys: the only material published
-- here is a public key. There are no prekeys — the sealed box derives a static
-- pairwise key via ECDH, so this trades forward secrecy for permissive
-- licensing. With encryption enabled, `messages.content` stays null and
-- ciphertext lives in `messages.encrypted` as
-- `{ "<user_id>": { "v": 1, "b": "<base64 nonce||ciphertext||mac>" } }`.

-- ─────────────────────────── public key directory ──────────────────────────
create table if not exists public.e2ee_public_keys (
  user_id    uuid primary key references auth.users (id) on delete cascade,
  public_key text not null,   -- base64 X25519 public key
  updated_at timestamptz not null default now()
);

alter table public.e2ee_public_keys enable row level security;

-- Public key material: any authenticated user may read it to start a session.
drop policy if exists e2ee_public_keys_read on public.e2ee_public_keys;
create policy e2ee_public_keys_read on public.e2ee_public_keys
  for select to authenticated using (true);

-- A user may only publish / replace their OWN public key.
drop policy if exists e2ee_public_keys_write on public.e2ee_public_keys;
create policy e2ee_public_keys_write on public.e2ee_public_keys
  for all to authenticated
  using (user_id = auth.uid())
  with check (user_id = auth.uid());

-- ────────────────────── ciphertext column on messages ──────────────────────
-- Idempotent: also added by 0002. Safe to run on its own if you use only this
-- package.
alter table public.messages
  add column if not exists encrypted jsonb;
