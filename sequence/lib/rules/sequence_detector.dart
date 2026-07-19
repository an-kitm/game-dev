import 'board.dart';

/// A completed line of 5 belonging to a team.
class GameSequence {
  final int team;
  final List<Cell> cells;

  const GameSequence(this.team, this.cells);

  @override
  String toString() => 'Seq(team=$team, $cells)';
}

/// Occupancy grid: `board[r][c]` is the team index occupying a cell, or null
/// if empty. Corners are never stored as occupied — they are wild (see
/// [_ownedBy]). Use [emptyBoard] to allocate one.
typedef Occupancy = List<List<int?>>;

Occupancy emptyBoard() =>
    List.generate(kBoardSize, (_) => List<int?>.filled(kBoardSize, null));

/// A cell counts toward [team]'s sequences if the team occupies it OR it is a
/// free corner (corners are wild for every team).
bool _ownedBy(Occupancy board, int team, int r, int c) =>
    isCorner(r, c) || board[r][c] == team;

/// All 5-cell lines on the board, in deterministic scan order.
Iterable<List<Cell>> _allLines() sync* {
  for (var r = 0; r < kBoardSize; r++) {
    for (var c = 0; c < kBoardSize; c++) {
      for (final dir in kLineDirections) {
        final cells = <Cell>[];
        for (var i = 0; i < kSequenceLength; i++) {
          cells.add(Cell(r + dir[0] * i, c + dir[1] * i));
        }
        if (cells.last.isOnBoard) yield cells; // first is always on board
      }
    }
  }
}

/// Detects all sequences currently held by [team].
///
/// Honors the official overlap rule: *only one chip from an existing completed
/// sequence may be reused in another sequence.* We accept complete lines
/// greedily in deterministic order; a candidate is accepted only if at most one
/// of its cells is already part of an accepted sequence.
List<GameSequence> detectSequences(Occupancy board, int team) {
  final result = <GameSequence>[];
  final used = <Cell>{};

  for (final line in _allLines()) {
    final complete =
        line.every((cell) => _ownedBy(board, team, cell.row, cell.col));
    if (!complete) continue;

    final shared = line.where(used.contains).length;
    if (shared > 1) continue; // would reuse more than one locked chip

    result.add(GameSequence(team, List.unmodifiable(line)));
    used.addAll(line);
  }
  return result;
}

int countSequences(Occupancy board, int team) =>
    detectSequences(board, team).length;

/// Number of teams present (max team index + 1). Used to scan all teams.
int _teamCount(Occupancy board) {
  var max = -1;
  for (final row in board) {
    for (final v in row) {
      if (v != null && v > max) max = v;
    }
  }
  return max + 1;
}

/// All cells that belong to a completed sequence of *any* team — these chips
/// are locked and cannot be removed by a one-eyed Jack.
Set<Cell> lockedCells(Occupancy board) {
  final locked = <Cell>{};
  for (var team = 0; team < _teamCount(board); team++) {
    for (final seq in detectSequences(board, team)) {
      locked.addAll(seq.cells);
    }
  }
  return locked;
}

/// Whether the chip at [cell] is protected from removal (part of a sequence).
/// Corners are not chips and are never "removable" in the first place.
bool isCellLocked(Occupancy board, Cell cell) =>
    lockedCells(board).contains(cell);
