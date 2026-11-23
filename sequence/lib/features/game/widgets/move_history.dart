import 'package:flutter/material.dart';

import '../../../core/theme.dart';
import '../../../models/move.dart';
import '../../../models/player.dart';
import '../../../rules/board_layout.dart';
import '../../../rules/cards.dart';

const Map<String, String> _suitGlyph = {'S': '♠', 'H': '♥', 'D': '♦', 'C': '♣'};

/// The room's move log as sentences, newest first: who played which card, a
/// Jack used as a wild or to remove a chip, dead cards swapped.
class MoveHistory extends StatelessWidget {
  /// Oldest first, as the moves stream delivers them.
  final List<Move> moves;

  /// Everyone currently in the room. A player who has since left is no longer
  /// here, so their moves are attributed by team colour only.
  final List<Player> players;
  final String? myUserId;

  const MoveHistory({
    super.key,
    required this.moves,
    required this.players,
    required this.myUserId,
  });

  @override
  Widget build(BuildContext context) {
    if (moves.isEmpty) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 8),
        child: Text('No moves yet.', style: TextStyle(color: kMuted, fontSize: 13)),
      );
    }
    final byId = {for (final p in players) p.id: p};
    final removed = removedChipTeams(moves);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final m in moves.reversed)
          _MoveRow(
            move: m,
            player: m.playerId == null ? null : byId[m.playerId],
            isMe: m.playerId != null && byId[m.playerId]?.userId == myUserId,
            removedTeam: removed[m.seq],
          ),
      ],
    );
  }
}

class _MoveRow extends StatelessWidget {
  final Move move;
  final Player? player;
  final bool isMe;
  final int? removedTeam;

  const _MoveRow({
    required this.move,
    required this.player,
    required this.isMe,
    required this.removedTeam,
  });

  @override
  Widget build(BuildContext context) {
    final team = move.team ?? player?.team;
    const body = TextStyle(color: kBody, fontSize: 13, height: 1.35);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: team == null
                ? Container(
                    width: 14,
                    height: 14,
                    decoration: const BoxDecoration(
                        color: kLine, shape: BoxShape.circle),
                  )
                : TeamDot(team: team, size: 14),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text.rich(
              TextSpan(style: body, children: _sentence()),
            ),
          ),
        ],
      ),
    );
  }

  List<InlineSpan> _sentence() {
    if (move.isStart) return const [TextSpan(text: 'Game started')];

    final who = TextSpan(
      text: isMe ? 'You' : (player?.nickname ?? 'A player who left'),
      style: archivo(weight: FontWeight.w700, color: kInk, size: 13),
    );
    final card = move.card;
    final cell = move.cell;
    final cellCard = cell == null ? null : kBoardLayout[cell.row][cell.col];

    if (move.isDeadSwap) {
      return [who, const TextSpan(text: ' swapped dead card '), ?_card(card)];
    }
    if (move.isRemove) {
      final t = removedTeam;
      return [
        who,
        const TextSpan(text: ' removed '),
        if (t != null) ...[
          TextSpan(
            text: teamName(t),
            style: TextStyle(color: teamColor(t), fontWeight: FontWeight.w700),
          ),
          const TextSpan(text: "'s chip"),
        ] else
          const TextSpan(text: 'a chip'),
        const TextSpan(text: ' from '),
        ?_card(cellCard),
        const TextSpan(text: ' with '),
        ?_card(card),
      ];
    }
    // A place: a normal card on its own cell, or a two-eyed Jack as a wild.
    final wild = card != null && PlayingCard.fromCode(card).isTwoEyedJack;
    return [
      who,
      const TextSpan(text: ' played '),
      ?_card(card),
      if (wild) ...[const TextSpan(text: ' (wild) on '), ?_card(cellCard)],
    ];
  }

  /// A card code as its rank and suit glyph in the suit's colour, e.g. 7♥.
  TextSpan? _card(String? code) {
    if (code == null || code.length < 2) return null;
    final suit = code.substring(code.length - 1);
    final rank = code.substring(0, code.length - 1);
    final red = suit == 'H' || suit == 'D';
    return TextSpan(
      text: '$rank${_suitGlyph[suit] ?? suit}',
      style: archivo(
          weight: FontWeight.w700, color: red ? kCardRed : kCardBlack, size: 13),
    );
  }
}
