import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/router.dart' show enterRoom, replaceRoute;
import '../../core/theme.dart';
import '../../data/lobby_repository.dart';
import '../auth/nickname_provider.dart';
import 'home_screen.dart' show friendlyLobbyError;

/// Landing page for an invite link (`/#/join/ABCD`): joins the room and moves
/// on to its lobby. Joining is idempotent server-side, so reopening the link
/// (or refreshing this page) is harmless.
class JoinScreen extends ConsumerStatefulWidget {
  final String code;
  const JoinScreen({super.key, required this.code});

  @override
  ConsumerState<JoinScreen> createState() => _JoinScreenState();
}

class _JoinScreenState extends ConsumerState<JoinScreen> {
  String? _error;

  String get _code => widget.code.trim().toUpperCase();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _join());
  }

  Future<void> _join() async {
    setState(() => _error = null);
    try {
      final roomId = await ref.read(lobbyRepositoryProvider).joinRoom(
            code: _code,
            nickname: ref.read(nicknameProvider) ?? '',
          );
      if (!mounted) return;
      // Swap this invite-link entry for Home, then enter the room from there:
      // Back from the lobby then returns Home (leaving the room) instead of
      // reopening the link, which would join all over again.
      final router = GoRouter.of(context);
      replaceRoute(context, '/home');
      await WidgetsBinding.instance.endOfFrame;
      enterRoom(router, roomId);
    } catch (e) {
      if (mounted) setState(() => _error = friendlyLobbyError(e));
    }
  }

  @override
  Widget build(BuildContext context) {
    final error = _error;
    return Scaffold(
      body: CanvasBackground(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Wordmark(eyebrow: 'Joining room $_code'),
                  const SizedBox(height: 44),
                  if (error == null)
                    const Center(child: CircularProgressIndicator())
                  else ...[
                    Text(error,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                            color: kBody, fontSize: 15, height: 1.5)),
                    const SizedBox(height: 24),
                    FilledButton(
                      onPressed: _join,
                      child: const Text('Try again'),
                    ),
                    const SizedBox(height: 14),
                    OutlinedButton(
                      onPressed: () => replaceRoute(context, '/home'),
                      child: const Text('Go to Home'),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
