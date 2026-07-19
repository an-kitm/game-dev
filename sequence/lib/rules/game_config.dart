import 'cards.dart';

/// Game setup rules: legal player/team counts, hand sizes, win thresholds,
/// seating and dealing. Pure functions — mirrored by the server.

/// Hand size by number of players (official Sequence table).
int handSize(int numPlayers) {
  switch (numPlayers) {
    case 2:
      return 7;
    case 3:
    case 4:
      return 6;
    case 6:
      return 5;
    case 8:
    case 9:
      return 4;
    case 10:
    case 12:
      return 3;
    default:
      throw ArgumentError('Unsupported player count: $numPlayers');
  }
}

/// 2 teams must complete 2 sequences to win; 3 teams need only 1.
int sequencesToWin(int numTeams) {
  switch (numTeams) {
    case 2:
      return 2;
    case 3:
      return 1;
    default:
      throw ArgumentError('numTeams must be 2 or 3, got $numTeams');
  }
}

/// Players must divide evenly into [numTeams] equal teams, and the resulting
/// player count must have a defined hand size.
bool isValidSetup(int numPlayers, int numTeams) {
  if (numTeams != 2 && numTeams != 3) return false;
  if (numPlayers < numTeams) return false;
  if (numPlayers % numTeams != 0) return false;
  const supported = {2, 3, 4, 6, 8, 9, 10, 12};
  return supported.contains(numPlayers);
}

/// Team index (0-based) for a seat, so turn order alternates between teams.
int teamForSeat(int seatIndex, int numTeams) => seatIndex % numTeams;

/// True when the lobby is ready to start: the total is a supported player count
/// AND every team has the same number of players (each ≥ 1). Players may switch
/// teams freely, so we validate the actual distribution — [teamOf] is each
/// player's chosen team. Mirrors the equal-teams check in `start_game`.
bool teamsReady(Iterable<int> teamOf, int numTeams) {
  final teams = teamOf.toList();
  if (!isValidSetup(teams.length, numTeams)) return false;
  final counts = List.filled(numTeams, 0);
  for (final t in teams) {
    if (t < 0 || t >= numTeams) return false;
    counts[t]++;
  }
  final first = counts.first;
  return counts.every((c) => c > 0 && c == first);
}

/// Result of dealing: one hand per seat plus the remaining draw deck.
class Deal {
  final List<List<PlayingCard>> hands;
  final List<PlayingCard> remainingDeck;
  const Deal(this.hands, this.remainingDeck);
}

/// Deals [handSize] cards to each of [numPlayers] from the front of [deck].
/// [deck] is assumed already shuffled; it is not mutated.
Deal deal(List<PlayingCard> deck, int numPlayers) {
  final size = handSize(numPlayers);
  final hands = List.generate(numPlayers, (_) => <PlayingCard>[]);
  var idx = 0;
  for (var round = 0; round < size; round++) {
    for (var p = 0; p < numPlayers; p++) {
      hands[p].add(deck[idx++]);
    }
  }
  return Deal(hands, deck.sublist(idx));
}
