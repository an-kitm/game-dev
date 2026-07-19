import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../auth/nickname_provider.dart' show sharedPrefsProvider;

/// Whether the one-time rules tutorial has been seen. Persisted locally, so it
/// shows only once after the first install (and after the nickname is set).
class TutorialSeenNotifier extends Notifier<bool> {
  static const _key = 'tutorial_seen_v1';

  @override
  bool build() => ref.read(sharedPrefsProvider).getBool(_key) ?? false;

  Future<void> markSeen() async {
    await ref.read(sharedPrefsProvider).setBool(_key, true);
    state = true;
  }
}

final tutorialSeenProvider =
    NotifierProvider<TutorialSeenNotifier, bool>(TutorialSeenNotifier.new);
