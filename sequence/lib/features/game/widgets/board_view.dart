import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../core/theme.dart';
import '../../../rules/board.dart';
import '../../../rules/board_layout.dart';
import 'card_cell.dart';

/// Renders the 10x10 Sequence board inside a calm white panel topped by a 4px
/// bar in the current team's color. The panel is square and sized to the
/// tighter of the available width and height, so it fits a tall phone and a
/// wide desktop window alike. Optionally supports pinch-to-zoom / pan (the
/// grid is dense on a phone).
class BoardView extends StatelessWidget {
  /// Occupancy grid: team index or null per cell.
  final List<List<int?>> board;
  final Set<Cell> locked;
  final Set<Cell> highlighted;
  final Cell? lastMove;

  /// The current team's color — drawn as the panel's top accent bar.
  final Color accent;

  /// When set, locked cells owned by this team pulse as the winning sequence.
  final int? winningTeam;
  final void Function(int row, int col)? onCellTap;

  /// Pinch / scroll-wheel zoom and pan.
  final bool zoomable;

  const BoardView({
    super.key,
    required this.board,
    this.locked = const {},
    this.highlighted = const {},
    this.lastMove,
    this.accent = kAccentDefault,
    this.winningTeam,
    this.onCellTap,
    this.zoomable = true,
  });

  @override
  Widget build(BuildContext context) {
    final layout = kBoardLayout;
    return LayoutBuilder(builder: (context, outer) {
      final side = _shortestFinite(outer.maxWidth, outer.maxHeight);
      return Center(
        child: SizedBox.square(
          dimension: side,
          child: Container(
            decoration: BoxDecoration(
              color: kSurface,
              borderRadius: BorderRadius.circular(kRadiusPanel),
              border: Border.all(color: kLine),
              boxShadow: kPanelShadow,
            ),
            clipBehavior: Clip.antiAlias,
            child: Column(
              children: [
                // Top bar — a single colored thread guiding the eye to whose turn it is.
                AnimatedContainer(
                  duration: const Duration(milliseconds: 300),
                  height: 4,
                  color: accent,
                ),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: LayoutBuilder(
                      builder: (context, constraints) {
                        // Always fit (never clip) — on a tiny screen the
                        // cells get small and pinch-zoom takes over.
                        final fit = _shortestFinite(
                            constraints.maxWidth, constraints.maxHeight);
                        final cell =
                            ((fit - kBoardSize * 2) / kBoardSize).clamp(10.0, 80.0);
                        return InteractiveViewer(
                          minScale: 1,
                          maxScale: 4,
                          scaleEnabled: zoomable,
                          panEnabled: zoomable,
                          child: Center(
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                for (var r = 0; r < kBoardSize; r++)
                                  Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      for (var c = 0; c < kBoardSize; c++)
                                        CardCell(
                                          cardCode: layout[r][c],
                                          team: board[r][c],
                                          locked: locked.contains(Cell(r, c)),
                                          highlighted:
                                              highlighted.contains(Cell(r, c)),
                                          isLastMove: lastMove == Cell(r, c),
                                          isWinning: winningTeam != null &&
                                              board[r][c] == winningTeam &&
                                              locked.contains(Cell(r, c)),
                                          accent: accent,
                                          size: cell,
                                          onTap: onCellTap == null
                                              ? null
                                              : () => onCellTap!(r, c),
                                        ),
                                    ],
                                  ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    });
  }
}

/// The smaller of two extents, ignoring an unbounded one.
double _shortestFinite(double a, double b) {
  if (!a.isFinite) return b;
  if (!b.isFinite) return a;
  return math.min(a, b);
}
