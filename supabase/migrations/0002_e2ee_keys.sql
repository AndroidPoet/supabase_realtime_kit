-- ════════════════════════════════════════════════════════════════════════════
-- supabase_chat_e2ee — opt-in end-to-end encryption (Signal Protocol)
-- ════════════════════════════════════════════════════════════════════════════
-- Apply this only if you use the `supabase_chat_e2ee` package. It adds:
--   1. `device_keys`        — each user's long-term identity + signed prekey,
--   2. `one_time_prekeys`   — a pool of single-use prekeys, consumed atomically,
--   3. `claim_one_time_prekey()` — pops exactly one prekey per session, and
--   4. an `encrypted` jsonb column on `messages` for per-recipient ciphertext.
--
-- The server never sees plaintext or private keys: everything published here is
-- public key material (X3DH). One-time prekeys are popped server-side so a key
-- is never handed out twice — preserving forward secrecy for new sessions.
-- With E2EE enabled, `messages.content` stays null and ciphertext lives in
-- `messages.encrypted` as `{ "<user_id>": { "t": <int>, "b": "<base64>" } }`.

-- ──────────────────────── identity + signed prekey ─────────────────────────
create table if not exists public.device_keys (
  user_id                 uuid primary key references auth.users (id)
                            on delete cascade,
  registration_id         integer not null,
  device_id               integer not null default 1,
  identity_key            text not null,   -- base64 public identity key
  signed_pre_key_id       integer not null,
  signed_pre_key          text not null,   -- base64 public signed prekey
  signed_pre_key_signature text not null,  -- base64 signature
  updated_at              timestamptz not null default now()
);

alter table public.device_keys enable row level security;

-- Public key material: any authenticated user may read it to start a session.
drop policy if exists device_keys_read on public.device_keys;
create policy device_keys_read on public.device_keys
  for select to authenticated using (true);

-- A user may only publish / replace their OWN identity.
drop policy if exists device_keys_write on public.device_keys;
create policy device_keys_write on public.device_keys
  for all to authenticated
  using (user_id = auth.uid())
  with check (user_id = auth.uid());

-- ──────────────────────── one-time prekey pool ─────────────────────────────
create table if not exists public.one_time_prekeys (
  id         bigint generated always as identity primary key,
  user_id    uuid not null references auth.users (id) on delete cascade,
  key_id     integer not null,
  public_key text not null,             -- base64 public prekey
  unique (user_id, key_id)
);

create index if not exists one_time_prekeys_user_idx
  on public.one_time_prekeys (user_id);

alter table public.one_time_prekeys enable row level security;

-- A user manages only their own pool. Others never read the pool directly —
-- they consume it through claim_one_time_prekey() below.
drop policy if exists one_time_prekeys_write on public.one_time_prekeys;
create policy one_time_prekeys_write on public.one_time_prekeys
  for all to authenticated
  using (user_id = auth.uid())
  with check (user_id = auth.uid());

-- Atomically pop one prekey for `target`, or return no rows if the pool is
-- empty (the caller then falls back to the signed prekey). SECURITY DEFINER so
-- callers can consume someone else's pool without reading it wholesale;
-- SKIP LOCKED keeps concurrent claims from colliding.
create or replace function public.claim_one_time_prekey(target uuid)
  returns table (key_id integer, public_key text)
  language plpgsql
  security definer
  set search_path = public
as $$
begin
  return query
  delete from public.one_time_prekeys p
  where p.id = (
    select id from public.one_time_prekeys
    where user_id = target
    order by id
    for update skip locked
    limit 1
  )
  returning p.key_id, p.public_key;
end;
$$;

revoke all on function public.claim_one_time_prekey(uuid) from public;
grant execute on function public.claim_one_time_prekey(uuid) to authenticated;

-- ──────────────────────── ciphertext on messages ───────────────────────────
-- Existing `messages` RLS already restricts read/write to room members, so no
-- extra policy is needed for this column.
alter table public.messages
  add column if not exists encrypted jsonb;
