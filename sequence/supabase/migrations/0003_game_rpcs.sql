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
  if v_count % v_teams <> 0 then
    raise exception 'players do not divide evenly into % teams', v_teams;
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

  select jsonb_agg(id::text order by seat_index) into v_order
  from players where room_id = p_room;

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
