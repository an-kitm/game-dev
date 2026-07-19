import 'package:flutter_test/flutter_test.dart';
import 'package:sequence/rules/board.dart';
import 'package:sequence/rules/sequence_detector.dart';

/// Places [team] on a run of [length] cells starting at (r,c) in direction
/// (dr,dc).
void place(Occupancy b, int team, int r, int c, int dr, int dc, int length) {
  for (var i = 0; i < length; i++) {
    b[r + dr * i][c + dc * i] = team;
  }
}

void main() {
  test('empty board has no sequences', () {
    expect(countSequences(emptyBoard(), 0), 0);
  });

  test('four in a row is not a sequence', () {
    final b = emptyBoard();
    place(b, 0, 1, 0, 0, 1, 4);
    expect(countSequences(b, 0), 0);
  });

  test('horizontal five in a row', () {
    final b = emptyBoard();
    place(b, 0, 1, 0, 0, 1, 5);
    expect(countSequences(b, 0), 1);
  });

  test('vertical five in a row', () {
    final b = emptyBoard();
    place(b, 0, 0, 1, 1, 0, 5);
    expect(countSequences(b, 0), 1);
  });

  test('diagonal five in a row', () {
    final b = emptyBoard();
    place(b, 0, 1, 1, 1, 1, 5);
    expect(countSequences(b, 0), 1);
  });

  test('another team does not get credit for your chips', () {
    final b = emptyBoard();
    place(b, 0, 1, 0, 0, 1, 5);
    expect(countSequences(b, 1), 0);
  });

  test('corner acts as a wild chip for the team', () {
    final b = emptyBoard();
    // Corner (0,0) is wild; team only needs the other four cells (0,1)-(0,4).
    place(b, 0, 0, 1, 0, 1, 4);
    expect(countSequences(b, 0), 1);
    // Works for a different team too — corners are shared.
    final b2 = emptyBoard();
    place(b2, 1, 0, 1, 0, 1, 4);
    expect(countSequences(b2, 1), 1);
  });

  test('nine in a row yields two sequences sharing one chip', () {
    final b = emptyBoard();
    place(b, 0, 1, 0, 0, 1, 9); // row 1 has no corners
    expect(countSequences(b, 0), 2);
  });

  test('two disjoint sequences count as two', () {
    final b = emptyBoard();
    place(b, 0, 1, 0, 0, 1, 5); // row 1
    place(b, 0, 3, 0, 0, 1, 5); // row 3
    expect(countSequences(b, 0), 2);
  });

  test('six in a row is a single sequence (cannot double-count overlap)', () {
    final b = emptyBoard();
    place(b, 0, 1, 0, 0, 1, 6); // row 1, six consecutive
    expect(countSequences(b, 0), 1);
  });

  test('perpendicular lines sharing exactly one chip count as two', () {
    final b = emptyBoard();
    place(b, 0, 1, 1, 0, 1, 5); // horizontal (1,1)-(1,5)
    place(b, 0, 2, 1, 1, 0, 4); // (2,1)-(5,1); with (1,1) makes a vertical 5
    // The vertical reuses only (1,1) from the horizontal -> allowed -> two.
    expect(countSequences(b, 0), 2);
  });

  test('locked cells include sequence chips and protect from removal', () {
    final b = emptyBoard();
    place(b, 0, 1, 0, 0, 1, 5);
    final locked = lockedCells(b);
    expect(locked.contains(const Cell(1, 0)), isTrue);
    expect(locked.contains(const Cell(1, 4)), isTrue);
    expect(isCellLocked(b, const Cell(1, 2)), isTrue);
    // A non-sequence chip is not locked.
    final b2 = emptyBoard();
    place(b2, 0, 5, 5, 0, 1, 3);
    expect(isCellLocked(b2, const Cell(5, 5)), isFalse);
  });
}
