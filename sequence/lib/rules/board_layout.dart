import 'board.dart';

/// The official Sequence board card-to-cell layout (transcribed from the
/// physical board and validated: every one of the 48 non-Jack cards appears on
/// exactly two cells, the four corners are FREE, and no Jacks appear).
///
/// This is the single source of truth for *which card sits on which cell*,
/// used for rendering and for validating that a played card matches its cell.
/// The same layout is mirrored into the database via `tool/gen_board_sql.dart`
/// (regenerate `supabase/migrations/0002_board_layout.sql` after any change).
///
/// `null` marks a free corner.
typedef BoardLayout = List<List<String?>>;

const BoardLayout kBoardLayout = <List<String?>>[
  [null, '6D', '7D', '8D', '9D', '10D', 'QD', 'KD', 'AD', null],
  ['5D', '3H', '2H', '2S', '3S', '4S', '5S', '6S', '7S', 'AC'],
  ['4D', '4H', 'KD', 'AD', 'AC', 'KC', 'QC', '10C', '8S', 'KC'],
  ['3D', '5H', 'QD', 'QH', '10H', '9H', '8H', '9C', '9S', 'QC'],
  ['2D', '6H', '10D', 'KH', '3H', '2H', '7H', '8C', '10S', '10C'],
  ['AS', '7H', '9D', 'AH', '4H', '5H', '6H', '7C', 'QS', '9C'],
  ['KS', '8H', '8D', '2C', '3C', '4C', '5C', '6C', 'KS', '8C'],
  ['QS', '9H', '7D', '6D', '5D', '4D', '3D', '2D', 'AS', '7C'],
  ['10S', '10H', 'QH', 'KH', 'AH', '2C', '3C', '4C', '5C', '6C'],
  [null, '9S', '8S', '7S', '6S', '5S', '4S', '3S', '2S', null],
];

/// The two cells (never zero, never one) carrying a given card code.
List<Cell> cellsForCard(String cardCode, [BoardLayout? layout]) {
  final l = layout ?? kBoardLayout;
  final cells = <Cell>[];
  for (var r = 0; r < kBoardSize; r++) {
    for (var c = 0; c < kBoardSize; c++) {
      if (l[r][c] == cardCode) cells.add(Cell(r, c));
    }
  }
  return cells;
}
