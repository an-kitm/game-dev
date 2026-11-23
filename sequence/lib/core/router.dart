import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../features/auth/nickname_provider.dart';
import '../features/auth/nickname_screen.dart';
import '../features/game/game_screen.dart';
import '../features/lobby/home_screen.dart';
import '../features/lobby/join_screen.dart';
import '../features/lobby/lobby_screen.dart';
import '../features/onboarding/tutorial_provider.dart';
import '../features/onboarding/tutorial_screen.dart';

/// The shareable link that drops a friend straight into a room's lobby.
///
/// The app uses Flutter web's default hash URLs (`/#/join/ABCD`), which work on
/// any static host without server rewrite rules.
String inviteLink(String code) {
  final here = Uri.base; // the page's own URL, including any --base-href path
  return Uri(
    scheme: here.scheme,
    host: here.host,
    port: here.hasPort ? here.port : null,
    path: here.path,
    fragment: '/join/$code',
  ).toString();
}

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
      final onboarding = loc == '/nickname' || loc == '/tutorial';

      // A first-time visitor arriving on an invite link (or any deep link) is
      // sent through onboarding first; carry the destination along as `next`
      // so they land on it afterwards instead of on Home.
      final next = onboarding
          ? _safeNext(state.uri.queryParameters['next'])
          : state.uri.toString();
      String onboard(String path) => (next == null || next == '/home')
          ? path
          : Uri(path: path, queryParameters: {'next': next}).toString();

      final hasName = nicknameIsSet(ref.read(nicknameProvider));
      final seenTutorial = ref.read(tutorialSeenProvider);
      // 1) Need a name first.
      if (!hasName) return loc == '/nickname' ? null : onboard('/nickname');
      // 2) Then the one-time rules tutorial.
      if (!seenTutorial) return loc == '/tutorial' ? null : onboard('/tutorial');
      // 3) Otherwise, keep onboarding routes out of reach.
      if (onboarding) return next ?? '/home';
      return null;
    },
    // A mistyped or stale URL lands on Home rather than an error page.
    onException: (context, state, router) => router.go('/home'),
    routes: [
      GoRoute(path: '/', redirect: (_, _) => '/home'),
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
        path: '/join/:code',
        builder: (context, state) =>
            JoinScreen(code: state.pathParameters['code']!),
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
    ],
  );
});

/// Only follow in-app paths, never an absolute URL smuggled into `next`.
String? _safeNext(String? next) {
  if (next == null || !next.startsWith('/') || next.startsWith('//')) {
    return null;
  }
  return next;
}
