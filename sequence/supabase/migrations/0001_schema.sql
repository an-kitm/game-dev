-- Sequence — core schema, RLS, and lobby RPCs.
--
-- Authoritative model: clients NEVER write game tables directly. All mutations
-- go through SECURITY DEFINER functions (create_room/join_room/...) that run as
-- the table owner and bypass RLS after validating the request. RLS on the
-- tables themselves only governs what clients may READ (and Realtime delivers).
--
-- Privacy: public room/player state is readable by room members; each player's
-- hand and the draw deck live in separate tables that only their owner / no one
-- can read, so opponents' cards and the deck never reach a client.

-- ---------------------------------------------------------------------------
-- Tables
-- ---------------------------------------------------------------------------

create table if not exists rooms (
  id                uuid primary key default gen_random_uuid(),
  code              text unique not null,
  host_id           uuid not null,                 -- auth.uid() of creator
  status            text not null default 'lobby'
                      check (status in ('lobby', 'playing', 'finished')),
  num_teams         int  not null check (num_teams in (2, 3)),
  sequences_to_win  int  not null,
  board             jsonb not null,                -- 10x10 of team index | null
  locked            jsonb not null default '[]',   -- [[r,c], ...] sequence chips
  turn_order        jsonb not null default '[]',   -- [player_id, ...] by seat
  current_turn      uuid,                          -- players.id whose turn it is
  winner_team       int,
  created_at        timestamptz not null default now(),
  last_move_at      timestamptz
);

create table if not exists players (
  id          uuid primary key default gen_random_uuid(),
  room_id     uuid not null references rooms(id) on delete cascade,
  user_id     uuid not null,                       -- auth.uid()
  nickname    text not null,
  team        int  not null,
  seat_index  int  not null,
  hand_count  int  not null default 0,             -- public; cards are private
  connected   boolean not null default true,
  last_seen   timestamptz not null default now(),
  created_at  timestamptz not null default now(),
  unique (room_id, user_id),
  unique (room_id, seat_index)
);

-- Private: a player's actual cards. Only the owner may read this row.
create table if not exists player_hands (
  player_id  uuid primary key references players(id) on delete cascade,
  room_id    uuid not null references rooms(id) on delete cascade,
  user_id    uuid not null,
  cards      jsonb not null default '[]'           -- ["AS","10H",...]
);

-- Private: the remaining draw deck + discard pile. No client may read this.
-- When the deck empties, the discard pile is reshuffled into a new deck.
create table if not exists room_secrets (
  room_id  uuid primary key references rooms(id) on delete cascade,
  deck     jsonb not null default '[]',            -- ["AS","10H",...]
  discard  jsonb not null default '[]'             -- played cards, for reshuffle
);

-- Append-only move log for history / animation.
create table if not exists moves (
  id          uuid primary key default gen_random_uuid(),
  room_id     uuid not null references rooms(id) on delete cascade,
  player_id   uuid,
  seq         int  not null,
  type        text not null,                       -- 'place' | 'remove' | 'dead' | 'start'
  payload     jsonb not null default '{}',
  created_at  timestamptz not null default now()
);

create index if not exists moves_room_seq_idx on moves (room_id, seq);
create index if not exists players_room_idx on players (room_id);

-- Static reference: which card sits on each board cell (corners excluded).
-- Data is loaded by the generated migration 0002_board_layout.sql.
create table if not exists board_layout (
  row   int  not null,
  col   int  not null,
  card  text not null,
  primary key (row, col)
);

-- ---------------------------------------------------------------------------
-- Helpers
-- ---------------------------------------------------------------------------

-- A fresh empty 10x10 board (all nulls).
create or replace function empty_board() returns jsonb
  language sql immutable as $$
  select jsonb_agg(r) from (
    select (select jsonb_agg(null::int) from generate_series(1, 10)) as r
    from generate_series(1, 10)
  ) s;
$$;

-- Membership check used by RLS. SECURITY DEFINER so it does not recurse into
-- the players RLS policy.
create or replace function is_member(_room uuid) returns boolean
  language sql security definer stable set search_path = public as $$
  select exists (
    select 1 from players
    where room_id = _room and user_id = auth.uid()
  );
$$;

-- A random 4-letter uppercase room code (no confusing letters).
create or replace function gen_room_code() returns text
  language sql volatile as $$
  select string_agg(
    substr('ABCDEFGHJKLMNPQRSTUVWXYZ', (floor(random() * 24) + 1)::int, 1), ''
  )
  from generate_series(1, 4);
$$;

-- ---------------------------------------------------------------------------
-- Row Level Security
-- ---------------------------------------------------------------------------

alter table rooms         enable row level security;
alter table players       enable row level security;
alter table player_hands  enable row level security;
alter table room_secrets  enable row level security;
alter table moves         enable row level security;

-- Members (and the host) can read their room. No client writes.
create policy rooms_select on rooms for select
  using (is_member(id) or host_id = auth.uid());

-- Members can read all public player rows in their room. No client writes.
create policy players_select on players for select
  using (is_member(room_id));

-- A player can read only their own hand.
create policy hands_select_own on player_hands for select
  using (user_id = auth.uid());

-- room_secrets: no policies => no client access at all (RPCs bypass via DEFINER).

-- Members can read the move log of their room.
create policy moves_select on moves for select
  using (is_member(room_id));

-- Static reference data: readable by anyone authenticated (no secrets here).
alter table board_layout enable row level security;
create policy board_layout_select on board_layout for select using (true);

-- ---------------------------------------------------------------------------
-- Realtime
-- ---------------------------------------------------------------------------

alter publication supabase_realtime add table rooms;
alter publication supabase_realtime add table players;
alter publication supabase_realtime add table player_hands;
alter publication supabase_realtime add table moves;

-- ---------------------------------------------------------------------------
-- Lobby RPCs (SECURITY DEFINER)
-- ---------------------------------------------------------------------------

-- Returns the new room's id; the room's join code is read from the room row.
create or replace function create_room(p_nickname text, p_num_teams int)
  returns uuid
  language plpgsql security definer set search_path = public as $$
declare
  v_uid   uuid := auth.uid();
  v_code  text;
  v_room  uuid;
begin
  if v_uid is null then raise exception 'not authenticated'; end if;
  if coalesce(trim(p_nickname), '') = '' then raise exception 'nickname required'; end if;
  if p_num_teams not in (2, 3) then raise exception 'num_teams must be 2 or 3'; end if;

  -- Unique code.
  loop
    v_code := gen_room_code();
    exit when not exists (select 1 from rooms where code = v_code);
  end loop;

  insert into rooms (code, host_id, num_teams, sequences_to_win, board, status)
  values (v_code, v_uid, p_num_teams,
          case when p_num_teams = 2 then 2 else 1 end,
          empty_board(), 'lobby')
  returning id into v_room;

  insert into room_secrets (room_id) values (v_room);

  insert into players (room_id, user_id, nickname, team, seat_index)
  values (v_room, v_uid, trim(p_nickname), 0, 0);

  return v_room;
end;
$$;

create or replace function join_room(p_code text, p_nickname text)
  returns uuid
  language plpgsql security definer set search_path = public as $$
declare
  v_uid   uuid := auth.uid();
  v_room  uuid;
  v_teams int;
  v_seat  int;
begin
  if v_uid is null then raise exception 'not authenticated'; end if;
  if coalesce(trim(p_nickname), '') = '' then raise exception 'nickname required'; end if;

  select id, num_teams into v_room, v_teams
  from rooms where code = upper(trim(p_code)) and status = 'lobby';
  if v_room is null then raise exception 'room not found or already started'; end if;

  -- Idempotent: already joined.
  if exists (select 1 from players where room_id = v_room and user_id = v_uid) then
    return v_room;
  end if;

  select count(*) into v_seat from players where room_id = v_room;
  if v_seat >= 12 then raise exception 'room is full'; end if;

  insert into players (room_id, user_id, nickname, team, seat_index)
  values (v_room, v_uid, trim(p_nickname), v_seat % v_teams, v_seat);

  return v_room;
end;
$$;

-- Leave a room while still in the lobby; reseats remaining players so seats stay
-- contiguous and teams balanced.
create or replace function leave_room(p_room uuid)
  returns void
  language plpgsql security definer set search_path = public as $$
declare
  v_uid   uuid := auth.uid();
  v_teams int;
begin
  delete from players where room_id = p_room and user_id = v_uid;

  select num_teams into v_teams from rooms where id = p_room;
  -- Resequence seats / teams for the remaining lobby players.
  update players p set
    seat_index = s.rn,
    team       = s.rn % v_teams
  from (
    select id, (row_number() over (order by seat_index) - 1)::int as rn
    from players where room_id = p_room
  ) s
  where p.id = s.id;

  -- If the room is now empty, drop it.
  delete from rooms r where r.id = p_room
    and not exists (select 1 from players where room_id = p_room);
end;
$$;
