-- 0005_teams.sql — lobby team selection.
-- Adds set_team() so players can choose their team in the lobby, and updates
-- start_game() to (a) require every team to have an equal number of players and
-- (b) build a turn order that interleaves teams so turns always alternate,
-- regardless of seating or which team a player switched to.
-- Non-destructive: create-or-replace only. Safe to run on an existing project.

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

grant execute on function set_team(uuid, int) to anon, authenticated;

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

  -- Interleave teams so turns alternate between them (round-robin by team),
  -- regardless of how players were seated or which team they switched to.
  select jsonb_agg(id::text order by team_rank, team) into v_order
  from (
    select id, team,
           row_number() over (partition by team order by seat_index) as team_rank
    from players where room_id = p_room
  ) s;

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
