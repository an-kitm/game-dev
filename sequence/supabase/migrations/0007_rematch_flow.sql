-- 0007_rematch_flow.sql — robust end-of-match flow.
--   * rematch  — any player in the room can trigger it (not just the host), and
--                it is idempotent, so concurrent "Play Again" taps are safe. It
--                keeps the SAME room (id + code + players) and just resets it to
--                the lobby.
--   * leave_room — if the host leaves, promote the lowest-seat remaining player
--                  to host so the room is never orphaned; preserve players'
--                  chosen teams (only reindex seats).
-- Non-destructive: create-or-replace only. Safe to run on a live project.

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
