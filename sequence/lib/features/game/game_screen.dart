import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/presence.dart';
import '../../core/supabase.dart';
import '../../core/theme.dart';
import '../../data/game_repository.dart';
import '../../data/lobby_repository.dart';
import '../../models/player.dart';
import '../../models/room.dart';
import '../../rules/board.dart';
import '../../rules/legal_moves.dart';
import 'widgets/board_view.dart';
import 'widgets/hand_bar.dart';
import 'widgets/turn_rail.dart';

class GameScreen extends ConsumerStatefulWidget {
  final String roomId;
  const GameScreen({super.key, required this.roomId});

  @override
  ConsumerState<GameScreen> createState() => _GameScreenState();
}

class _GameScreenState extends ConsumerState<GameScreen> {
  String? _selected;
  bool _busy = false;
  String? _deadPromptKey; // room.turnKey we've already warned about this turn

  Set<Cell> _lockedSet(Room room) =>
      room.locked.map((c) => Cell(c[0], c[1])).toSet();

  Player? _me(List<Player> players) {
    for (final p in players) {
      if (p.userId == currentUserId) return p;
    }
    return null;
  }

  Future<void> _onCellTap(Room room, int team, Set<Cell> legal, int r, int c) async {
    if (_busy) return;
    if (_selected == null) {
      _toast('Select a card first');
      return;
    }
    if (!legal.contains(Cell(r, c))) {
      _toast('Not a legal move for that card');
      return;
    }
    setState(() => _busy = true);
    try {
      await ref.read(gameRepositoryProvider).playCard(
            roomId: widget.roomId,
            card: _selected!,
            row: r,
            col: c,
          );
      if (mounted) setState(() => _selected = null);
    } catch (e) {
      _toast(_clean(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _exchangeDead(String card) async {
    setState(() => _busy = true);
    try {
      await ref
          .read(gameRepositoryProvider)
          .exchangeDeadCard(roomId: widget.roomId, card: card);
      if (mounted) setState(() => _selected = null);
    } catch (e) {
      _toast(_clean(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _toast(String m) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));
    }
  }

  /// Warn the player at the start of their turn if they hold a dead card and
  /// offer to swap it for a fresh one (the official dead-card exchange).
  Future<void> _promptDeadCard(List<String> dead) async {
    if (!mounted || _busy || dead.isEmpty) return;
    final card = dead.first;
    final more = dead.length > 1 ? ' You have ${dead.length} dead cards.' : '';
    final swap = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Dead card'),
        content: Text(
          "$card can't be played — both of its spaces on the board are already "
          "taken, so it's a dead card.$more\n\n"
          'Swap it for a new card from the deck?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Keep'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Swap'),
          ),
        ],
      ),
    );
    if (swap == true) await _exchangeDead(card);
  }

  @override
  Widget build(BuildContext context) {
    final roomAsync = ref.watch(roomStreamProvider(widget.roomId));
    final playersAsync = ref.watch(playersStreamProvider(widget.roomId));
    final handAsync = ref.watch(handStreamProvider(widget.roomId));
    final lastMove = ref.watch(lastMoveProvider(widget.roomId)).value;

    // A rematch resets the room to the lobby; send everyone back there.
    ref.listen(roomStreamProvider(widget.roomId), (_, next) {
      final r = next.value;
      if (r != null && r.isLobby) context.go('/lobby/${widget.roomId}');
    });

    final room = roomAsync.value;
    final players = playersAsync.value;
    final hand = handAsync.value ?? const <String>[];

    if (room == null || players == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    final me = _me(players);
    final myTeam = me?.team ?? 0;
    final isMyTurn = me != null && room.currentTurn == me.id && room.isPlaying;

    // "One accent per moment" — the current team's color threads through the
    // board's top bar, the turn dot and the valid-target glow.
    Player? curPlayer;
    for (final p in players) {
      if (p.id == room.currentTurn) curPlayer = p;
    }
    final accentTeam = room.isFinished
        ? (room.winnerTeam ?? myTeam)
        : (curPlayer?.team ?? myTeam);
    final accent = teamColor(accentTeam);

    // The full rotation, in turn order, for the turn rail.
    final byId = {for (final p in players) p.id: p};
    final seats = <TurnSeat>[
      for (final id in room.turnOrder)
        if (byId[id] != null)
          TurnSeat(
            name: byId[id]!.nickname,
            team: byId[id]!.team,
            isCurrent: id == room.currentTurn,
            isOnline: byId[id]!.isOnline,
          ),
    ];
    final locked = _lockedSet(room);
    final legal = (_selected != null && isMyTurn)
        ? legalCellsFor(
            card: _selected!, board: room.board, locked: locked, myTeam: myTeam)
        : <Cell>{};
    final deadCards = {
      for (final c in hand)
        if (isDeadCard(c, room.board)) c,
    };

    // Once per turn, proactively warn if the player is holding a dead card.
    if (isMyTurn &&
        deadCards.isNotEmpty &&
        room.turnKey != _deadPromptKey &&
        !_busy) {
      _deadPromptKey = room.turnKey;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && !_busy) _promptDeadCard(deadCards.toList());
      });
    }

    return HeartbeatTicker(
      roomId: widget.roomId,
      child: Scaffold(
      appBar: AppBar(title: Text('Sequence • ${room.code}')),
      body: Column(
        children: [
          _StatusBar(
            room: room,
            players: players,
            isMyTurn: isMyTurn,
            accentTeam: accentTeam,
          ),
          if (room.isPlaying && seats.length > 1) TurnRail(seats: seats),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.all(8),
              child: BoardView(
                board: room.board,
                locked: locked,
                highlighted: legal,
                lastMove: lastMove,
                accent: accent,
                winningTeam: room.isFinished ? room.winnerTeam : null,
                onCellTap: room.isPlaying
                    ? (r, c) => _onCellTap(room, myTeam, legal, r, c)
                    : null,
              ),
            ),
          ),
          if (room.isFinished)
            _WinnerBanner(room: room)
          else ...[
            if (_selected != null && isDeadCard(_selected!, room.board) && isMyTurn)
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: TextButton.icon(
                  onPressed: _busy ? null : () => _exchangeDead(_selected!),
                  icon: const Icon(Icons.autorenew),
                  label: Text('Exchange dead card $_selected'),
                ),
              ),
            HandBar(
              cards: hand,
              selected: _selected,
              deadCards: deadCards,
              enabled: isMyTurn && !_busy,
              accent: teamColor(myTeam),
              onCardTap: (card) =>
                  setState(() => _selected = _selected == card ? null : card),
            ),
          ],
        ],
      ),
      ),
    );
  }
}

String _clean(Object e) {
  final s = e.toString();
  final i = s.indexOf('message: ');
  if (i >= 0) {
    final rest = s.substring(i + 9);
    final end = rest.indexOf(',');
    return end > 0 ? rest.substring(0, end) : rest;
  }
  return s;
}

class _StatusBar extends StatelessWidget {
  final Room room;
  final List<Player> players;
  final bool isMyTurn;
  final int accentTeam;
  const _StatusBar({
    required this.room,
    required this.players,
    required this.isMyTurn,
    required this.accentTeam,
  });

  @override
  Widget build(BuildContext context) {
    final color = teamColor(accentTeam);
    String label;
    if (room.isFinished) {
      label = '${teamName(accentTeam)} team wins';
    } else if (isMyTurn) {
      label = 'Your turn';
    } else {
      Player? cur;
      for (final p in players) {
        if (p.id == room.currentTurn) cur = p;
      }
      label = cur != null ? "${cur.nickname}'s turn" : 'Waiting…';
    }
    final toWin = room.numTeams == 2 ? 2 : 1;
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.fromLTRB(8, 8, 8, 0),
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
      decoration: BoxDecoration(
        color: teamSoft(accentTeam),
        borderRadius: BorderRadius.circular(kRadiusControl),
      ),
      child: Row(
        children: [
          Container(
            width: 12,
            height: 12,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 10),
          Text(label, style: archivo(weight: FontWeight.w800, color: kInk, size: 16)),
          const Spacer(),
          Text('$toWin TO WIN', style: eyebrow(color: kMuted)),
        ],
      ),
    );
  }
}

class _WinnerBanner extends ConsumerWidget {
  final Room room;
  const _WinnerBanner({required this.room});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = room.winnerTeam ?? 0;
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.all(8),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: teamSoft(t),
        borderRadius: BorderRadius.circular(kRadiusPanel),
        border: Border.all(color: teamColor(t).withValues(alpha: 0.4)),
      ),
      child: Column(
        children: [
          Text('${teamName(t)} team wins! 🎉',
              style: archivo(weight: FontWeight.w800, color: teamColor(t), size: 22)),
          const SizedBox(height: 14),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // Anyone can rematch — it returns everyone still in the room to
              // the same lobby (same code) to play again.
              FilledButton.icon(
                style: FilledButton.styleFrom(backgroundColor: teamColor(t)),
                onPressed: () async {
                  try {
                    await ref.read(gameRepositoryProvider).rematch(room.id);
                  } catch (e) {
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text(_clean(e))));
                    }
                  }
                },
                icon: const Icon(Icons.refresh),
                label: const Text('Play Again'),
              ),
              const SizedBox(width: 12),
              OutlinedButton(
                onPressed: () async {
                  await ref.read(lobbyRepositoryProvider).leaveRoom(room.id);
                  if (context.mounted) context.go('/home');
                },
                child: const Text('Home'),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            'Play Again keeps the same room — everyone is brought back to the '
            'lobby. Home leaves the room.',
            textAlign: TextAlign.center,
            style: const TextStyle(color: kBody, fontSize: 12, height: 1.4),
          ),
        ],
      ),
    );
  }
}
