import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme.dart';
import '../../data/lobby_repository.dart';
import '../auth/nickname_provider.dart';

/// Home: create a new room or join an existing one by code.
class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  bool _busy = false;

  Future<void> _run(Future<String> Function() action) async {
    setState(() => _busy = true);
    try {
      final roomId = await action();
      if (mounted) context.go('/lobby/$roomId');
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(_friendlyError(e))),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _createRoom() async {
    final teams = await showDialog<int>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: const Text('How many teams?'),
        children: [
          SimpleDialogOption(
            onPressed: () => Navigator.pop(ctx, 2),
            child: const Text('2 teams (need 2 sequences to win)'),
          ),
          SimpleDialogOption(
            onPressed: () => Navigator.pop(ctx, 3),
            child: const Text('3 teams (need 1 sequence to win)'),
          ),
        ],
      ),
    );
    if (teams == null) return;
    final nickname = ref.read(nicknameProvider) ?? '';
    await _run(() => ref
        .read(lobbyRepositoryProvider)
        .createRoom(nickname: nickname, numTeams: teams));
  }

  Future<void> _joinRoom() async {
    final controller = TextEditingController();
    final code = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Enter room code'),
        content: TextField(
          controller: controller,
          autofocus: true,
          textCapitalization: TextCapitalization.characters,
          maxLength: 4,
          decoration: const InputDecoration(hintText: 'ABCD'),
          onSubmitted: (v) => Navigator.pop(ctx, v),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, controller.text),
            child: const Text('Join'),
          ),
        ],
      ),
    );
    final trimmed = code?.trim().toUpperCase() ?? '';
    if (trimmed.isEmpty) return;
    final nickname = ref.read(nicknameProvider) ?? '';
    await _run(() => ref
        .read(lobbyRepositoryProvider)
        .joinRoom(code: trimmed, nickname: nickname));
  }

  @override
  Widget build(BuildContext context) {
    final nickname = ref.watch(nicknameProvider) ?? '';
    return Scaffold(
      body: CanvasBackground(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: _busy
                  ? const Center(child: CircularProgressIndicator())
                  : Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Wordmark(
                            eyebrow: nickname.isEmpty ? 'Welcome' : 'Hi, $nickname'),
                        const SizedBox(height: 44),
                        FilledButton.icon(
                          onPressed: _createRoom,
                          icon: const Icon(Icons.add),
                          label: const Text('Create Room'),
                        ),
                        const SizedBox(height: 14),
                        OutlinedButton.icon(
                          onPressed: _joinRoom,
                          icon: const Icon(Icons.login),
                          label: const Text('Join Room'),
                        ),
                      ],
                    ),
            ),
          ),
        ),
      ),
    );
  }
}

String _friendlyError(Object e) {
  final s = e.toString();
  if (s.contains('not authenticated')) {
    return 'Not signed in yet — enable anonymous sign-ins in Supabase.';
  }
  if (s.contains('room not found')) return 'Room not found or already started.';
  if (s.contains('full')) return 'That room is full.';
  return 'Something went wrong: $s';
}
