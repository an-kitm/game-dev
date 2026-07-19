import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Provides the [SharedPreferences] instance. Overridden in `main()` once it
/// has been loaded, so it is synchronously available everywhere else.
final sharedPrefsProvider = Provider<SharedPreferences>(
  (ref) => throw UnimplementedError('sharedPrefsProvider must be overridden'),
);

/// The player's chosen display name, persisted locally. Null/empty until set.
class NicknameNotifier extends Notifier<String?> {
  static const _key = 'nickname';

  @override
  String? build() => ref.read(sharedPrefsProvider).getString(_key);

  Future<void> set(String name) async {
    final trimmed = name.trim();
    await ref.read(sharedPrefsProvider).setString(_key, trimmed);
    state = trimmed;
  }
}

final nicknameProvider =
    NotifierProvider<NicknameNotifier, String?>(NicknameNotifier.new);

bool nicknameIsSet(String? n) => n != null && n.trim().isNotEmpty;
