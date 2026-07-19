import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/supabase.dart';
import '../models/player.dart';
import '../models/room.dart';

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

  /// Live room state (board, turn, status). Errors if the room disappears.
  Stream<Room> roomStream(String roomId) => _client
      .from('rooms')
      .stream(primaryKey: ['id'])
      .eq('id', roomId)
      .map((rows) {
        if (rows.isEmpty) throw StateError('room closed');
        return Room.fromMap(rows.first);
      });

  /// Live list of players in a room, ordered by seat.
  Stream<List<Player>> playersStream(String roomId) => _client
      .from('players')
      .stream(primaryKey: ['id'])
      .eq('room_id', roomId)
      .map((rows) {
        final players = rows.map(Player.fromMap).toList()
          ..sort((a, b) => a.seatIndex.compareTo(b.seatIndex));
        return players;
      });
}

final lobbyRepositoryProvider =
    Provider<LobbyRepository>((ref) => LobbyRepository(supabase));

final roomStreamProvider = StreamProvider.family<Room, String>((ref, roomId) {
  return ref.watch(lobbyRepositoryProvider).roomStream(roomId);
});

final playersStreamProvider =
    StreamProvider.family<List<Player>, String>((ref, roomId) {
  return ref.watch(lobbyRepositoryProvider).playersStream(roomId);
});
