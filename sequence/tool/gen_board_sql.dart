// Generates the board-layout data migration from the Dart source of truth so
// the client and server can never disagree about which card sits on a cell.
//
// Regenerate with:
//   dart run tool/gen_board_sql.dart > supabase/migrations/0002_board_layout.sql

import 'package:sequence/rules/board.dart';
import 'package:sequence/rules/board_layout.dart';
import 'package:sequence/rules/cards.dart';

void main() {
  final layout = kBoardLayout;
  final out = StringBuffer()
    ..writeln('-- GENERATED from lib/rules/board_layout.dart — do not edit by hand.')
    ..writeln('-- Regenerate: dart run tool/gen_board_sql.dart > '
        'supabase/migrations/0002_board_layout.sql')
    ..writeln()
    ..writeln('truncate board_layout;')
    ..writeln('insert into board_layout (row, col, card) values');

  final rows = <String>[];
  for (var r = 0; r < kBoardSize; r++) {
    for (var c = 0; c < kBoardSize; c++) {
      final card = layout[r][c];
      if (card == null) continue; // free corner
      rows.add("  ($r, $c, '$card')");
    }
  }
  out
    ..writeln('${rows.join(',\n')};')
    ..writeln()
    ..writeln('-- The 52 distinct card codes, in fixed order; the draw deck is two of these.')
    ..writeln('create or replace function deck_template() returns text[]')
    ..writeln(r'  language sql immutable as $$')
    ..writeln('  select array[${standardDeck52.map((c) => "'${c.code}'").join(', ')}]::text[];')
    ..writeln(r'$$;');

  // ignore: avoid_print
  print(out.toString());
}
