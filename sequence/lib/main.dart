import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'core/env.dart';
import 'core/router.dart';
import 'core/theme.dart';
import 'features/auth/nickname_provider.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Portrait-only: never rotate to landscape, even if the device is turned.
  await SystemChrome.setPreferredOrientations(const [
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
  ]);

  await Supabase.initialize(
    url: Env.supabaseUrl,
    // The legacy anon JWT still works; migrate to publishableKey later.
    // ignore: deprecated_member_use
    anonKey: Env.supabaseAnonKey,
  );

  // Ensure we always have an anonymous session (this is auth.uid() server-side).
  // Non-fatal: if anonymous sign-ins aren't enabled yet, the app still launches
  // (the nickname screen works offline); lobby actions re-check the session.
  final auth = Supabase.instance.client.auth;
  if (auth.currentSession == null) {
    try {
      await auth.signInAnonymously();
    } catch (e) {
      debugPrint('Anonymous sign-in failed (enable it in Supabase Auth): $e');
    }
  }

  final prefs = await SharedPreferences.getInstance();

  runApp(
    ProviderScope(
      overrides: [sharedPrefsProvider.overrideWithValue(prefs)],
      child: const SequenceApp(),
    ),
  );
}

class SequenceApp extends ConsumerWidget {
  const SequenceApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final router = ref.watch(routerProvider);
    return MaterialApp.router(
      title: 'Sequence',
      debugShowCheckedModeBanner: false,
      theme: buildAppTheme(),
      routerConfig: router,
    );
  }
}
