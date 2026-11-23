import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/supabase.dart';
import '../models/move.dart';

/// Move RPCs + the player's own private hand stream. RLS guarantees the hand
/// stream only ever carries the current user's cards.
class GameRepository {
  final SupabaseClient _client;
  GameRepository(this._client);

  /// The current user's hand for [roomId]. Emits [] until dealt.
  Stream<List<String>> handStream(String roomId) => _client
      .from('player_hands')
      .stream(primaryKey: ['player_id'])
      .eq('room_id', roomId)
      .map((rows) {
        if (rows.isEmpty) return const <String>[];
        final cards = (rows.first['cards'] as List?) ?? const [];
        return cards.map((e) => e as String).toList();
      });

  Future<void> playCard({
    required String roomId,
    required String card,
    required int row,
    required int col,
  }) async {
    await _client.rpc('play_card', params: {
      'p_room': roomId,
      'p_card': card,
      'p_row': row,
      'p_col': col,
    });
  }

  Future<void> exchangeDeadCard({
    required String roomId,
    required String card,
  }) async {
    await _client.rpc('exchange_dead_card', params: {
      'p_room': roomId,
      'p_card': card,
    });
  }

  /// Host-only: reset a finished room back to the lobby for another game.
  Future<void> rematch(String roomId) async {
    await _client.rpc('rematch', params: {'p_room': roomId});
  }

  /// Presence ping; keeps the player's `last_seen` fresh.
  Future<void> heartbeat(String roomId) async {
    await _client.rpc('heartbeat', params: {'p_room': roomId});
  }

  /// The room's move log, oldest first. Moves are only ever inserted during a
  /// game (a rematch deletes them, but the screens showing them have been
  /// left by then), so the filtered `.stream()` is enough here.
  Stream<List<Move>> movesStream(String roomId) => _client
      .from('moves')
      .stream(primaryKey: ['id'])
      .eq('room_id', roomId)
      .map((rows) =>
          rows.map(Move.fromMap).toList()..sort((a, b) => a.seq.compareTo(b.seq)));
}

final gameRepositoryProvider =
    Provider<GameRepository>((ref) => GameRepository(supabase));

// Auto-disposed like the room streams: a rematch deletes the old hands and
// moves, which a filtered realtime stream never hears about, so the next game
// must start from a fresh snapshot rather than a cached one.
final handStreamProvider =
    StreamProvider.autoDispose.family<List<String>, String>((ref, roomId) {
  return ref.watch(gameRepositoryProvider).handStream(roomId);
});

final movesProvider =
    StreamProvider.autoDispose.family<List<Move>, String>((ref, roomId) {
  return ref.watch(gameRepositoryProvider).movesStream(roomId);
});
