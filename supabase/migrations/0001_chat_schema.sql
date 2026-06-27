-- supabase_chat — canonical schema, Row Level Security, and realtime publication.
--
-- Apply with the Supabase CLI:  supabase db push
-- or paste into the SQL editor.  Safe to run once on a fresh project.
--
-- Design notes
--   * Every table is membership-gated: you can only see/act in a room you belong
--     to. RLS is the security boundary; the client library trusts these policies.
--   * `messages` is the durable history (postgres_changes drives the live tail).
--   * Typing / presence are EPHEMERAL — they ride realtime broadcast/presence and
--     intentionally have NO table here.

-- ───────────────────────────── extensions ──────────────────────────────────
create extension if not exists "pgcrypto";  -- gen_random_uuid()

-- ─────────────────────────────── tables ────────────────────────────────────
create table if not exists public.rooms (
  id          uuid primary key default gen_random_uuid(),
  name        text,
  is_direct   boolean not null default false,
  created_by  uuid not null references auth.users (id) on delete cascade,
  created_at  timestamptz not null default now()
);

create table if not exists public.room_members (
  room_id   uuid not null references public.rooms (id) on delete cascade,
  user_id   uuid not null references auth.users (id) on delete cascade,
  role      text not null default 'member' check (role in ('owner', 'admin', 'member')),
  joined_at timestamptz not null default now(),
  primary key (room_id, user_id)
);

create table if not exists public.messages (
  id          uuid primary key default gen_random_uuid(),
  room_id     uuid not null references public.rooms (id) on delete cascade,
  sender_id   uuid not null references auth.users (id) on delete cascade,
  content     text,
  attachments jsonb not null default '[]'::jsonb,
  -- Client-generated idempotency key for optimistic send reconciliation.
  client_id   text,
  created_at  timestamptz not null default now(),
  edited_at   timestamptz,
  deleted_at  timestamptz
);

create table if not exists public.message_receipts (
  message_id uuid not null references public.messages (id) on delete cascade,
  user_id    uuid not null references auth.users (id) on delete cascade,
  read_at    timestamptz not null default now(),
  primary key (message_id, user_id)
);

-- ─────────────────────────────── indexes ───────────────────────────────────
create index if not exists messages_room_created_idx
  on public.messages (room_id, created_at desc);
create index if not exists room_members_user_idx
  on public.room_members (user_id);
-- Idempotency: at most one server row per (room, client_id).
create unique index if not exists messages_room_client_idx
  on public.messages (room_id, client_id) where client_id is not null;

-- ───────────────────── membership helper (SECURITY DEFINER) ─────────────────
-- Used by policies to avoid recursive RLS evaluation on room_members.
create or replace function public.is_room_member(p_room_id uuid)
returns boolean
language sql
security definer
set search_path = public
stable
as $$
  select exists (
    select 1 from public.room_members
    where room_id = p_room_id and user_id = auth.uid()
  );
$$;

-- ──────────────────────────── enable RLS ────────────────────────────────────
alter table public.rooms            enable row level security;
alter table public.room_members     enable row level security;
alter table public.messages         enable row level security;
alter table public.message_receipts enable row level security;

-- rooms ----------------------------------------------------------------------
drop policy if exists rooms_select on public.rooms;
create policy rooms_select on public.rooms
  for select using (public.is_room_member(id) or created_by = auth.uid());

drop policy if exists rooms_insert on public.rooms;
create policy rooms_insert on public.rooms
  for insert with check (created_by = auth.uid());

-- room_members ---------------------------------------------------------------
drop policy if exists room_members_select on public.room_members;
create policy room_members_select on public.room_members
  for select using (public.is_room_member(room_id));

drop policy if exists room_members_insert on public.room_members;
create policy room_members_insert on public.room_members
  for insert with check (
    -- The room creator can add anyone; otherwise you may only add yourself.
    user_id = auth.uid()
    or exists (select 1 from public.rooms r where r.id = room_id and r.created_by = auth.uid())
  );

drop policy if exists room_members_delete on public.room_members;
create policy room_members_delete on public.room_members
  for delete using (user_id = auth.uid());  -- leave a room

-- messages -------------------------------------------------------------------
drop policy if exists messages_select on public.messages;
create policy messages_select on public.messages
  for select using (public.is_room_member(room_id));

drop policy if exists messages_insert on public.messages;
create policy messages_insert on public.messages
  for insert with check (sender_id = auth.uid() and public.is_room_member(room_id));

drop policy if exists messages_update on public.messages;
create policy messages_update on public.messages
  for update using (sender_id = auth.uid()) with check (sender_id = auth.uid());

-- message_receipts -----------------------------------------------------------
drop policy if exists receipts_select on public.message_receipts;
create policy receipts_select on public.message_receipts
  for select using (
    exists (
      select 1 from public.messages m
      where m.id = message_id and public.is_room_member(m.room_id)
    )
  );

drop policy if exists receipts_upsert on public.message_receipts;
create policy receipts_upsert on public.message_receipts
  for insert with check (user_id = auth.uid());

-- ─────────────────────── realtime publication ──────────────────────────────
-- postgres_changes only streams tables added to supabase_realtime.
alter publication supabase_realtime add table public.messages;
alter publication supabase_realtime add table public.message_receipts;
alter publication supabase_realtime add table public.room_members;

-- NOTE on deletes: this app uses soft-deletes (an UPDATE setting deleted_at),
-- which stream fine. If you instead need *hard* DELETE events to be delivered
-- to filtered realtime queries, the table must use full replica identity so the
-- old row (incl. the filter column) is included in the WAL payload:
--   alter table public.messages replica identity full;
-- It increases WAL volume, so it's left off by default.
