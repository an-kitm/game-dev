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
/// whose turn it is highlighted. Names are shown in full — each seat is as
/// wide as its name — and the strip scrolls when they don't all fit, keeping
/// the active player in view.
class TurnRail extends StatefulWidget {
  final List<TurnSeat> seats;

  /// Drop the "TURN ORDER" label and tighten padding, for short screens.
  final bool compact;

  /// Lay the seats out in wrapping lines instead of one scrolling strip, so
  /// every full name is visible at once (the wide layout's sidebar).
  final bool wrap;
  const TurnRail({
    super.key,
    required this.seats,
    this.compact = false,
    this.wrap = false,
  });

  @override
  State<TurnRail> createState() => _TurnRailState();
}

class _TurnRailState extends State<TurnRail> {
  final _scroll = ScrollController();
  // Seats vary in width with their names, so centre the active one by its
  // actual position rather than by an assumed fixed width.
  final _activeKey = GlobalKey();

  @override
  void initState() {
    super.initState();
    _centerActive(animate: false);
  }

  @override
  void didUpdateWidget(TurnRail oldWidget) {
    super.didUpdateWidget(oldWidget);
    _centerActive();
  }

  void _centerActive({bool animate = true}) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final active = _activeKey.currentContext;
      if (active == null || !active.mounted) return;
      Scrollable.ensureVisible(
        active,
        alignment: 0.5,
        duration: animate ? const Duration(milliseconds: 300) : Duration.zero,
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
      padding: EdgeInsets.symmetric(vertical: widget.compact ? 6 : 10),
      decoration: BoxDecoration(
        color: kSurface,
        borderRadius: BorderRadius.circular(kRadiusControl),
        border: Border.all(color: kLine),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (!widget.compact)
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 0, 14, 8),
              child: Text('TURN ORDER', style: eyebrow()),
            ),
          if (widget.wrap)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Wrap(
                spacing: 2,
                runSpacing: 10,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  for (var i = 0; i < widget.seats.length; i++) ...[
                    _SeatToken(seat: widget.seats[i]),
                    if (i < widget.seats.length - 1) _chevron,
                  ],
                ],
              ),
            )
          else
          SizedBox(
            height: 62,
            child: ListView.separated(
              controller: _scroll,
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              itemCount: widget.seats.length,
              separatorBuilder: (_, _) => _chevron,
              itemBuilder: (context, i) => _SeatToken(
                key: widget.seats[i].isCurrent ? _activeKey : null,
                seat: widget.seats[i],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

const _chevron = Icon(Icons.chevron_right_rounded, size: 16, color: kLine);

class _SeatToken extends StatelessWidget {
  final TurnSeat seat;
  const _SeatToken({super.key, required this.seat});

  @override
  Widget build(BuildContext context) {
    final c = teamColor(seat.team);
    return Opacity(
      opacity: seat.isOnline ? 1 : 0.45,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minWidth: 44),
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
              seat.name, // in full (nicknames are at most 16 characters)
              maxLines: 1,
              softWrap: false,
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
