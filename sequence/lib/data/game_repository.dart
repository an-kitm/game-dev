import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/supabase.dart';
import '../rules/board.dart';

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

  /// The cell of the most recent place/remove move (for the last-move marker).
  Stream<Cell?> lastMoveStream(String roomId) => _client
      .from('moves')
      .stream(primaryKey: ['id'])
      .eq('room_id', roomId)
      .order('seq')
      .map((rows) {
        for (final m in rows.reversed) {
          final p = m['payload'] as Map?;
          if (p != null && p['row'] != null && p['col'] != null) {
            return Cell(p['row'] as int, p['col'] as int);
          }
        }
        return null;
      });
}

final gameRepositoryProvider =
    Provider<GameRepository>((ref) => GameRepository(supabase));

final handStreamProvider =
    StreamProvider.family<List<String>, String>((ref, roomId) {
  return ref.watch(gameRepositoryProvider).handStream(roomId);
});

final lastMoveProvider = StreamProvider.family<Cell?, String>((ref, roomId) {
  return ref.watch(gameRepositoryProvider).lastMoveStream(roomId);
});
