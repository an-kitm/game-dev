import '../rules/board.dart';

/// One entry of a room's move log (the `moves` table), oldest first by [seq].
///
/// Types: `start` (the deal), `place` (a chip played with a card, including a
/// two-eyed Jack as a wild), `remove` (a one-eyed Jack taking a chip off) and
/// `dead` (a dead card swapped for a fresh one).
class Move {
  final int seq;
  final String type;

  /// The player who moved (null for `start`). Rows can outlive the player:
  /// their `players` row is deleted if they leave the room.
  final String? playerId;
  final String? card;
  final int? row;
  final int? col;

  /// The mover's team, for `place` and `remove`.
  final int? team;

  const Move({
    required this.seq,
    required this.type,
    this.playerId,
    this.card,
    this.row,
    this.col,
    this.team,
  });

  factory Move.fromMap(Map<String, dynamic> m) {
    final p = (m['payload'] as Map?) ?? const {};
    return Move(
      seq: m['seq'] as int,
      type: m['type'] as String,
      playerId: m['player_id'] as String?,
      card: p['card'] as String?,
      row: p['row'] as int?,
      col: p['col'] as int?,
      team: p['team'] as int?,
    );
  }

  bool get isStart => type == 'start';
  bool get isPlace => type == 'place';
  bool get isRemove => type == 'remove';
  bool get isDeadSwap => type == 'dead';

  /// The board cell this move touched, if any.
  Cell? get cell => (row != null && col != null) ? Cell(row!, col!) : null;
}

/// For each `remove` in [moves] (oldest first), the team whose chip it took,
/// keyed by the remove's [Move.seq]. The log stores only the remover's team,
/// so this is the team of the last chip placed on that cell before it.
Map<int, int> removedChipTeams(List<Move> moves) {
  final occupant = <Cell, int>{};
  final removed = <int, int>{};
  for (final m in moves) {
    final cell = m.cell;
    if (cell == null) continue;
    if (m.isPlace && m.team != null) {
      occupant[cell] = m.team!;
    } else if (m.isRemove) {
      final taken = occupant.remove(cell);
      if (taken != null) removed[m.seq] = taken;
    }
  }
  return removed;
}

/// The most recent move that put down or took off a chip.
Move? lastBoardMove(List<Move> moves) {
  for (final m in moves.reversed) {
    if (m.cell != null) return m;
  }
  return null;
}
