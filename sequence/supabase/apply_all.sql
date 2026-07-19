begin;

-- DEV reset: drop our objects so this script is safely re-runnable on a fresh
-- or partially-applied project. WARNING: this deletes all rooms/players/games.
drop function if exists create_room(text, int) cascade;
drop function if exists join_room(text, text) cascade;
drop function if exists leave_room(uuid) cascade;
drop function if exists set_team(uuid, int) cascade;
drop function if exists start_game(uuid) cascade;
drop function if exists play_card(uuid, text, int, int) cascade;
drop function if exists exchange_dead_card(uuid, text) cascade;
drop function if exists heartbeat(uuid) cascade;
drop function if exists rematch(uuid) cascade;
drop function if exists draw_card(uuid) cascade;
drop function if exists detect_sequences(jsonb, int) cascade;
drop function if exists locked_cells(jsonb) cascade;
drop function if exists deck_template() cascade;
drop function if exists empty_board() cascade;
drop function if exists is_member(uuid) cascade;
drop function if exists gen_room_code() cascade;
drop table if exists moves, player_hands, room_secrets, players, board_layout, rooms cascade;


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
  v_host  uuid;
begin
  select host_id into v_host from rooms where id = p_room;

  delete from players where room_id = p_room and user_id = v_uid;

  -- Resequence seats for the remaining players (preserve their chosen teams).
  update players p set seat_index = s.rn
  from (
    select id, (row_number() over (order by seat_index) - 1)::int as rn
    from players where room_id = p_room
  ) s
  where p.id = s.id;

  -- If the host left but players remain, promote the lowest-seat player to host
  -- so the room is never left without someone who can start / rematch.
  if v_host = v_uid then
    update rooms set host_id = (
      select user_id from players where room_id = p_room
      order by seat_index limit 1
    )
    where id = p_room
      and exists (select 1 from players where room_id = p_room);
  end if;

  -- If the room is now empty, drop it.
  delete from rooms r where r.id = p_room
    and not exists (select 1 from players where room_id = p_room);
end;
$$;

-- Switch teams while in the lobby. Players pick their own team; start_game
-- enforces that the teams end up equal in size.
create or replace function set_team(p_room uuid, p_team int)
  returns void
  language plpgsql security definer set search_path = public as $$
declare
  v_uid    uuid := auth.uid();
  v_teams  int;
  v_status text;
begin
  if v_uid is null then raise exception 'not authenticated'; end if;
  select num_teams, status into v_teams, v_status from rooms where id = p_room;
  if v_teams is null then raise exception 'room not found'; end if;
  if v_status <> 'lobby' then raise exception 'game already started'; end if;
  if p_team < 0 or p_team >= v_teams then raise exception 'invalid team'; end if;

  update players set team = p_team
  where room_id = p_room and user_id = v_uid;
end;
$$;


-- GENERATED from lib/rules/board_layout.dart — do not edit by hand.
-- Regenerate: dart run tool/gen_board_sql.dart > supabase/migrations/0002_board_layout.sql

truncate board_layout;
insert into board_layout (row, col, card) values
  (0, 1, '6D'),
  (0, 2, '7D'),
  (0, 3, '8D'),
  (0, 4, '9D'),
  (0, 5, '10D'),
  (0, 6, 'QD'),
  (0, 7, 'KD'),
  (0, 8, 'AD'),
  (1, 0, '5D'),
  (1, 1, '3H'),
  (1, 2, '2H'),
  (1, 3, '2S'),
  (1, 4, '3S'),
  (1, 5, '4S'),
  (1, 6, '5S'),
  (1, 7, '6S'),
  (1, 8, '7S'),
  (1, 9, 'AC'),
  (2, 0, '4D'),
  (2, 1, '4H'),
  (2, 2, 'KD'),
  (2, 3, 'AD'),
  (2, 4, 'AC'),
  (2, 5, 'KC'),
  (2, 6, 'QC'),
  (2, 7, '10C'),
  (2, 8, '8S'),
  (2, 9, 'KC'),
  (3, 0, '3D'),
  (3, 1, '5H'),
  (3, 2, 'QD'),
  (3, 3, 'QH'),
  (3, 4, '10H'),
  (3, 5, '9H'),
  (3, 6, '8H'),
  (3, 7, '9C'),
  (3, 8, '9S'),
  (3, 9, 'QC'),
  (4, 0, '2D'),
  (4, 1, '6H'),
  (4, 2, '10D'),
  (4, 3, 'KH'),
  (4, 4, '3H'),
  (4, 5, '2H'),
  (4, 6, '7H'),
  (4, 7, '8C'),
  (4, 8, '10S'),
  (4, 9, '10C'),
  (5, 0, 'AS'),
  (5, 1, '7H'),
  (5, 2, '9D'),
  (5, 3, 'AH'),
  (5, 4, '4H'),
  (5, 5, '5H'),
  (5, 6, '6H'),
  (5, 7, '7C'),
  (5, 8, 'QS'),
  (5, 9, '9C'),
  (6, 0, 'KS'),
  (6, 1, '8H'),
  (6, 2, '8D'),
  (6, 3, '2C'),
  (6, 4, '3C'),
  (6, 5, '4C'),
  (6, 6, '5C'),
  (6, 7, '6C'),
  (6, 8, 'KS'),
  (6, 9, '8C'),
  (7, 0, 'QS'),
  (7, 1, '9H'),
  (7, 2, '7D'),
  (7, 3, '6D'),
  (7, 4, '5D'),
  (7, 5, '4D'),
  (7, 6, '3D'),
  (7, 7, '2D'),
  (7, 8, 'AS'),
  (7, 9, '7C'),
  (8, 0, '10S'),
  (8, 1, '10H'),
  (8, 2, 'QH'),
  (8, 3, 'KH'),
  (8, 4, 'AH'),
  (8, 5, '2C'),
  (8, 6, '3C'),
  (8, 7, '4C'),
  (8, 8, '5C'),
  (8, 9, '6C'),
  (9, 1, '9S'),
  (9, 2, '8S'),
  (9, 3, '7S'),
  (9, 4, '6S'),
  (9, 5, '5S'),
  (9, 6, '4S'),
  (9, 7, '3S'),
  (9, 8, '2S');

-- The 52 distinct card codes, in fixed order; the draw deck is two of these.
create or replace function deck_template() returns text[]
  language sql immutable as $$
  select array['AS', '2S', '3S', '4S', '5S', '6S', '7S', '8S', '9S', '10S', 'JS', 'QS', 'KS', 'AH', '2H', '3H', '4H', '5H', '6H', '7H', '8H', '9H', '10H', 'JH', 'QH', 'KH', 'AD', '2D', '3D', '4D', '5D', '6D', '7D', '8D', '9D', '10D', 'JD', 'QD', 'KD', 'AC', '2C', '3C', '4C', '5C', '6C', '7C', '8C', '9C', '10C', 'JC', 'QC', 'KC']::text[];
$$;



-- Sequence — authoritative game RPCs.
--
-- All game mutations run here as SECURITY DEFINER after validating the request.
-- The sequence-detection logic mirrors lib/rules/sequence_detector.dart (the
-- Dart engine is unit-tested; a DO self-test at the bottom guards the SQL port).

-- ---------------------------------------------------------------------------
-- Sequence detection (operates on the occupancy grid; layout-independent)
-- ---------------------------------------------------------------------------

-- Detects all sequences for a team. Honors the "at most one shared chip between
-- sequences" rule via a deterministic greedy scan. Returns the count and the
-- flat 0-based cell indices (row*10+col) that belong to a completed sequence.
create or replace function detect_sequences(
  p_board jsonb, p_team int, out seq_count int, out cells int[])
  language plpgsql immutable as $$
declare
  dr   int[] := array[0, 1, 1, 1];
  dc   int[] := array[1, 0, 1, -1];
  used boolean[] := array_fill(false, array[100]);
  r int; c int; d int; i int; rr int; cc int; lr int; lc int;
  ok boolean; shared int; idx int;
begin
  seq_count := 0;
  cells := array[]::int[];
  for r in 0..9 loop
    for c in 0..9 loop
      for d in 1..4 loop
        lr := r + dr[d] * 4;
        lc := c + dc[d] * 4;
        continue when lr < 0 or lr > 9 or lc < 0 or lc > 9;

        ok := true;
        for i in 0..4 loop
          rr := r + dr[d] * i; cc := c + dc[d] * i;
          if not ((rr in (0, 9) and cc in (0, 9))
                  or (p_board -> rr -> cc) = to_jsonb(p_team)) then
            ok := false; exit;
          end if;
        end loop;
        continue when not ok;

        shared := 0;
        for i in 0..4 loop
          rr := r + dr[d] * i; cc := c + dc[d] * i;
          if used[rr * 10 + cc + 1] then shared := shared + 1; end if;
        end loop;
        continue when shared > 1;

        seq_count := seq_count + 1;
        for i in 0..4 loop
          rr := r + dr[d] * i; cc := c + dc[d] * i;
          idx := rr * 10 + cc + 1;
          if not used[idx] then
            used[idx] := true;
            cells := cells || (rr * 10 + cc);
          end if;
        end loop;
      end loop;
    end loop;
  end loop;
end;
$$;

-- Union over all teams of cells that are part of a completed sequence,
-- as a jsonb array of [row, col]. These chips are locked (one-eyed-Jack proof).
create or replace function locked_cells(p_board jsonb) returns jsonb
  language plpgsql immutable as $$
declare
  v_all int[] := array[]::int[];
  v_team_cells int[];
  t int;
begin
  for t in 0..2 loop
    select ds.cells into v_team_cells from detect_sequences(p_board, t) ds;
    v_all := v_all || v_team_cells;
  end loop;
  return coalesce((
    select jsonb_agg(distinct jsonb_build_array(idx / 10, idx % 10))
    from unnest(v_all) as idx
  ), '[]'::jsonb);
end;
$$;

-- Draw one card for a room, reshuffling the discard pile into the deck when the
-- deck is empty (official rule). Returns null only if no cards remain anywhere.
create or replace function draw_card(p_room uuid) returns text
  language plpgsql as $$
declare
  v_deck jsonb; v_discard jsonb; v_card text;
begin
  select deck, discard into v_deck, v_discard
  from room_secrets where room_id = p_room;

  if jsonb_array_length(v_deck) = 0 and jsonb_array_length(v_discard) > 0 then
    select coalesce(jsonb_agg(c order by random()), '[]'::jsonb) into v_deck
    from jsonb_array_elements_text(v_discard) c;
    v_discard := '[]'::jsonb;
  end if;

  if jsonb_array_length(v_deck) = 0 then
    update room_secrets set deck = v_deck, discard = v_discard where room_id = p_room;
    return null;
  end if;

  v_card := v_deck ->> 0;
  update room_secrets set deck = v_deck - 0, discard = v_discard where room_id = p_room;
  return v_card;
end;
$$;

-- ---------------------------------------------------------------------------
-- start_game
-- ---------------------------------------------------------------------------

create or replace function start_game(p_room uuid)
  returns void
  language plpgsql security definer set search_path = public as $$
declare
  v_uid   uuid := auth.uid();
  v_host  uuid;
  v_status text;
  v_teams int;
  v_count int;
  v_hs    int;
  v_deck  text[];
  v_idx   int := 1;
  v_order jsonb;
  v_p     record;
  v_distinct int;
  v_minteam  int;
  v_filled   int;
begin
  select host_id, status, num_teams into v_host, v_status, v_teams
  from rooms where id = p_room;
  if v_host is null then raise exception 'room not found'; end if;
  if v_uid <> v_host then raise exception 'only the host can start'; end if;
  if v_status <> 'lobby' then raise exception 'game already started'; end if;

  select count(*) into v_count from players where room_id = p_room;
  if v_count not in (2, 3, 4, 6, 8, 9, 10, 12) then
    raise exception 'unsupported player count: %', v_count;
  end if;
  -- Teams must all be present and exactly equal in size. Players can switch
  -- teams in the lobby, so check the real distribution, not just divisibility.
  select count(distinct cnt), min(cnt), count(*)
    into v_distinct, v_minteam, v_filled
  from (
    select team, count(*) as cnt
    from players where room_id = p_room group by team
  ) t;
  if v_filled <> v_teams or v_distinct <> 1 or coalesce(v_minteam, 0) < 1 then
    raise exception 'each team must have the same number of players (% teams)', v_teams;
  end if;

  v_hs := case v_count
            when 2 then 7 when 3 then 6 when 4 then 6 when 6 then 5
            when 8 then 4 when 9 then 4 when 10 then 3 when 12 then 3 end;

  -- Shuffle two full decks (104 cards).
  select array_agg(code order by random()) into v_deck
  from unnest(deck_template() || deck_template()) as code;

  -- Deal contiguous blocks in seat order (deck is already shuffled).
  for v_p in
    select id, user_id from players where room_id = p_room order by seat_index
  loop
    insert into player_hands (player_id, room_id, user_id, cards)
    values (v_p.id, p_room, v_p.user_id,
            to_jsonb(v_deck[v_idx : v_idx + v_hs - 1]))
    on conflict (player_id) do update set cards = excluded.cards;
    update players set hand_count = v_hs where id = v_p.id;
    v_idx := v_idx + v_hs;
  end loop;

  update room_secrets
    set deck = to_jsonb(v_deck[v_idx : array_length(v_deck, 1)])
    where room_id = p_room;

  -- Build the turn order. Turns must still strictly alternate between teams,
  -- but WHICH team starts (and the order within each team) is randomized, so
  -- the first turn can fall to any team — not always team 0.
  --   * tp.k  — one random key per team => a random, fixed team rotation
  --   * team_rank — random player order within each team
  select jsonb_agg(r.id::text order by r.team_rank, tp.k) into v_order
  from (
    select id, team,
           row_number() over (partition by team order by random()) as team_rank
    from players where room_id = p_room
  ) r
  join (
    select team, random() as k
    from players where room_id = p_room group by team
  ) tp on tp.team = r.team;

  update rooms set
    status = 'playing',
    turn_order = v_order,
    current_turn = (v_order ->> 0)::uuid,
    board = empty_board(),
    locked = '[]'::jsonb,
    last_move_at = now()
  where id = p_room;

  insert into moves (room_id, player_id, seq, type, payload)
  values (p_room, null, 1, 'start', jsonb_build_object('players', v_count));
end;
$$;

-- ---------------------------------------------------------------------------
-- play_card  (normal place / two-eyed wild / one-eyed remove)
-- ---------------------------------------------------------------------------

create or replace function play_card(p_room uuid, p_card text, p_row int, p_col int)
  returns void
  language plpgsql security definer set search_path = public as $$
declare
  v_uid    uuid := auth.uid();
  v_me     uuid; v_team int;
  v_status text; v_turn uuid; v_teams int; v_win int;
  v_board  jsonb; v_order jsonb; v_occ jsonb;
  v_hand   text[]; v_pos int; v_cell_card text;
  v_is_two boolean := p_card in ('JD', 'JC');
  v_is_one boolean := p_card in ('JS', 'JH');
  v_draw   text;
  v_seqcount int; v_locked jsonb; v_seq int; v_i int; v_cur int;
  v_corner boolean := (p_row in (0, 9) and p_col in (0, 9));
begin
  if v_uid is null then raise exception 'not authenticated'; end if;
  if p_row < 0 or p_row > 9 or p_col < 0 or p_col > 9 then
    raise exception 'cell out of range';
  end if;

  select p.id, p.team into v_me, v_team
  from players p where p.room_id = p_room and p.user_id = v_uid;
  if v_me is null then raise exception 'not in this room'; end if;

  select status, current_turn, num_teams, sequences_to_win, board, turn_order
    into v_status, v_turn, v_teams, v_win, v_board, v_order
  from rooms where id = p_room;
  if v_status <> 'playing' then raise exception 'game not in progress'; end if;
  if v_turn <> v_me then raise exception 'not your turn'; end if;

  select array(select jsonb_array_elements_text(cards)) into v_hand
  from player_hands where player_id = v_me;
  if not (p_card = any(v_hand)) then raise exception 'card not in hand'; end if;

  v_occ := v_board -> p_row -> p_col;

  if v_is_one then
    if v_corner then raise exception 'cannot target a corner'; end if;
    if jsonb_typeof(v_occ) <> 'number' then raise exception 'no chip to remove'; end if;
    if v_occ = to_jsonb(v_team) then raise exception 'cannot remove your own chip'; end if;
    if exists (select 1 from jsonb_array_elements(locked_cells(v_board)) e
               where (e ->> 0)::int = p_row and (e ->> 1)::int = p_col) then
      raise exception 'chip is part of a completed sequence';
    end if;
    v_board := jsonb_set(v_board, array[p_row::text, p_col::text], 'null'::jsonb);
  elsif v_is_two then
    if v_corner then raise exception 'cannot place on a corner'; end if;
    if jsonb_typeof(v_occ) = 'number' then raise exception 'cell occupied'; end if;
    v_board := jsonb_set(v_board, array[p_row::text, p_col::text], to_jsonb(v_team));
  else
    if v_corner then raise exception 'cannot place on a corner'; end if;
    select card into v_cell_card from board_layout where row = p_row and col = p_col;
    if v_cell_card is distinct from p_card then
      raise exception 'card does not match this cell';
    end if;
    if jsonb_typeof(v_occ) = 'number' then raise exception 'cell occupied'; end if;
    v_board := jsonb_set(v_board, array[p_row::text, p_col::text], to_jsonb(v_team));
  end if;

  -- Remove one copy of the played card from the hand, discard it, then draw a
  -- replacement (reshuffling the discard pile into the deck if it has emptied).
  v_pos := array_position(v_hand, p_card);
  v_hand := v_hand[1 : v_pos - 1] || v_hand[v_pos + 1 : coalesce(array_length(v_hand, 1), 0)];

  update room_secrets set discard = discard || to_jsonb(p_card)
  where room_id = p_room;
  v_draw := draw_card(p_room);
  if v_draw is not null then v_hand := v_hand || v_draw; end if;

  update player_hands set cards = to_jsonb(v_hand) where player_id = v_me;
  update players set hand_count = coalesce(array_length(v_hand, 1), 0) where id = v_me;

  select ds.seq_count into v_seqcount from detect_sequences(v_board, v_team) ds;
  v_locked := locked_cells(v_board);
  select coalesce(max(seq), 0) + 1 into v_seq from moves where room_id = p_room;

  if v_seqcount >= v_win then
    update rooms set board = v_board, locked = v_locked, status = 'finished',
      winner_team = v_team, last_move_at = now() where id = p_room;
  else
    v_cur := 0;
    for v_i in 0 .. jsonb_array_length(v_order) - 1 loop
      if (v_order ->> v_i)::uuid = v_me then v_cur := v_i; exit; end if;
    end loop;
    v_cur := (v_cur + 1) % jsonb_array_length(v_order);
    update rooms set board = v_board, locked = v_locked,
      current_turn = (v_order ->> v_cur)::uuid, last_move_at = now()
    where id = p_room;
  end if;

  insert into moves (room_id, player_id, seq, type, payload)
  values (p_room, v_me, v_seq,
          case when v_is_one then 'remove' else 'place' end,
          jsonb_build_object('card', p_card, 'row', p_row, 'col', p_col, 'team', v_team));
end;
$$;

-- ---------------------------------------------------------------------------
-- exchange_dead_card  (a held card whose both board cells are already covered)
-- ---------------------------------------------------------------------------

create or replace function exchange_dead_card(p_room uuid, p_card text)
  returns void
  language plpgsql security definer set search_path = public as $$
declare
  v_uid uuid := auth.uid();
  v_me uuid; v_status text; v_turn uuid;
  v_board jsonb; v_hand text[]; v_pos int;
  v_open int; v_draw text; v_seq int;
begin
  if v_uid is null then raise exception 'not authenticated'; end if;
  select p.id into v_me from players p where p.room_id = p_room and p.user_id = v_uid;
  if v_me is null then raise exception 'not in this room'; end if;

  select status, current_turn, board into v_status, v_turn, v_board
  from rooms where id = p_room;
  if v_status <> 'playing' then raise exception 'game not in progress'; end if;
  if v_turn <> v_me then raise exception 'not your turn'; end if;
  if p_card in ('JD', 'JC', 'JS', 'JH') then raise exception 'jacks are never dead'; end if;

  select array(select jsonb_array_elements_text(cards)) into v_hand
  from player_hands where player_id = v_me;
  if not (p_card = any(v_hand)) then raise exception 'card not in hand'; end if;

  -- The card is dead only if BOTH its board cells are occupied.
  select count(*) into v_open from board_layout bl
  where bl.card = p_card
    and jsonb_typeof(v_board -> bl.row -> bl.col) <> 'number';
  if v_open > 0 then raise exception 'card is not dead (an open cell remains)'; end if;

  v_pos := array_position(v_hand, p_card);
  v_hand := v_hand[1 : v_pos - 1] || v_hand[v_pos + 1 : coalesce(array_length(v_hand, 1), 0)];

  update room_secrets set discard = discard || to_jsonb(p_card)
  where room_id = p_room;
  v_draw := draw_card(p_room);
  if v_draw is not null then v_hand := v_hand || v_draw; end if;

  update player_hands set cards = to_jsonb(v_hand) where player_id = v_me;
  update players set hand_count = coalesce(array_length(v_hand, 1), 0) where id = v_me;

  -- Dead-card exchange does NOT end the turn.
  select coalesce(max(seq), 0) + 1 into v_seq from moves where room_id = p_room;
  insert into moves (room_id, player_id, seq, type, payload)
  values (p_room, v_me, v_seq, 'dead', jsonb_build_object('card', p_card));
end;
$$;

grant execute on function set_team(uuid, int) to anon, authenticated;
grant execute on function start_game(uuid) to anon, authenticated;
grant execute on function play_card(uuid, text, int, int) to anon, authenticated;
grant execute on function exchange_dead_card(uuid, text) to anon, authenticated;

-- ---------------------------------------------------------------------------
-- Self-test: validate the PL/pgSQL detection against known cases at apply time.
-- ---------------------------------------------------------------------------
do $$
declare
  b jsonb := empty_board();
  n int;
begin
  -- 4 in a row on row 1 -> 0 sequences
  b := empty_board();
  for c in 0..3 loop b := jsonb_set(b, array['1', c::text], '0'); end loop;
  select seq_count into n from detect_sequences(b, 0);
  if n <> 0 then raise exception 'self-test failed: 4-in-row gave %', n; end if;

  -- 5 in a row -> 1
  b := empty_board();
  for c in 0..4 loop b := jsonb_set(b, array['1', c::text], '0'); end loop;
  select seq_count into n from detect_sequences(b, 0);
  if n <> 1 then raise exception 'self-test failed: 5-in-row gave %', n; end if;

  -- 6 in a row -> 1 (no double counting)
  b := empty_board();
  for c in 0..5 loop b := jsonb_set(b, array['1', c::text], '0'); end loop;
  select seq_count into n from detect_sequences(b, 0);
  if n <> 1 then raise exception 'self-test failed: 6-in-row gave %', n; end if;

  -- 9 in a row -> 2 (one shared chip)
  b := empty_board();
  for c in 0..8 loop b := jsonb_set(b, array['1', c::text], '0'); end loop;
  select seq_count into n from detect_sequences(b, 0);
  if n <> 2 then raise exception 'self-test failed: 9-in-row gave %', n; end if;

  -- corner wild: chips at (0,1)-(0,4) + free corner (0,0) -> 1
  b := empty_board();
  for c in 1..4 loop b := jsonb_set(b, array['0', c::text], '0'); end loop;
  select seq_count into n from detect_sequences(b, 0);
  if n <> 1 then raise exception 'self-test failed: corner-wild gave %', n; end if;

  raise notice 'detect_sequences self-test passed';
end;
$$;


-- Sequence — Milestone 6: presence heartbeat + rematch.
-- NON-DESTRUCTIVE: only creates/replaces functions (plus row updates inside
-- rematch). Safe to run on a live project without dropping anything.

-- Presence: mark the caller as recently seen. Called on a short client timer.
create or replace function heartbeat(p_room uuid) returns void
  language plpgsql security definer set search_path = public as $$
begin
  update players set last_seen = now(), connected = true
  where room_id = p_room and user_id = auth.uid();
end;
$$;

-- Reset a finished room back to the lobby so the same players can play again.
create or replace function rematch(p_room uuid) returns void
  language plpgsql security definer set search_path = public as $$
declare
  v_uid    uuid := auth.uid();
  v_status text;
begin
  -- Any player still in the room can trigger a rematch (not just the host).
  if not exists (select 1 from players where room_id = p_room and user_id = v_uid) then
    raise exception 'not in this room';
  end if;
  select status into v_status from rooms where id = p_room;
  if v_status is null then raise exception 'room not found'; end if;
  -- Idempotent: if someone already reset us to the lobby, do nothing. This makes
  -- concurrent "Play Again" taps from several players safe.
  if v_status = 'lobby' then return; end if;

  update rooms set
    status = 'lobby',
    board = empty_board(),
    locked = '[]'::jsonb,
    turn_order = '[]'::jsonb,
    current_turn = null,
    winner_team = null,
    last_move_at = null
  where id = p_room;

  update players set hand_count = 0 where room_id = p_room;
  delete from player_hands where room_id = p_room;
  update room_secrets set deck = '[]'::jsonb, discard = '[]'::jsonb
  where room_id = p_room;
  delete from moves where room_id = p_room;
end;
$$;

grant execute on function heartbeat(uuid) to anon, authenticated;
grant execute on function rematch(uuid) to anon, authenticated;

commit;
