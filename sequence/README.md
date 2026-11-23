# Sequence

An online multiplayer game of Sequence, played in the browser. One player
creates a room and shares an invite link (or the four-letter code), and
everyone races to line up five chips in a row.

Flutter web client, Supabase backend. The server is authoritative: clients never
write game tables directly — every move goes through a `SECURITY DEFINER` RPC
that validates it, and each player's hand lives in a table only its owner can
read, so opponents' cards never reach a client.

## Layout

| Path | What lives there |
| --- | --- |
| `lib/rules/` | Pure game logic — board layout, legal moves, sequence detection. Unit-tested, no I/O. |
| `lib/data/` | Repositories wrapping the Supabase RPCs and realtime streams. |
| `lib/features/` | Screens: onboarding, lobby, game board. |
| `lib/core/` | Router (incl. invite links), theme, env, Supabase client, presence heartbeat. |
| `web/` | `index.html` (loading screen, link-preview tags), PWA manifest, icons. |
| `supabase/migrations/` | Schema, RLS, and the game RPCs, in apply order. |
| `tool/` | Branding and web-icon generators, board-layout SQL generator. |

The sequence-detection rules exist twice — in `lib/rules/sequence_detector.dart`
(unit-tested) and as a PL/pgSQL port in migration `0003`. The port has a `DO`
self-test that runs at apply time to keep the two honest.

## Running it

```sh
flutter pub get
flutter run -d chrome          # hot reload in Chrome
flutter run -d web-server      # or serve a URL to open in any browser / phone on your LAN
```

Point the app at a Supabase project either by editing the defaults in
`lib/core/env.dart` or, better, at build time:

```sh
flutter run -d chrome \
  --dart-define=SUPABASE_URL=https://<ref>.supabase.co \
  --dart-define=SUPABASE_ANON_KEY=<anon key>
```

The anon key is public by design — it is gated server-side by Row Level
Security. The `service_role` key must never appear in the app.

**Testing with several players on one machine:** every tab in the same browser
profile shares one anonymous session, so two tabs are the *same* player. Use a
private window or a second browser for each extra player.

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

## Building and deploying

```sh
flutter build web --release      # output: build/web/
```

`build/web/` is a static site — upload it to any static host (Netlify,
Vercel, Cloudflare Pages, Firebase Hosting, GitHub Pages, an S3 bucket…).
Routes use hash URLs (`https://host/#/join/ABCD`), so no server rewrite rules
are needed. Serve it over HTTPS: copying the invite link uses the browser
clipboard API, which only works in a secure context.

- **Serving from a sub-path** (e.g. GitHub Pages at `user.github.io/sequence/`):
  `flutter build web --release --base-href /sequence/`
- **Caching:** Flutter's output files keep the same names between deploys
  (`main.dart.js` has no content hash), so have the host revalidate them
  (`Cache-Control: no-cache`) rather than cache them long-term — otherwise
  players can keep running an old build after you deploy.
- **Link previews:** some chat apps need `og:image` in `web/index.html` to be
  an absolute URL — set it to `https://<your-domain>/og-image.png` once you
  have a domain.

Supabase needs no extra configuration for the web: players sign in
anonymously, so there are no auth redirect URLs to allow-list.

## Icons

`web/favicon.png`, `web/icons/*` and `web/og-image.png` are generated from the
brand art in `assets/branding/`:

```sh
python3 tool/gen_branding.py && tool/render_branding.sh   # only if the art changed
tool/gen_web_icons.sh                                      # needs ImageMagick
```
