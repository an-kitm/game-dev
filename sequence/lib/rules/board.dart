// Board geometry for Sequence. Layout-independent: this file knows nothing
// about which card sits on which cell, only the 10x10 grid + corners.

const int kBoardSize = 10;

/// Length of a winning line.
const int kSequenceLength = 5;

/// A board coordinate. Immutable with value equality so it can live in Sets.
class Cell {
  final int row;
  final int col;

  const Cell(this.row, this.col);

  bool get isOnBoard =>
      row >= 0 && row < kBoardSize && col >= 0 && col < kBoardSize;

  @override
  bool operator ==(Object other) =>
      other is Cell && other.row == row && other.col == col;

  @override
  int get hashCode => row * kBoardSize + col;

  @override
  String toString() => '($row,$col)';
}

/// The four free corners. They act as wild chips belonging to every team.
bool isCorner(int row, int col) =>
    (row == 0 || row == kBoardSize - 1) &&
    (col == 0 || col == kBoardSize - 1);

const List<Cell> kCorners = [
  Cell(0, 0),
  Cell(0, kBoardSize - 1),
  Cell(kBoardSize - 1, 0),
  Cell(kBoardSize - 1, kBoardSize - 1),
];

/// The four directions that define a line. Each line is scanned once; the
/// reverse directions would only produce duplicate lines.
const List<List<int>> kLineDirections = [
  [0, 1], // horizontal →
  [1, 0], // vertical ↓
  [1, 1], // diagonal ↘
  [1, -1], // diagonal ↙
];
