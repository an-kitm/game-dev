import 'package:flutter/material.dart';

import '../../../core/theme.dart';

/// One seat in the turn rotation.
class TurnSeat {
  final String name;
  final int team;
  final bool isCurrent;
  final bool isOnline;
  const TurnSeat({
    required this.name,
    required this.team,
    this.isCurrent = false,
    this.isOnline = true,
  });
}

/// A horizontal strip showing the full turn rotation in order, with the player
/// whose turn it is highlighted. Scrolls when there are many players, and keeps
/// the active player in view.
class TurnRail extends StatefulWidget {
  final List<TurnSeat> seats;
  const TurnRail({super.key, required this.seats});

  @override
  State<TurnRail> createState() => _TurnRailState();
}

class _TurnRailState extends State<TurnRail> {
  final _scroll = ScrollController();
  static const _itemExtent = 60.0; // token width + separators

  @override
  void didUpdateWidget(TurnRail oldWidget) {
    super.didUpdateWidget(oldWidget);
    _centerActive();
  }

  void _centerActive() {
    final i = widget.seats.indexWhere((s) => s.isCurrent);
    if (i < 0 || !_scroll.hasClients) return;
    final target = (i * _itemExtent) -
        (_scroll.position.viewportDimension / 2) +
        (_itemExtent / 2);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scroll.hasClients) return;
      _scroll.animateTo(
        target.clamp(0.0, _scroll.position.maxScrollExtent),
        duration: const Duration(milliseconds: 300),
        curve: kEaseSoft,
      );
    });
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.fromLTRB(8, 8, 8, 0),
      padding: const EdgeInsets.symmetric(vertical: 10),
      decoration: BoxDecoration(
        color: kSurface,
        borderRadius: BorderRadius.circular(kRadiusControl),
        border: Border.all(color: kLine),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 0, 14, 8),
            child: Text('TURN ORDER', style: eyebrow()),
          ),
          SizedBox(
            height: 62,
            child: ListView.separated(
              controller: _scroll,
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              itemCount: widget.seats.length,
              separatorBuilder: (_, _) => const Icon(
                  Icons.chevron_right_rounded,
                  size: 16,
                  color: kLine),
              itemBuilder: (context, i) => _SeatToken(seat: widget.seats[i]),
            ),
          ),
        ],
      ),
    );
  }
}

class _SeatToken extends StatelessWidget {
  final TurnSeat seat;
  const _SeatToken({required this.seat});

  @override
  Widget build(BuildContext context) {
    final c = teamColor(seat.team);
    final name = seat.name.length > 7
        ? '${seat.name.substring(0, 6)}…'
        : seat.name;
    return Opacity(
      opacity: seat.isOnline ? 1 : 0.45,
      child: SizedBox(
        width: 44,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            AnimatedContainer(
              duration: const Duration(milliseconds: 220),
              curve: kEaseSoft,
              width: 40,
              height: 40,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(
                  color: seat.isCurrent ? c : Colors.transparent,
                  width: 2.5,
                ),
                boxShadow: seat.isCurrent
                    ? [
                        BoxShadow(
                            color: c.withValues(alpha: 0.35),
                            blurRadius: 9,
                            spreadRadius: 1),
                      ]
                    : null,
              ),
              child: TeamDot(team: seat.team, size: seat.isCurrent ? 30 : 26),
            ),
            const SizedBox(height: 4),
            Text(
              name,
              maxLines: 1,
              overflow: TextOverflow.clip,
              style: archivo(
                weight: seat.isCurrent ? FontWeight.w800 : FontWeight.w600,
                color: seat.isCurrent ? kInk : kMuted,
                size: 11,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
