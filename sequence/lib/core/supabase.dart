import 'package:supabase_flutter/supabase_flutter.dart';

/// Shorthand accessor for the initialized Supabase client.
///
/// Safe to use only after [Supabase.initialize] has completed (see `main()`).
SupabaseClient get supabase => Supabase.instance.client;

/// The current anonymous auth user id (`auth.uid()` server-side), or null if
/// no session exists yet.
String? get currentUserId => supabase.auth.currentUser?.id;

/// Ensures an anonymous session exists, signing in lazily if needed. Called
/// before any RPC so that enabling anonymous sign-ins takes effect without an
/// app restart (the initial sign-in at launch may have failed).
Future<void> ensureSignedIn() async {
  if (supabase.auth.currentSession == null) {
    await supabase.auth.signInAnonymously();
  }
}
