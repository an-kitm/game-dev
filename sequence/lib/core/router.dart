import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../data/lobby_repository.dart';
import '../features/auth/nickname_provider.dart';
import '../features/auth/nickname_screen.dart';
import '../features/game/game_screen.dart';
import '../features/lobby/home_screen.dart';
import '../features/lobby/join_screen.dart';
import '../features/lobby/lobby_screen.dart';
import '../features/onboarding/tutorial_provider.dart';
import '../features/onboarding/tutorial_screen.dart';
import 'browser_history.dart';
import 'supabase.dart';

// ── Browser history ─────────────────────────────────────────────────────────
// The browser's Back button (and the phone's back gesture) walks the URL
// history, so every navigation decides what it leaves behind there:
//
//  * Home is the root.
//  * Entering a room from Home adds ONE entry, so Back from the lobby returns
//    Home — and leaving the lobby by any route takes the player out of the room
//    (see the lobby's onExit below).
//  * Everything else REPLACES the current entry: onboarding steps, the
//    lobby <-> game switches (start, rematch), invite links, redirects. So
//    Back never lands on a finished match, a room already left, or an invite
//    link that would join again.
//  * In-app "go back" moves (✕, Home, a room that's gone, a bad URL) step the
//    browser back when the entry below is still the app, so they never leave
//    a dead entry behind; otherwise they replace.
//  * Back first closes an open dialog or sheet. During a game in progress it
//    is refused (leaving would stall the game for everyone else); from the
//    results screen it leaves like Home does.

/// True while the app itself is navigating (as opposed to the browser's Back /
/// Forward or an edited URL). The onExit hooks run synchronously inside the
/// navigation call, so this tells them who asked.
var _navigatingInApp = false;

void _inApp(VoidCallback navigate) {
  _navigatingInApp = true;
  try {
    navigate();
  } finally {
    _navigatingInApp = false;
  }
}

/// Navigates without adding a browser history entry: the current entry is
/// replaced, so Back skips straight past the screen being left.
void replaceRoute(BuildContext context, String location) =>
    Router.neglect(context, () => _inApp(() => context.go(location)));

/// Enters a room's lobby, adding one history entry so Back returns to where
/// the player came from (Home). Takes the router (not a context) so it works
/// after the caller's screen has gone, as in the invite-link flow.
void enterRoom(GoRouter router, String roomId) =>
    _inApp(() => router.go('/lobby/$roomId'));

/// Set while a room screen is on its way back to Home. Stepping the browser
/// back completes asynchronously, and several triggers can fire before it
/// lands — e.g. a deleted room trips both the room and the player-list
/// checks — each of which would step back again and overshoot, past Home and
/// out of the site. Cleared when the room screen is actually left (its
/// onExit), or after a moment in case the browser never moves.
var _exitingRoom = false;
Timer? _exitingRoomReset;

void _roomExited() {
  _exitingRoom = false;
  _exitingRoomReset?.cancel();
}

/// Goes back to Home from a room screen — the lobby's ✕, the results' Home
/// button, a room that's gone. Steps the browser back when the entry below is
/// the app (Home), so no entry is left pointing at the room; otherwise
/// replaces. Repeat calls while one is under way are ignored. Leaving the room
/// itself happens in the route's onExit, which also covers the browser's own
/// Back button.
void exitRoomToHome(BuildContext context) {
  if (_exitingRoom) return;
  _exitingRoom = true;
  _exitingRoomReset?.cancel();
  _exitingRoomReset = Timer(const Duration(seconds: 2), _roomExited);
  if (hasAppEntryBelow() && browserBack()) return;
  replaceRoute(context, '/home');
}

/// Sends the player Home from a lobby / game they are no longer part of —
/// the room closed, or they reached a room they left via Back / Forward.
void leaveUnavailableRoom(BuildContext context) {
  ScaffoldMessenger.maybeOf(context)
    ?..hideCurrentSnackBar()
    ..showSnackBar(const SnackBar(
      content: Text("You're not in that room any more."),
    ));
  exitRoomToHome(context);
}

/// Leaves an onboarding screen for where the player was headed — the `next`
/// parameter (e.g. an invite link) or Home — replacing the onboarding entry
/// so Back can't return to it. The router's redirect still slots the tutorial
/// in first if it hasn't been seen.
void finishOnboarding(BuildContext context) {
  final next = _safeNext(GoRouterState.of(context).uri.queryParameters['next']);
  replaceRoute(context, next ?? '/home');
}

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
  return GoRouter(
    initialLocation: '/home',
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
    // A mistyped or stale URL lands on Home rather than an error page. This
    // runs mid-parse with a context from above the Router, so navigate once
    // parsing is done, from the navigator's context — stepping back past the
    // bad entry if the app is below it, so Back can't loop onto it.
    onException: (_, _, router) => scheduleMicrotask(() {
      final navigator = router.routerDelegate.navigatorKey.currentContext;
      if (navigator == null) return _inApp(() => router.go('/home'));
      if (hasAppEntryBelow() && browserBack()) return;
      Router.neglect(navigator, () => _inApp(() => router.go('/home')));
    }),
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
        onExit: (context, state) => !_backClosedPopup(context),
        builder: (context, state) => const HomeScreen(),
      ),
      GoRoute(
        path: '/join/:code',
        builder: (context, state) =>
            JoinScreen(code: state.pathParameters['code']!),
      ),
      GoRoute(
        path: '/lobby/:roomId',
        onExit: (context, state) =>
            _exitLobby(context, state.pathParameters['roomId']!),
        builder: (context, state) =>
            LobbyScreen(roomId: state.pathParameters['roomId']!),
      ),
      GoRoute(
        path: '/game/:roomId',
        onExit: (context, state) =>
            _exitGame(context, state.pathParameters['roomId']!),
        builder: (context, state) =>
            GameScreen(roomId: state.pathParameters['roomId']!),
      ),
    ],
  );
});

// The onExit hooks answer synchronously: an async answer would complete after
// the frame in which Router.neglect applies, turning the replace-navigations
// (lobby <-> game) into new history entries. Leaving the room is therefore
// fired off rather than awaited — joining is idempotent and Home doesn't
// depend on it having finished.

/// When the browser's Back fires with a dialog or bottom sheet open, close
/// that instead of leaving the screen — as Back does in a native app. The
/// browser has already moved its URL back, so step forward again to match.
bool _backClosedPopup(BuildContext context) {
  if (_navigatingInApp) return false;
  final navigator = Navigator.of(context);
  if (!navigator.canPop()) return false; // only the page itself is showing
  navigator.pop();
  browserForward();
  return true;
}

/// Leaving the lobby by any route — ✕, the browser's Back, an edited URL —
/// takes the player out of the room. Only moving on to the game keeps them in.
bool _exitLobby(BuildContext context, String roomId) {
  if (_backClosedPopup(context)) return false;
  _roomExited();
  final container = ProviderScope.containerOf(context, listen: false);
  final room = container.read(roomStreamProvider(roomId));
  final repo = container.read(lobbyRepositoryProvider);
  if (room.value != null) {
    if (room.value!.isLobby) unawaited(_quietly(repo.leaveRoom(roomId)));
  } else if (!room.hasError) {
    // Still loading: ask the server, and leave only if it's still a lobby —
    // never pull a player out of a game that has started.
    unawaited(_quietly(() async {
      final row = await supabase
          .from('rooms')
          .select('status')
          .eq('id', roomId)
          .maybeSingle();
      if (row?['status'] == 'lobby') await repo.leaveRoom(roomId);
    }()));
  }
  return true;
}

/// A game in progress can't be left — the others couldn't finish without this
/// player — so the browser's Back is refused while it runs. Once it's over,
/// leaving the results takes the player out of the room, as the Home button
/// does. Moving back to the lobby after a rematch passes straight through.
bool _exitGame(BuildContext context, String roomId) {
  if (_backClosedPopup(context)) return false;
  final container = ProviderScope.containerOf(context, listen: false);
  final room = container.read(roomStreamProvider(roomId)).value;
  if (room == null) {
    _roomExited();
    return true; // gone, or not ours to see
  }
  if (room.isPlaying && !_navigatingInApp) {
    // The browser has already moved its URL back; step forward again so the
    // address bar matches the game that is still on screen.
    browserForward();
    ScaffoldMessenger.maybeOf(context)
      ?..hideCurrentSnackBar()
      ..showSnackBar(const SnackBar(
        content: Text("The game is still on — you can leave once it's over."),
      ));
    return false;
  }
  if (room.isFinished) {
    unawaited(
        _quietly(container.read(lobbyRepositoryProvider).leaveRoom(roomId)));
  }
  _roomExited();
  return true;
}

/// Leaving is best-effort: a failure must not block navigation.
Future<void> _quietly(Future<void> f) => f.catchError((Object _) {});

/// Only follow in-app paths, never an absolute URL smuggled into `next`.
String? _safeNext(String? next) {
  if (next == null || !next.startsWith('/') || next.startsWith('//')) {
    return null;
  }
  return next;
}
