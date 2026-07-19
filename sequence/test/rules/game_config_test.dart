import 'package:flutter_test/flutter_test.dart';
import 'package:sequence/rules/cards.dart';
import 'package:sequence/rules/game_config.dart';

void main() {
  test('hand sizes match the official table', () {
    expect(handSize(2), 7);
    expect(handSize(3), 6);
    expect(handSize(4), 6);
    expect(handSize(6), 5);
    expect(handSize(8), 4);
    expect(handSize(9), 4);
    expect(handSize(10), 3);
    expect(handSize(12), 3);
  });

  test('unsupported player counts throw', () {
    expect(() => handSize(5), throwsArgumentError);
    expect(() => handSize(11), throwsArgumentError);
  });

  test('sequences to win', () {
    expect(sequencesToWin(2), 2);
    expect(sequencesToWin(3), 1);
  });

  test('valid setups', () {
    expect(isValidSetup(2, 2), isTrue);
    expect(isValidSetup(4, 2), isTrue);
    expect(isValidSetup(12, 2), isTrue);
    expect(isValidSetup(3, 3), isTrue);
    expect(isValidSetup(6, 3), isTrue);
    expect(isValidSetup(9, 3), isTrue);
    // invalid
    expect(isValidSetup(3, 2), isFalse); // odd for 2 teams
    expect(isValidSetup(5, 2), isFalse); // no hand size
    expect(isValidSetup(4, 3), isFalse); // not divisible by 3
    expect(isValidSetup(2, 4), isFalse); // 4 teams unsupported
  });

  test('team assignment alternates by seat', () {
    expect(teamForSeat(0, 2), 0);
    expect(teamForSeat(1, 2), 1);
    expect(teamForSeat(2, 2), 0);
    expect(teamForSeat(0, 3), 0);
    expect(teamForSeat(1, 3), 1);
    expect(teamForSeat(2, 3), 2);
    expect(teamForSeat(3, 3), 0);
  });

  test('dealing distributes correct hand sizes and consumes the deck', () {
    final deck = buildDrawDeck(); // 104
    final result = deal(deck, 2);
    expect(result.hands.length, 2);
    expect(result.hands[0].length, 7);
    expect(result.hands[1].length, 7);
    expect(result.remainingDeck.length, 104 - 14);

    final result4 = deal(deck, 4);
    expect(result4.hands.every((h) => h.length == 6), isTrue);
    expect(result4.remainingDeck.length, 104 - 24);
  });
}
