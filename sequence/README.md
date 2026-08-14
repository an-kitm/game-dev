# Sequence

An online multiplayer game of Sequence. One player creates a room, shares the
four-letter code, and everyone races to line up five chips in a row.

Flutter client, Supabase backend. The server is authoritative: clients never
write game tables directly — every move goes through a `SECURITY DEFINER` RPC
that validates it, and each player's hand lives in a table only its owner can
read, so opponents' cards never reach a client.

## Layout

| Path | What lives there |
| --- | --- |
| `lib/rules/` | Pure game logic — board layout, legal moves, sequence detection. Unit-tested, no I/O. |
| `lib/data/` | Repositories wrapping the Supabase RPCs and realtime streams. |
| `lib/features/` | Screens: onboarding, lobby, game board. |
| `lib/core/` | Router, theme, env, Supabase client, presence heartbeat. |
| `supabase/migrations/` | Schema, RLS, and the game RPCs, in apply order. |
| `tool/` | Branding generator and the board-layout SQL generator. |

The sequence-detection rules exist twice — in `lib/rules/sequence_detector.dart`
(unit-tested) and as a PL/pgSQL port in migration `0003`. The port has a `DO`
self-test that runs at apply time to keep the two honest.

## Running it

```sh
flutter pub get
flutter run
```

Point the app at a Supabase project either by editing the defaults in
`lib/core/env.dart` or, better, at build time:

```sh
flutter run \
  --dart-define=SUPABASE_URL=https://<ref>.supabase.co \
  --dart-define=SUPABASE_ANON_KEY=<anon key>
```

The anon key is public by design — it is gated server-side by Row Level
Security. The `service_role` key must never appear in the app.

## Setting up the backend

1. Create a project at [supabase.com/dashboard](https://supabase.com/dashboard).
2. Run `supabase/apply_all.sql` in the SQL editor. It is the seven migrations
   concatenated, with a destructive reset at the top, so it is safe to re-run on
   a fresh or partially-applied project.
3. Enable **anonymous sign-ins** under Authentication → Providers. The app signs
   every player in anonymously; `auth.uid()` is the player identity server-side.
4. Enable Realtime on the `rooms`, `players`, `player_hands`, and `moves` tables.

Free-tier projects pause after a week of inactivity, which takes the game
offline. Upgrade before handing the app to real players.

## Tests

```sh
flutter test      # 33 tests: rules engine + widget smoke tests
flutter analyze
```

## Building a release

Release signing reads `android/key.properties`, which is **not** in version
control. It points at a keystore outside the repo:

```properties
storePassword=...
keyPassword=...
keyAlias=sequence
storeFile=/Users/you/keystores/sequence-release.jks
```

Losing that keystore means you can never ship an update that upgrades an
existing install — back it up somewhere durable.

```sh
flutter build apk --release       # single universal APK, easiest to share
flutter build apk --release --split-per-abi   # smaller, one per architecture
flutter build appbundle --release # for Google Play
```

Without `key.properties` the release build falls back to the debug key so the
project still builds; that APK is fine for local testing and nothing else.
