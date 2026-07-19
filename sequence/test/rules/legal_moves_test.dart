import 'package:flutter_test/flutter_test.dart';
import 'package:sequence/rules/board.dart';
import 'package:sequence/rules/board_layout.dart';
import 'package:sequence/rules/legal_moves.dart';
import 'package:sequence/rules/sequence_detector.dart';

void main() {
  test('normal card targets its empty cells', () {
    final board = emptyBoard();
    final cells = cellsForCard('AS');
    final legal = legalCellsFor(card: 'AS', board: board, locked: {}, myTeam: 0);
    expect(legal, cells.toSet());

    // Occupy one of them -> only the other remains legal.
    board[cells.first.row][cells.first.col] = 1;
    final legal2 =
        legalCellsFor(card: 'AS', board: board, locked: {}, myTeam: 0);
    expect(legal2, {cells.last});
  });

  test('two-eyed jack targets all empty non-corner cells', () {
    final board = emptyBoard();
    final legal = legalCellsFor(card: 'JD', board: board, locked: {}, myTeam: 0);
    expect(legal.length, 96); // 100 - 4 corners
    expect(legal.any((c) => isCorner(c.row, c.col)), isFalse);
  });

  test('one-eyed jack targets unlocked opponent chips only', () {
    final board = emptyBoard();
    board[3][3] = 1; // opponent chip
    board[4][4] = 0; // own chip
    board[5][5] = 1; // opponent chip but we will lock it
    final locked = {const Cell(5, 5)};
    final legal =
        legalCellsFor(card: 'JS', board: board, locked: locked, myTeam: 0);
    expect(legal, {const Cell(3, 3)});
  });

  test('isDeadCard true only when both cells are occupied', () {
    final board = emptyBoard();
    final cells = cellsForCard('5D');
    expect(isDeadCard('5D', board), isFalse);
    board[cells.first.row][cells.first.col] = 0;
    expect(isDeadCard('5D', board), isFalse);
    board[cells.last.row][cells.last.col] = 1;
    expect(isDeadCard('5D', board), isTrue);
    // Jacks are never dead.
    expect(isDeadCard('JD', board), isFalse);
  });
}
