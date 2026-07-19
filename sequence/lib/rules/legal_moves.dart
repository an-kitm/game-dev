import 'board.dart';
import 'board_layout.dart';
import 'cards.dart';

/// Computes the set of legal target cells for [card] given the current board.
/// Mirrors the server's `play_card` validation so the UI can highlight targets.
///
///  * one-eyed Jack  -> any opponent chip that is not locked (and not a corner)
///  * two-eyed Jack  -> any empty non-corner cell
///  * normal card    -> the card's own (up to two) cells that are empty
Set<Cell> legalCellsFor({
  required String card,
  required List<List<int?>> board,
  required Set<Cell> locked,
  required int myTeam,
}) {
  final pc = PlayingCard.fromCode(card);
  final result = <Cell>{};

  if (pc.isOneEyedJack) {
    for (var r = 0; r < kBoardSize; r++) {
      for (var c = 0; c < kBoardSize; c++) {
        if (isCorner(r, c)) continue;
        final occ = board[r][c];
        final cell = Cell(r, c);
        if (occ != null && occ != myTeam && !locked.contains(cell)) {
          result.add(cell);
        }
      }
    }
  } else if (pc.isTwoEyedJack) {
    for (var r = 0; r < kBoardSize; r++) {
      for (var c = 0; c < kBoardSize; c++) {
        if (!isCorner(r, c) && board[r][c] == null) result.add(Cell(r, c));
      }
    }
  } else {
    for (final cell in cellsForCard(card)) {
      if (board[cell.row][cell.col] == null) result.add(cell);
    }
  }
  return result;
}

/// A card is "dead" when both of its board cells are already occupied (Jacks,
/// which have no board cells, are never dead).
bool isDeadCard(String card, List<List<int?>> board) {
  final pc = PlayingCard.fromCode(card);
  if (pc.isJack) return false;
  final cells = cellsForCard(card);
  return cells.isNotEmpty && cells.every((c) => board[c.row][c.col] != null);
}
