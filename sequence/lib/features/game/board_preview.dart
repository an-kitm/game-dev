import 'package:flutter/material.dart';

import '../../rules/board.dart';
import '../../rules/sequence_detector.dart';
import 'widgets/board_view.dart';
import 'widgets/hand_bar.dart';
import 'widgets/turn_rail.dart';

/// DEV-ONLY preview of the board + hand with mock data, for visual checks.
/// Remove the /preview route before shipping.
class BoardPreview extends StatefulWidget {
  const BoardPreview({super.key});

  @override
  State<BoardPreview> createState() => _BoardPreviewState();
}

class _BoardPreviewState extends State<BoardPreview> {
  String? _selected;

  @override
  Widget build(BuildContext context) {
    final board = emptyBoard();
    // Team 0 (blue) horizontal sequence on row 1.
    for (var c = 0; c < 5; c++) {
      board[1][c] = 0;
    }
    // Team 1 (red) scattered + a diagonal start.
    board[3][4] = 1;
    board[4][5] = 1;
    board[5][6] = 1;
    board[2][7] = 1;
    // Team 2 (green) a couple.
    board[6][2] = 2;
    board[6][3] = 2;

    final locked = lockedCells(board);
    final highlighted = {const Cell(0, 5), const Cell(4, 4)};

    return Scaffold(
      appBar: AppBar(title: const Text('Board preview (dev)')),
      body: Column(
        children: [
          // Mock 9-player / 3-team rotation: Blue→Green→Red, repeating.
          const TurnRail(seats: [
            TurnSeat(name: 'Alice', team: 0),
            TurnSeat(name: 'Bea', team: 1),
            TurnSeat(name: 'Cal', team: 2, isCurrent: true),
            TurnSeat(name: 'Dani', team: 0),
            TurnSeat(name: 'Eli', team: 1),
            TurnSeat(name: 'Fin', team: 2),
            TurnSeat(name: 'Gus', team: 0),
            TurnSeat(name: 'Hana', team: 1),
            TurnSeat(name: 'Ivy', team: 2, isOnline: false),
          ]),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.all(8),
              child: BoardView(
                board: board,
                locked: locked,
                highlighted: highlighted,
                lastMove: const Cell(3, 4), // white last-move ring
                onCellTap: (r, c) =>
                    ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text('Tapped ($r,$c)'),
                    duration: const Duration(milliseconds: 600),
                  ),
                ),
              ),
            ),
          ),
          HandBar(
            cards: const ['AS', '10H', 'JD', 'JS', 'QC', '5D', '7H'],
            selected: _selected,
            deadCards: const {'QC'}, // shows the DEAD badge
            onCardTap: (card) => setState(
                () => _selected = _selected == card ? null : card),
          ),
        ],
      ),
    );
  }
}
