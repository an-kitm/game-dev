import 'package:flutter_test/flutter_test.dart';
import 'package:sequence/rules/cards.dart';

void main() {
  test('standard deck has 52 distinct cards', () {
    final deck = standardDeck52;
    expect(deck.length, 52);
    expect(deck.toSet().length, 52);
  });

  test('board cards are the 48 non-Jacks', () {
    final cards = boardCards48;
    expect(cards.length, 48);
    expect(cards.any((c) => c.isJack), isFalse);
  });

  test('draw deck is two full decks = 104 cards', () {
    expect(buildDrawDeck().length, 104);
  });

  test('Jack eyedness classification', () {
    expect(const PlayingCard(Rank.jack, Suit.diamonds).isTwoEyedJack, isTrue);
    expect(const PlayingCard(Rank.jack, Suit.clubs).isTwoEyedJack, isTrue);
    expect(const PlayingCard(Rank.jack, Suit.spades).isOneEyedJack, isTrue);
    expect(const PlayingCard(Rank.jack, Suit.hearts).isOneEyedJack, isTrue);
    // A two-eyed jack is not one-eyed and vice versa.
    expect(const PlayingCard(Rank.jack, Suit.diamonds).isOneEyedJack, isFalse);
    expect(const PlayingCard(Rank.jack, Suit.spades).isTwoEyedJack, isFalse);
  });

  test('card code round-trips', () {
    for (final code in ['AS', '10H', 'JD', 'KC', '2D', 'QS']) {
      expect(PlayingCard.fromCode(code).code, code);
    }
  });
}
