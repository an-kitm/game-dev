// Pure card model for Sequence. No Flutter / Supabase dependencies so the
// whole `rules/` module is trivially unit-testable.

enum Suit { spades, hearts, diamonds, clubs }

enum Rank { ace, two, three, four, five, six, seven, eight, nine, ten, jack, queen, king }

const Map<Suit, String> _suitCode = {
  Suit.spades: 'S',
  Suit.hearts: 'H',
  Suit.diamonds: 'D',
  Suit.clubs: 'C',
};

const Map<Rank, String> _rankCode = {
  Rank.ace: 'A',
  Rank.two: '2',
  Rank.three: '3',
  Rank.four: '4',
  Rank.five: '5',
  Rank.six: '6',
  Rank.seven: '7',
  Rank.eight: '8',
  Rank.nine: '9',
  Rank.ten: '10',
  Rank.jack: 'J',
  Rank.queen: 'Q',
  Rank.king: 'K',
};

/// A playing card. Serialized as a short code, e.g. `AS`, `10H`, `JD`.
class PlayingCard {
  final Rank rank;
  final Suit suit;

  const PlayingCard(this.rank, this.suit);

  String get code => '${_rankCode[rank]}${_suitCode[suit]}';

  bool get isJack => rank == Rank.jack;

  /// Two-eyed Jacks (Diamonds, Clubs) are wild — place a chip anywhere open.
  bool get isTwoEyedJack =>
      isJack && (suit == Suit.diamonds || suit == Suit.clubs);

  /// One-eyed Jacks (Spades, Hearts) remove one opponent chip.
  bool get isOneEyedJack =>
      isJack && (suit == Suit.spades || suit == Suit.hearts);

  static PlayingCard fromCode(String code) {
    final suitChar = code.substring(code.length - 1);
    final rankChars = code.substring(0, code.length - 1);
    final suit = _suitCode.entries.firstWhere((e) => e.value == suitChar).key;
    final rank = _rankCode.entries.firstWhere((e) => e.value == rankChars).key;
    return PlayingCard(rank, suit);
  }

  @override
  bool operator ==(Object other) =>
      other is PlayingCard && other.rank == rank && other.suit == suit;

  @override
  int get hashCode => Object.hash(rank, suit);

  @override
  String toString() => code;
}

/// All 52 distinct cards in a fixed order (used to build the board + deck).
List<PlayingCard> get standardDeck52 => [
      for (final suit in Suit.values)
        for (final rank in Rank.values) PlayingCard(rank, suit),
    ];

/// The 48 non-Jack cards — each appears exactly twice on the board.
List<PlayingCard> get boardCards48 =>
    standardDeck52.where((c) => !c.isJack).toList(growable: false);

/// Two full 52-card decks shuffled together = 104 cards (the draw deck).
List<PlayingCard> buildDrawDeck() => [...standardDeck52, ...standardDeck52];
