import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../features/auth/nickname_provider.dart';
import '../features/auth/nickname_screen.dart';
import '../features/game/board_preview.dart';
import '../features/game/game_screen.dart';
import '../features/lobby/home_screen.dart';
import '../features/lobby/lobby_screen.dart';
import '../features/onboarding/tutorial_provider.dart';
import '../features/onboarding/tutorial_screen.dart';

/// Application router. Redirects to the nickname screen until a name is set.
final routerProvider = Provider<GoRouter>((ref) {
  // Bridge the nickname provider to a Listenable so go_router re-evaluates
  // its redirect whenever the nickname changes.
  final refresh = ValueNotifier<int>(0);
  ref.onDispose(refresh.dispose);
  ref.listen(nicknameProvider, (_, _) => refresh.value++);
  ref.listen(tutorialSeenProvider, (_, _) => refresh.value++);

  return GoRouter(
    initialLocation: '/home',
    refreshListenable: refresh,
    redirect: (context, state) {
      final loc = state.matchedLocation;
      if (loc == '/preview') return null; // dev bypass
      final hasName = nicknameIsSet(ref.read(nicknameProvider));
      final seenTutorial = ref.read(tutorialSeenProvider);
      // 1) Need a name first.
      if (!hasName) return loc == '/nickname' ? null : '/nickname';
      // 2) Then the one-time rules tutorial.
      if (!seenTutorial) return loc == '/tutorial' ? null : '/tutorial';
      // 3) Otherwise, keep onboarding routes out of reach.
      if (loc == '/nickname' || loc == '/tutorial') return '/home';
      return null;
    },
    routes: [
      GoRoute(
        path: '/nickname',
        builder: (context, state) => const NicknameScreen(),
      ),
      GoRoute(
        path: '/tutorial',
        builder: (context, state) => const TutorialScreen(),
      ),
      GoRoute(
        path: '/home',
        builder: (context, state) => const HomeScreen(),
      ),
      GoRoute(
        path: '/lobby/:roomId',
        builder: (context, state) =>
            LobbyScreen(roomId: state.pathParameters['roomId']!),
      ),
      GoRoute(
        path: '/game/:roomId',
        builder: (context, state) =>
            GameScreen(roomId: state.pathParameters['roomId']!),
      ),
      GoRoute(
        path: '/preview',
        builder: (context, state) => const BoardPreview(),
      ),
    ],
  );
});
