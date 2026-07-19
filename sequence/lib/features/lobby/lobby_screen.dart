import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/presence.dart';
import '../../core/supabase.dart';
import '../../core/theme.dart';
import '../../data/lobby_repository.dart';
import '../../models/player.dart';
import '../../models/room.dart';
import '../../rules/game_config.dart';

class LobbyScreen extends ConsumerWidget {
  final String roomId;
  const LobbyScreen({super.key, required this.roomId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final roomAsync = ref.watch(roomStreamProvider(roomId));
    final playersAsync = ref.watch(playersStreamProvider(roomId));

    // When the host starts the game, everyone navigates to the board.
    ref.listen(roomStreamProvider(roomId), (_, next) {
      final room = next.value;
      if (room != null && room.isPlaying) {
        context.go('/game/$roomId');
      }
    });

    return HeartbeatTicker(
      roomId: roomId,
      child: Scaffold(
      appBar: AppBar(
        title: const Text('Lobby'),
        leading: IconButton(
          icon: const Icon(Icons.close),
          onPressed: () async {
            await ref.read(lobbyRepositoryProvider).leaveRoom(roomId);
            if (context.mounted) context.go('/home');
          },
        ),
      ),
      body: roomAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Room closed: $e')),
        data: (room) => playersAsync.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => Center(child: Text('$e')),
          data: (players) => _LobbyBody(room: room, players: players),
        ),
      ),
      ),
    );
  }
}

class _LobbyBody extends ConsumerStatefulWidget {
  final Room room;
  final List<Player> players;
  const _LobbyBody({required this.room, required this.players});

  @override
  ConsumerState<_LobbyBody> createState() => _LobbyBodyState();
}

class _LobbyBodyState extends ConsumerState<_LobbyBody> {
  bool _starting = false;

  Future<void> _start() async {
    setState(() => _starting = true);
    try {
      await supabase.rpc('start_game', params: {'p_room': widget.room.id});
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Cannot start: $e')));
      }
    } finally {
      if (mounted) setState(() => _starting = false);
    }
  }

  Future<void> _setTeam(int team) async {
    try {
      await ref.read(lobbyRepositoryProvider).setTeam(widget.room.id, team);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Cannot switch team: $e')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final room = widget.room;
    final players = widget.players;
    final isHost = room.hostId == currentUserId;
    Player? me;
    for (final p in players) {
      if (p.userId == currentUserId) me = p;
    }
    final canStart = teamsReady(players.map((p) => p.team), room.numTeams);
    final teamCounts = [
      for (var t = 0; t < room.numTeams; t++)
        players.where((p) => p.team == t).length,
    ];

    return Column(
      children: [
        const SizedBox(height: 18),
        Text('ROOM CODE', style: eyebrow()),
        const SizedBox(height: 6),
        InkWell(
          onTap: () {
            Clipboard.setData(ClipboardData(text: room.code));
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Code copied')),
            );
          },
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(room.code,
                  style: mono(size: 40, weight: FontWeight.w700, color: kInk, spacing: 8)),
              const SizedBox(width: 8),
              const Icon(Icons.copy, size: 20, color: kMuted),
            ],
          ),
        ),
        const SizedBox(height: 8),
        Text('${players.length} player(s) • ${room.numTeams} teams',
            style: Theme.of(context).textTheme.bodyMedium),
        if (me != null && room.isLobby) ...[
          const SizedBox(height: 14),
          Text('Your team', style: Theme.of(context).textTheme.labelLarge),
          const SizedBox(height: 6),
          _TeamPicker(
            numTeams: room.numTeams,
            selected: me.team,
            onSelect: _setTeam,
          ),
        ],
        const Divider(height: 32),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            children: [
              for (var t = 0; t < room.numTeams; t++) ...[
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Text(
                    '${teamName(t)} Team · ${teamCounts[t]}',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          color: teamColor(t),
                          fontWeight: FontWeight.bold,
                        ),
                  ),
                ),
                ...players.where((p) => p.team == t).map(
                      (p) => ListTile(
                        leading: SizedBox(
                          width: 40,
                          height: 40,
                          child: Stack(
                            children: [
                              TeamDot(team: t, size: 40),
                              Positioned(
                                right: 0,
                                bottom: 0,
                                child: Container(
                                  width: 13,
                                  height: 13,
                                  decoration: BoxDecoration(
                                    color: p.isOnline
                                        ? const Color(0xFF16A36B)
                                        : kLabel,
                                    shape: BoxShape.circle,
                                    border: Border.all(color: kSurface, width: 2),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                        title: Text(p.nickname,
                            style: archivo(weight: FontWeight.w600, color: kInk)),
                        trailing: p.userId == room.hostId
                            ? Chip(
                                label: Text('Host',
                                    style: mono(size: 10, color: kBody, spacing: 1)),
                                backgroundColor: kPanelMuted,
                                side: const BorderSide(color: kLine),
                              )
                            : null,
                      ),
                    ),
              ],
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.all(16),
          child: isHost
              ? FilledButton(
                  onPressed: (canStart && !_starting) ? _start : null,
                  child: _starting
                      ? const SizedBox(
                          height: 20,
                          width: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : Text(canStart
                          ? 'Start Game'
                          : 'Teams must be equal to start'),
                )
              : const Text('Waiting for host to start…',
                  textAlign: TextAlign.center),
        ),
      ],
    );
  }
}

/// Lets the local player pick their own team. Each player chooses freely;
/// the host can only start once the teams are equal (enforced server-side).
class _TeamPicker extends StatelessWidget {
  final int numTeams;
  final int selected;
  final ValueChanged<int> onSelect;
  const _TeamPicker({
    required this.numTeams,
    required this.selected,
    required this.onSelect,
  });

  @override
  Widget build(BuildContext context) {
    return SegmentedButton<int>(
      segments: [
        for (var t = 0; t < numTeams; t++)
          ButtonSegment<int>(
            value: t,
            label: Text(teamName(t)),
            icon: Icon(Icons.circle, size: 14, color: teamColor(t)),
          ),
      ],
      selected: {selected},
      showSelectedIcon: false,
      onSelectionChanged: (s) => onSelect(s.first),
    );
  }
}
