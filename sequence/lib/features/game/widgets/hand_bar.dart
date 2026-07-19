import 'package:flutter/material.dart';

import '../../../core/theme.dart';
import '../../../rules/cards.dart';

const Map<String, String> _suitGlyph = {'S': '♠', 'H': '♥', 'D': '♦', 'C': '♣'};

/// The player's hand: a horizontal row of tappable cards. Jacks are tagged
/// (two-eyed = WILD, one-eyed = REMOVE); unplayable cards are tagged DEAD.
class HandBar extends StatelessWidget {
  final List<String> cards;
  final String? selected;
  final Set<String> deadCards; // cards whose both board cells are covered
  final bool enabled;
  final Color accent; // local player's team color (selection ring)
  final void Function(String card)? onCardTap;

  const HandBar({
    super.key,
    required this.cards,
    this.selected,
    this.deadCards = const {},
    this.enabled = true,
    this.accent = kAccentDefault,
    this.onCardTap,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 152,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
        itemCount: cards.length,
        separatorBuilder: (_, _) => const SizedBox(width: 10),
        itemBuilder: (context, i) {
          final code = cards[i];
          return _HandCard(
            code: code,
            isSelected: code == selected,
            isDead: deadCards.contains(code),
            enabled: enabled,
            accent: accent,
            onTap: (enabled && onCardTap != null) ? () => onCardTap!(code) : null,
          );
        },
      ),
    );
  }
}

class _HandCard extends StatelessWidget {
  final String code;
  final bool isSelected;
  final bool isDead;
  final bool enabled;
  final Color accent;
  final VoidCallback? onTap;

  const _HandCard({
    required this.code,
    required this.isSelected,
    required this.isDead,
    required this.enabled,
    required this.accent,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final card = PlayingCard.fromCode(code);
    final suit = code.substring(code.length - 1);
    final rank = code.substring(0, code.length - 1);
    final isRed = suit == 'H' || suit == 'D';
    final color = isRed ? kCardRed : kCardBlack;

    // Jacks are never dead, so the badge slot is shared.
    String? badge;
    Color badgeColor = kMuted;
    if (card.isTwoEyedJack) {
      badge = 'WILD';
      badgeColor = kTeamColors[1]; // green
    }
    if (card.isOneEyedJack) {
      badge = 'REMOVE';
      badgeColor = kCardRed;
    }
    if (isDead) {
      badge = 'DEAD';
      badgeColor = kCardRed;
    }

    return Opacity(
      opacity: enabled ? (isDead ? 0.6 : 1) : 0.55,
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 140),
          curve: kEaseSoft,
          width: 72,
          transform: Matrix4.translationValues(0, isSelected ? -26 : 0, 0),
          transformAlignment: Alignment.bottomCenter,
          child: Stack(
            clipBehavior: Clip.none,
            alignment: Alignment.topCenter,
            children: [
              Container(
                height: 104,
                margin: const EdgeInsets.only(top: 6),
                decoration: BoxDecoration(
                  color: kSurface,
                  borderRadius: BorderRadius.circular(kRadiusCard),
                  border: Border.all(
                    color: isSelected
                        ? accent
                        : (isDead ? kCardRed : const Color(0xFFDDE0E8)),
                    width: isSelected ? 3 : 1,
                  ),
                  boxShadow: [
                    if (isSelected)
                      BoxShadow(
                        color: accent.withValues(alpha: 0.45),
                        blurRadius: 18,
                        spreadRadius: 1,
                      )
                    else
                      const BoxShadow(
                        color: Color(0x26141823),
                        blurRadius: 18,
                        offset: Offset(0, 8),
                      ),
                  ],
                ),
                child: Stack(
                  children: [
                    Positioned(
                      top: 6,
                      left: 8,
                      child: Text(rank,
                          style: archivo(
                              weight: FontWeight.w700, color: color, size: 16)),
                    ),
                    Center(
                      child: Text(_suitGlyph[suit] ?? suit,
                          style: TextStyle(color: color, fontSize: 34)),
                    ),
                    Positioned(
                      bottom: 6,
                      right: 8,
                      child: Transform.rotate(
                        angle: 3.14159,
                        child: Text(rank,
                            style: archivo(
                                weight: FontWeight.w700, color: color, size: 16)),
                      ),
                    ),
                  ],
                ),
              ),
              if (badge != null)
                Positioned(
                  top: 0,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                    decoration: BoxDecoration(
                      color: badgeColor,
                      borderRadius: BorderRadius.circular(7),
                    ),
                    child: Text(badge,
                        style: mono(
                            size: 8, color: Colors.white, spacing: 0.5)),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
