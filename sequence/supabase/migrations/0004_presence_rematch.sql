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
  v_host uuid;
begin
  select host_id into v_host from rooms where id = p_room;
  if v_host is null then raise exception 'room not found'; end if;
  if auth.uid() <> v_host then raise exception 'only the host can rematch'; end if;

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
