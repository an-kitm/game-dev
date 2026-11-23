import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/supabase.dart';
import '../models/player.dart';
import '../models/room.dart';

/// The room no longer exists, or this player can no longer see it (Row Level
/// Security shows a room only to its members). Distinct from a transient
/// realtime error, which shouldn't send anyone back to Home.
class RoomUnavailable implements Exception {
  const RoomUnavailable();
  @override
  String toString() => 'This room is no longer available.';
}

/// Thin wrapper over the lobby RPCs and realtime streams.
class LobbyRepository {
  final SupabaseClient _client;
  LobbyRepository(this._client);

  /// Creates a room and returns its id. The host is seated automatically.
  Future<String> createRoom({
    required String nickname,
    required int numTeams,
  }) async {
    await ensureSignedIn();
    final id = await _client.rpc('create_room', params: {
      'p_nickname': nickname,
      'p_num_teams': numTeams,
    });
    return id as String;
  }

  /// Joins a room by code and returns its id.
  Future<String> joinRoom({
    required String code,
    required String nickname,
  }) async {
    await ensureSignedIn();
    final id = await _client.rpc('join_room', params: {
      'p_code': code,
      'p_nickname': nickname,
    });
    return id as String;
  }

  Future<void> leaveRoom(String roomId) async {
    await _client.rpc('leave_room', params: {'p_room': roomId});
  }

  /// Move the current player to [team] (lobby only; server-validated).
  Future<void> setTeam(String roomId, int team) async {
    await _client.rpc('set_team', params: {'p_room': roomId, 'p_team': team});
  }

  /// Live room state (board, turn, status). Errors with [RoomUnavailable] if
  /// the room disappears or the player is no longer in it.
  Stream<Room> roomStream(String roomId) => _client
      .from('rooms')
      .stream(primaryKey: ['id'])
      .eq('id', roomId)
      .map((rows) {
        if (rows.isEmpty) throw const RoomUnavailable();
        return Room.fromMap(rows.first);
      });

  /// Live list of players in a room, ordered by seat.
  ///
  /// Hand-rolled rather than `.stream()`: Realtime can only apply a
  /// `room_id` filter to inserts and updates — a DELETE event carries nothing
  /// but the deleted row's id — so a filtered subscription never hears that a
  /// player left. They lingered on everyone's screen, and showed up twice
  /// after rejoining. So deletes are subscribed to unfiltered (Supabase sends
  /// them for every room, id only) and matched against this room's rows.
  Stream<List<Player>> playersStream(String roomId) {
    final rows = <String, Map<String, dynamic>>{}; // keyed by player id
    final controller = StreamController<List<Player>>();
    RealtimeChannel? channel;
    // Changes that arrive while a snapshot is loading; replayed on top of it.
    List<PostgresChangePayload>? pending;

    bool apply(PostgresChangePayload change) {
      switch (change.eventType) {
        case PostgresChangeEvent.insert:
        case PostgresChangeEvent.update:
          rows[change.newRecord['id'] as String] = change.newRecord;
          return true;
        case PostgresChangeEvent.delete:
          return rows.remove(change.oldRecord['id']) != null;
        case PostgresChangeEvent.all:
          return false;
      }
    }

    void emit() {
      if (controller.isClosed) return;
      controller.add(rows.values.map(Player.fromMap).toList()
        ..sort((a, b) => a.seatIndex.compareTo(b.seatIndex)));
    }

    void onChange(PostgresChangePayload change) {
      final queue = pending;
      if (queue != null) {
        queue.add(change);
      } else if (apply(change)) {
        emit();
      }
    }

    // A fresh snapshot, taken on listen and again on every (re)subscribe, so
    // nothing missed while the socket was down survives.
    Future<void> load() async {
      final queue = pending = <PostgresChangePayload>[];
      try {
        final data =
            await _client.from('players').select().eq('room_id', roomId);
        rows
          ..clear()
          ..addEntries(data.map((r) => MapEntry(r['id'] as String, r)));
        queue.forEach(apply);
        emit();
      } catch (e, st) {
        if (!controller.isClosed) controller.addError(e, st);
      } finally {
        if (identical(pending, queue)) pending = null;
      }
    }

    controller
      ..onListen = () {
        final inRoom = PostgresChangeFilter(
          type: PostgresChangeFilterType.eq,
          column: 'room_id',
          value: roomId,
        );
        channel = _client
            .channel('players:$roomId:${_channelSeq++}')
            .onPostgresChanges(
              event: PostgresChangeEvent.insert,
              schema: 'public',
              table: 'players',
              filter: inRoom,
              callback: onChange,
            )
            .onPostgresChanges(
              event: PostgresChangeEvent.update,
              schema: 'public',
              table: 'players',
              filter: inRoom,
              callback: onChange,
            )
            .onPostgresChanges(
              event: PostgresChangeEvent.delete,
              schema: 'public',
              table: 'players',
              callback: onChange,
            )
            .subscribe((status, [error]) {
          switch (status) {
            case RealtimeSubscribeStatus.subscribed:
              load();
            case RealtimeSubscribeStatus.channelError:
            case RealtimeSubscribeStatus.timedOut:
              if (!controller.isClosed) {
                controller.addError(RealtimeSubscribeException(status, error));
              }
            case RealtimeSubscribeStatus.closed:
              break;
          }
        });
        load();
      }
      ..onCancel = () async {
        final c = channel;
        channel = null;
        if (c != null) await _client.removeChannel(c);
      };
    return controller.stream;
  }

  static int _channelSeq = 0;
}

final lobbyRepositoryProvider =
    Provider<LobbyRepository>((ref) => LobbyRepository(supabase));

// The room streams are auto-disposed: leaving a screen drops the
// subscription, and coming back (rejoining a room, or a rematch) starts from
// a fresh snapshot instead of a cached list that went stale while away.
final roomStreamProvider =
    StreamProvider.autoDispose.family<Room, String>((ref, roomId) {
  return ref.watch(lobbyRepositoryProvider).roomStream(roomId);
});

final playersStreamProvider =
    StreamProvider.autoDispose.family<List<Player>, String>((ref, roomId) {
  return ref.watch(lobbyRepositoryProvider).playersStream(roomId);
});
