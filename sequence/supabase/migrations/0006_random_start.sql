-- 0006_random_start.sql — randomize who takes the first turn.
-- Previously the rotation always ordered teams by index, so team 0 (Blue) always
-- started. This randomizes which team starts and the player order within each
-- team, while still keeping turns strictly alternating between teams and the
-- teams equal in size. Non-destructive: create-or-replace only — safe to run on
-- a live project (existing rooms keep playing; the change applies on next Start).

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
