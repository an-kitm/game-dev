import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/game_repository.dart';

/// Pings the server presence heartbeat for [roomId] every few seconds while
/// mounted (and immediately on app resume), keeping the player's `last_seen`
/// fresh so others can see they are online. Renders [child] unchanged.
class HeartbeatTicker extends ConsumerStatefulWidget {
  final String roomId;
  final Widget child;

  const HeartbeatTicker({
    super.key,
    required this.roomId,
    required this.child,
  });

  @override
  ConsumerState<HeartbeatTicker> createState() => _HeartbeatTickerState();
}

class _HeartbeatTickerState extends ConsumerState<HeartbeatTicker>
    with WidgetsBindingObserver {
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _ping();
    _timer = Timer.periodic(const Duration(seconds: 8), (_) => _ping());
  }

  Future<void> _ping() async {
    try {
      await ref.read(gameRepositoryProvider).heartbeat(widget.roomId);
    } catch (_) {
      // Presence is best-effort; ignore transient failures.
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _ping();
  }

  @override
  void dispose() {
    _timer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
