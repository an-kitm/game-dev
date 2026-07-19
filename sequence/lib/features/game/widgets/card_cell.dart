import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../core/theme.dart';

const Map<String, String> _suitGlyph = {'S': '♠', 'H': '♥', 'D': '♦', 'C': '♣'};

/// One board cell: a playing-card face (or a free corner), optionally covered by
/// a team chip, with states for a valid target, a locked sequence chip, the most
/// recent move (ripple) and a winning sequence chip.
class CardCell extends StatelessWidget {
  final String? cardCode; // null => free corner
  final int? team; // chip owner, null => empty
  final bool locked; // part of a completed sequence
  final bool highlighted; // legal move target
  final bool isLastMove; // most recently played cell
  final bool isWinning; // part of the winning team's sequence
  final Color accent; // local player's team color (valid-target glow)
  final double size;
  final VoidCallback? onTap;

  const CardCell({
    super.key,
    required this.cardCode,
    required this.team,
    this.locked = false,
    this.highlighted = false,
    this.isLastMove = false,
    this.isWinning = false,
    this.accent = kAccentDefault,
    this.size = 56,
    this.onTap,
  });

  bool get isCorner => cardCode == null;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: size,
        height: size,
        margin: const EdgeInsets.all(1),
        decoration: BoxDecoration(
          gradient: isCorner
              ? const LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [kCornerTop, kCornerBottom],
                )
              : null,
          color: isCorner ? null : kSurface,
          borderRadius: BorderRadius.circular(kRadiusCell),
          border: Border.all(
            color: locked ? teamColor(team ?? 0) : kCellBorder,
            width: locked ? 2 : 1,
          ),
        ),
        child: Stack(
          alignment: Alignment.center,
          children: [
            if (isCorner)
              _FreeCorner(size: size)
            else
              _CardFace(code: cardCode!, size: size),
            if (highlighted)
              _PulseRing(color: accent, size: size, win: false),
            if (team != null)
              _Chip(team: team!, size: size, key: ValueKey('chip$team')),
            if (isLastMove && team != null)
              _Ripple(color: teamColor(team!), size: size),
            if (isWinning) _PulseRing(color: teamColor(team ?? 0), size: size, win: true),
          ],
        ),
      ),
    );
  }
}

class _FreeCorner extends StatelessWidget {
  final double size;
  const _FreeCorner({required this.size});

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(Icons.star_rounded, color: kLabel, size: size * 0.34),
        if (size >= 40)
          Text('FREE', style: mono(size: 7, color: kLabel, spacing: 1)),
      ],
    );
  }
}

class _CardFace extends StatelessWidget {
  final String code;
  final double size;
  const _CardFace({required this.code, required this.size});

  @override
  Widget build(BuildContext context) {
    final suit = code.substring(code.length - 1);
    final rank = code.substring(0, code.length - 1);
    final isRed = suit == 'H' || suit == 'D';
    final color = isRed ? kCardRed : kCardBlack;
    return Stack(
      children: [
        Positioned(
          top: size * 0.05,
          left: size * 0.09,
          child: Text(rank,
              style: archivo(
                  weight: FontWeight.w700, color: color, size: size * 0.2, height: 1)),
        ),
        Center(
          child: Text(_suitGlyph[suit] ?? suit,
              style: TextStyle(color: color, fontSize: size * 0.38, height: 1)),
        ),
      ],
    );
  }
}

/// The signature poker chip: a flat team-color disc (75% of the cell) with a
/// subtle top-light / bottom-shade, a dashed inner ring and a translucent hole,
/// dropping into place with a springy pop.
class _Chip extends StatelessWidget {
  final int team;
  final double size;
  const _Chip({required this.team, required this.size, super.key});

  @override
  Widget build(BuildContext context) {
    final base = teamColor(team);
    final d = size * 0.75;
    final chip = Container(
      width: d,
      height: d,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Color.lerp(base, Colors.white, 0.28)!,
            base,
            Color.lerp(base, Colors.black, 0.22)!,
          ],
          stops: const [0, 0.52, 1],
        ),
        boxShadow: [
          BoxShadow(
            color: const Color(0x66141823),
            blurRadius: d * 0.2,
            offset: Offset(0, d * 0.09),
          ),
        ],
      ),
      child: CustomPaint(painter: _ChipFacePainter()),
    );

    // chipDrop — springy scale-in pop (also plays when a move syncs in).
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: const Duration(milliseconds: 500),
      curve: kEaseDrop,
      builder: (context, v, child) => Transform.scale(scale: v, child: child),
      child: chip,
    );
  }
}

/// Draws the dashed poker ring + center hole on top of the disc.
class _ChipFacePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final r = size.width / 2;

    final ring = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = math.max(1.4, r * 0.095)
      ..color = Colors.white.withValues(alpha: 0.55);
    final ringR = r * 0.74; // ~ inset 7px on a 42px disc
    const dashes = 16;
    const seg = 2 * math.pi / dashes;
    for (var i = 0; i < dashes; i++) {
      canvas.drawArc(
        Rect.fromCircle(center: center, radius: ringR),
        i * seg,
        seg * 0.6,
        false,
        ring,
      );
    }

    final hole = Paint()..color = Colors.white.withValues(alpha: 0.16);
    canvas.drawCircle(center, r * 0.33, hole);
  }

  @override
  bool shouldRepaint(covariant _ChipFacePainter oldDelegate) => false;
}

/// A looping ring + glow used for valid move targets (gentle pulse) and winning
/// sequence chips (stronger glow + scale).
class _PulseRing extends StatefulWidget {
  final Color color;
  final double size;
  final bool win;
  const _PulseRing({required this.color, required this.size, required this.win});

  @override
  State<_PulseRing> createState() => _PulseRingState();
}

class _PulseRingState extends State<_PulseRing>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: Duration(milliseconds: widget.win ? 800 : 1100),
  )..repeat(reverse: true);

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: AnimatedBuilder(
        animation: _c,
        builder: (context, _) {
          final t = _c.value; // 0..1
          final opacity = 0.5 + 0.5 * t;
          final scale = widget.win ? (1 + 0.06 * t) : 1.0;
          return Transform.scale(
            scale: scale,
            child: Container(
              width: widget.size,
              height: widget.size,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(kRadiusCell),
                border: Border.all(
                    color: widget.color.withValues(alpha: opacity),
                    width: widget.win ? 3 : 2),
                boxShadow: [
                  BoxShadow(
                    color: widget.color
                        .withValues(alpha: (widget.win ? 0.5 : 0.4) * opacity),
                    blurRadius: widget.win ? 16 : 12,
                    spreadRadius: widget.win ? 2 : 0,
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

/// One-shot expanding halo when a chip lands (keyed to the last-move cell).
class _Ripple extends StatelessWidget {
  final Color color;
  final double size;
  const _Ripple({required this.color, required this.size});

  @override
  Widget build(BuildContext context) {
    final d = size * 0.75;
    return IgnorePointer(
      child: TweenAnimationBuilder<double>(
        tween: Tween(begin: 0, end: 1),
        duration: const Duration(milliseconds: 600),
        curve: Curves.easeOut,
        builder: (context, t, _) {
          return Opacity(
            opacity: (1 - t) * 0.6,
            child: Transform.scale(
              scale: 0.7 + t * 1.6,
              child: Container(
                width: d,
                height: d,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(color: color, width: 3),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}
