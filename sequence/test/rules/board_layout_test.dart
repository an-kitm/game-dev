import 'package:flutter_test/flutter_test.dart';
import 'package:sequence/rules/board.dart';
import 'package:sequence/rules/board_layout.dart';
import 'package:sequence/rules/cards.dart';

void main() {
  final layout = kBoardLayout;

  test('layout is 10x10', () {
    expect(layout.length, kBoardSize);
    expect(layout.every((row) => row.length == kBoardSize), isTrue);
  });

  test('the four corners are free (null)', () {
    for (final corner in kCorners) {
      expect(layout[corner.row][corner.col], isNull);
    }
  });

  test('exactly 96 card cells', () {
    final filled = layout.expand((r) => r).where((c) => c != null).length;
    expect(filled, 96);
  });

  test('every non-Jack card appears exactly twice and no Jacks appear', () {
    final counts = <String, int>{};
    for (final row in layout) {
      for (final code in row) {
        if (code != null) counts[code] = (counts[code] ?? 0) + 1;
      }
    }
    for (final card in boardCards48) {
      expect(counts[card.code], 2, reason: '${card.code} should appear twice');
    }
    // No jack codes present.
    expect(counts.keys.any((c) => c.startsWith('J')), isFalse);
    // 48 distinct codes.
    expect(counts.keys.length, 48);
  });

  test('cellsForCard returns the two positions of a card', () {
    final cells = cellsForCard('AS');
    expect(cells.length, 2);
    for (final cell in cells) {
      expect(layout[cell.row][cell.col], 'AS');
    }
  });
}
