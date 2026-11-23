import 'package:flutter_test/flutter_test.dart';
import 'package:sequence/models/move.dart';
import 'package:sequence/rules/board.dart';

Move place(int seq, int team, int r, int c, [String card = '7H']) =>
    Move(seq: seq, type: 'place', playerId: 'p$team', card: card, row: r, col: c, team: team);

Move remove(int seq, int team, int r, int c) =>
    Move(seq: seq, type: 'remove', playerId: 'p$team', card: 'JS', row: r, col: c, team: team);

void main() {
  group('Move.fromMap', () {
    test('reads a place move and its payload', () {
      final m = Move.fromMap({
        'seq': 3,
        'type': 'place',
        'player_id': 'abc',
        'payload': {'card': 'JD', 'row': 2, 'col': 5, 'team': 1},
      });
      expect(m.isPlace, isTrue);
      expect(m.card, 'JD');
      expect(m.cell, const Cell(2, 5));
      expect(m.team, 1);
    });

    test('a start move has no player, card or cell', () {
      final m = Move.fromMap({'seq': 1, 'type': 'start', 'player_id': null, 'payload': {'players': 2}});
      expect(m.isStart, isTrue);
      expect(m.playerId, isNull);
      expect(m.cell, isNull);
    });

    test('a dead-card swap has a card but no cell', () {
      final m = Move.fromMap({'seq': 4, 'type': 'dead', 'player_id': 'abc', 'payload': {'card': '9C'}});
      expect(m.isDeadSwap, isTrue);
      expect(m.card, '9C');
      expect(m.cell, isNull);
    });
  });

  group('removedChipTeams', () {
    test("credits a removal to the team whose chip sat on the cell", () {
      final moves = [place(2, 0, 1, 1), place(3, 1, 4, 4), remove(4, 1, 1, 1)];
      expect(removedChipTeams(moves), {4: 0});
    });

    test('uses the latest chip when a cell was refilled', () {
      final moves = [
        place(2, 0, 1, 1),
        remove(3, 1, 1, 1),
        place(4, 2, 1, 1),
        remove(5, 0, 1, 1),
      ];
      expect(removedChipTeams(moves), {3: 0, 5: 2});
    });

    test('leaves a removal unattributed when no placement is known', () {
      expect(removedChipTeams([remove(2, 1, 0, 3)]), isEmpty);
    });
  });

  test('lastBoardMove skips moves without a cell', () {
    final moves = [
      const Move(seq: 1, type: 'start'),
      place(2, 0, 3, 3),
      const Move(seq: 3, type: 'dead', playerId: 'p1', card: '9C'),
    ];
    expect(lastBoardMove(moves)?.seq, 2);
    expect(lastBoardMove(const []), isNull);
  });
}
