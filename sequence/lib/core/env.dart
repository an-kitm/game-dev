/// Environment configuration.
///
/// The Supabase anon key is a *public* key — it is designed to be embedded in
/// client apps and is gated server-side by Row Level Security. The secret
/// `service_role` key must never appear in the app.
///
/// Values can be overridden at build/run time with:
///   flutter run --dart-define=SUPABASE_URL=... --dart-define=SUPABASE_ANON_KEY=...
class Env {
  const Env._();

  static const String supabaseUrl = String.fromEnvironment(
    'SUPABASE_URL',
    defaultValue: 'https://rbaomyccsohyhypewosx.supabase.co',
  );

  static const String supabaseAnonKey = String.fromEnvironment(
    'SUPABASE_ANON_KEY',
    defaultValue:
        'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InJiYW9teWNjc29oeWh5cGV3b3N4Iiwicm9sZSI6ImFub24iLCJpYXQiOjE3ODI0NTMzOTksImV4cCI6MjA5ODAyOTM5OX0.xKPVpTzp-LC7vQSCgRk9SRm9j-iW1j3YStLw5lTdbM4',
  );
}
