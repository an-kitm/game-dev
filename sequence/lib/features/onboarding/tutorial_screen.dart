import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme.dart';
import 'tutorial_provider.dart';

/// A one-time, swipeable rules tutorial shown after the first install. Reaches
/// the end → marks itself seen and the router moves on to Home.
class TutorialScreen extends ConsumerStatefulWidget {
  const TutorialScreen({super.key});

  @override
  ConsumerState<TutorialScreen> createState() => _TutorialScreenState();
}

class _TutorialScreenState extends ConsumerState<TutorialScreen> {
  final _pager = PageController();
  int _page = 0;

  static const _slides = <_Slide>[
    _Slide(
      title: 'Make a sequence',
      body:
          "Get five of your team's chips in a row — across, down or diagonally. "
          'Two teams race to two sequences; three teams need just one.',
      art: _ChipRowArt(),
    ),
    _Slide(
      title: 'Play a card',
      body:
          'Each card matches two spaces on the board. On your turn, play a card '
          'to drop your chip on a matching open space — then draw a new one.',
      art: _PlayArt(),
    ),
    _Slide(
      title: 'The Jacks are wild',
      body:
          'Two-eyed Jacks (J♦, J♣) are WILD — place a chip on any open space. '
          "One-eyed Jacks (J♠, J♥) REMOVE one of an opponent's chips.",
      art: _JackArt(),
    ),
    _Slide(
      title: 'Free corners',
      body:
          'The four corners are FREE — they count as a chip for every team, so '
          'you can build a sequence right through them.',
      art: _CornerArt(),
    ),
    _Slide(
      title: 'Dead cards & locks',
      body:
          "If both spaces for a card are already taken, it's a dead card — swap "
          'it for a new one. Chips in a finished sequence are locked and safe '
          'from one-eyed Jacks.',
      art: _DeadArt(),
    ),
  ];

  @override
  void dispose() {
    _pager.dispose();
    super.dispose();
  }

  bool get _isLast => _page == _slides.length - 1;

  Future<void> _finish() async {
    await ref.read(tutorialSeenProvider.notifier).markSeen();
    if (mounted) context.go('/home');
  }

  void _next() {
    if (_isLast) {
      _finish();
    } else {
      _pager.nextPage(
          duration: const Duration(milliseconds: 320), curve: kEaseSoft);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: CanvasBackground(
        child: SafeArea(
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 12, 12, 0),
                child: Row(
                  children: [
                    Text('HOW TO PLAY · ${_page + 1}/${_slides.length}',
                        style: eyebrow()),
                    const Spacer(),
                    TextButton(
                      onPressed: _finish,
                      child: const Text('Skip'),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: PageView.builder(
                  controller: _pager,
                  itemCount: _slides.length,
                  onPageChanged: (i) => setState(() => _page = i),
                  itemBuilder: (context, i) => _SlideView(slide: _slides[i]),
                ),
              ),
              _Dots(count: _slides.length, active: _page),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 18, 20, 24),
                child: SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    onPressed: _next,
                    child: Text(_isLast ? 'Get started' : 'Next'),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Slide {
  final String title;
  final String body;
  final Widget art;
  const _Slide({required this.title, required this.body, required this.art});
}

class _SlideView extends StatelessWidget {
  final _Slide slide;
  const _SlideView({required this.slide});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 28),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            height: 200,
            width: double.infinity,
            decoration: BoxDecoration(
              color: kSurface,
              borderRadius: BorderRadius.circular(kRadiusPanel),
              border: Border.all(color: kLine),
              boxShadow: kPanelShadow,
            ),
            alignment: Alignment.center,
            child: slide.art,
          ),
          const SizedBox(height: 32),
          Text(slide.title,
              textAlign: TextAlign.center,
              style: archivo(weight: FontWeight.w800, color: kInk, size: 26)),
          const SizedBox(height: 12),
          Text(slide.body,
              textAlign: TextAlign.center,
              style: const TextStyle(color: kBody, fontSize: 15.5, height: 1.6)),
        ],
      ),
    );
  }
}

class _Dots extends StatelessWidget {
  final int count;
  final int active;
  const _Dots({required this.count, required this.active});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        for (var i = 0; i < count; i++)
          AnimatedContainer(
            duration: const Duration(milliseconds: 240),
            margin: const EdgeInsets.symmetric(horizontal: 4),
            width: i == active ? 22 : 8,
            height: 8,
            decoration: BoxDecoration(
              color: i == active ? kInk : kLine,
              borderRadius: BorderRadius.circular(4),
            ),
          ),
      ],
    );
  }
}

// ── Illustrations ────────────────────────────────────────────────────────────

/// A poker chip disc (reused across slides).
class _Chip extends StatelessWidget {
  final int team;
  final double size;
  const _Chip({required this.team, this.size = 40});

  @override
  Widget build(BuildContext context) {
    final base = teamColor(team);
    return Container(
      width: size,
      height: size,
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
              color: const Color(0x55141823),
              blurRadius: size * 0.18,
              offset: Offset(0, size * 0.08)),
        ],
      ),
      child: Padding(
        padding: EdgeInsets.all(size * 0.17),
        child: DecoratedBox(
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(
                color: Colors.white.withValues(alpha: 0.55), width: size * 0.05),
          ),
        ),
      ),
    );
  }
}

class _MiniCard extends StatelessWidget {
  final String code;
  final String? badge;
  final Color badgeColor;
  const _MiniCard(this.code, {this.badge, this.badgeColor = kMuted});

  @override
  Widget build(BuildContext context) {
    final suit = code.substring(code.length - 1);
    final rank = code.substring(0, code.length - 1);
    final isRed = suit == 'H' || suit == 'D';
    final color = isRed ? kCardRed : kCardBlack;
    const glyph = {'S': '♠', 'H': '♥', 'D': '♦', 'C': '♣'};
    return Stack(
      clipBehavior: Clip.none,
      alignment: Alignment.topCenter,
      children: [
        Container(
          width: 60,
          height: 86,
          margin: const EdgeInsets.only(top: 6),
          decoration: BoxDecoration(
            color: kSurface,
            borderRadius: BorderRadius.circular(kRadiusCard),
            border: Border.all(color: const Color(0xFFDDE0E8)),
            boxShadow: kCardShadow,
          ),
          child: Stack(
            children: [
              Positioned(
                top: 5,
                left: 7,
                child: Text(rank,
                    style: archivo(weight: FontWeight.w700, color: color, size: 14)),
              ),
              Center(
                child: Text(glyph[suit] ?? suit,
                    style: TextStyle(color: color, fontSize: 30)),
              ),
            ],
          ),
        ),
        if (badge != null)
          Positioned(
            top: 0,
            child: _Pill(badge!, badgeColor),
          ),
      ],
    );
  }
}

class _Pill extends StatelessWidget {
  final String text;
  final Color color;
  const _Pill(this.text, this.color);

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration:
          BoxDecoration(color: color, borderRadius: BorderRadius.circular(7)),
      child: Text(text, style: mono(size: 8, color: Colors.white, spacing: 0.5)),
    );
  }
}

class _ChipRowArt extends StatelessWidget {
  const _ChipRowArt();
  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        for (var i = 0; i < 5; i++)
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 4),
            child: _Chip(team: 0, size: 40),
          ),
      ],
    );
  }
}

class _PlayArt extends StatelessWidget {
  const _PlayArt();
  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: const [
        _MiniCard('7H'),
        Padding(
          padding: EdgeInsets.symmetric(horizontal: 16),
          child: Icon(Icons.arrow_forward_rounded, color: kLabel, size: 28),
        ),
        _Chip(team: 1, size: 48),
      ],
    );
  }
}

class _JackArt extends StatelessWidget {
  const _JackArt();
  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: const [
        Padding(
          padding: EdgeInsets.symmetric(horizontal: 10),
          child: _MiniCard('JD', badge: 'WILD', badgeColor: Color(0xFF16A36B)),
        ),
        Padding(
          padding: EdgeInsets.symmetric(horizontal: 10),
          child: _MiniCard('JS', badge: 'REMOVE', badgeColor: kCardRed),
        ),
      ],
    );
  }
}

class _CornerArt extends StatelessWidget {
  const _CornerArt();
  @override
  Widget build(BuildContext context) {
    return Container(
      width: 92,
      height: 92,
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [kCornerTop, kCornerBottom],
        ),
        borderRadius: BorderRadius.circular(kRadiusPanel),
        border: Border.all(color: kCellBorder),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.star_rounded, color: kLabel, size: 34),
          Text('FREE', style: mono(size: 10, color: kLabel, spacing: 2)),
        ],
      ),
    );
  }
}

class _DeadArt extends StatelessWidget {
  const _DeadArt();
  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        const Opacity(
          opacity: 0.6,
          child: _MiniCard('QC', badge: 'DEAD', badgeColor: kCardRed),
        ),
        const SizedBox(width: 22),
        // A locked chip — team border ring around the cell.
        Container(
          width: 64,
          height: 64,
          decoration: BoxDecoration(
            color: kSurface,
            borderRadius: BorderRadius.circular(kRadiusCell),
            border: Border.all(color: teamColor(0), width: 2),
          ),
          alignment: Alignment.center,
          child: const _Chip(team: 0, size: 44),
        ),
      ],
    );
  }
}
