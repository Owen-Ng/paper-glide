# Paper Glide

Offline-first iOS game. A paper plane glides through open windows in scrolling building frames. Tap anywhere to set an upward speed; gravity does the rest.

Accounts and leaderboards use Supabase anonymous auth, Postgres, and row-level security. The app reads the project URL and anon key from a gitignored xcconfig. There is no service-role key in the repo. With the placeholder config the app stays on device and the unit tests talk to a fake backend, so CI does not need a live project.

## Requirements

- **App:** Xcode 16 or newer (the checked-in project uses Xcode 16 synchronized folders). Deployment target is **iOS 16.0**. An iPhone simulator is enough. No Apple Developer team is configured; signing is automatic and unset.
- **Logic tests:** Swift 5.9 or newer. `swift test` does not need Xcode or a Mac.

SwiftData is not used. It requires iOS 17, and this target is iOS 16. The best score and the first-run coach flag are stored in `UserDefaults` (`paperGlide.bestScore`, `paperGlide.coachCompleted`). Finished runs, the claimed name, and cached boards are also in `UserDefaults`. The anonymous session token is in the Keychain.

## Run the app

Open `App/PaperGlide.xcodeproj`, choose an iPhone simulator, and run the Paper Glide scheme.

From the repo root, a simulator build with no signing team:

```sh
xcodebuild build \
  -project App/PaperGlide.xcodeproj \
  -scheme PaperGlide \
  -destination 'platform=iOS Simulator,name=iPhone 16' \
  CODE_SIGNING_ALLOWED=NO \
  CODE_SIGNING_REQUIRED=NO \
  CODE_SIGN_IDENTITY=-
```

Pick whatever iPhone simulator is installed if that name is missing. The GitHub Actions workflow discovers one automatically.

## Tests

Logic tests live in `Tests/PaperGlideCoreTests` and run on Linux or macOS:

```sh
swift test
```

The same files are compiled into the `PaperGlideTests` unit-test bundle. On a Mac:

```sh
xcodebuild test \
  -project App/PaperGlide.xcodeproj \
  -scheme PaperGlide \
  -destination 'platform=iOS Simulator,name=iPhone 16' \
  CODE_SIGNING_ALLOWED=NO \
  CODE_SIGNING_REQUIRED=NO \
  CODE_SIGN_IDENTITY=-
```

CI (`.github/workflows/ios.yml`) runs that build and `xcodebuild test` on a macOS runner for pull requests and manual `workflow_dispatch`. Screenshot UI tests attach images to the `.xcresult`. The workflow extracts those PNGs and commits them under `evidence/<commit>/`. See `evidence/README.md` for which files are a test hook and which are the real simulation.

## How a run works

The plane stays at a fixed horizontal position and points to the right. Window frames scroll left. Coordinates are y-up logical points, defined in `GameConfig`.

- A tap queues one flap for the next physics slice. The flap assigns an upward speed instead of adding to the current speed, then gravity accelerates the plane down. Upward and downward speed are capped.
- The score increases by **1** only when the plane's trailing edge (its tail, the left side) passes the obstacle's trailing edge (the right side of that frame). Each window scores once.
- Overlapping a window frame, or touching the top or bottom of the page, ends the run.
- The best score updates when a finished run beats the stored best. The end screen shows "New best!" only when the score is strictly higher. A tie, a lower score, or a first run that scores 0 does not.
- "tap to glide" is shown only until the first tap of the first run, then the flag is saved and the hint stays hidden.

## Supabase setup

Owen does not need a project checked in. Create one, then point the app at it:

1. Create a free project at [supabase.com/dashboard](https://supabase.com/dashboard). The org can have two active free projects. This game needs one.
2. In **Authentication → Sign In / Providers** (or **Authentication → Providers**), enable **Anonymous sign-ins**. Leave the default anonymous rate limit (30 new anonymous users per hour per IP) on.
3. Open **SQL Editor → New query**, paste the whole file `supabase/migrations/20261109190000_accounts_leaderboards.sql`, and run it. It creates `profiles` and `runs`, the username and score checks, and the RPCs `claim_username`, `submit_run`, `leaderboard`, and `my_username`. It does not contain keys.
4. If the `auth.users` trigger errors, delete the two trigger statements (`handle_new_user` can stay) and run the file again. `claim_username` and `submit_run` insert the profile row themselves.
5. In **Project Settings → API**, copy the **Project URL** and the **anon public** key (or the publishable key). Do not copy the **service_role** key.
6. Copy `App/Config/Secrets.example.xcconfig` to `App/Config/Secrets.xcconfig`. That file is gitignored. Set:

   ```
   SUPABASE_URL = https:/$()/YOUR_PROJECT_REF.supabase.co
   SUPABASE_ANON_KEY = your-anon-or-publishable-key
   ```

   Keep the `/$()/`. An xcconfig treats `//` as a comment, and the empty variable keeps the URL's double slash. Rebuild the Paper Glide scheme. A placeholder URL leaves the game fully playable and offline.

To remove a score or a name without shipping a build, delete the row in **Table Editor** (`public.runs` or `public.profiles`). The dashboard role bypasses RLS. Deleting the user under **Authentication → Users** removes the profile and runs through the foreign key.

Free-tier notes, checked against the current Supabase pricing page: 500 MB database per project, 50,000 monthly active users per organization, unlimited Data API requests, 5 GB egress, and 500,000 Edge Function invocations. This milestone uses Postgres RPCs instead of Edge Functions so score posts do not spend that invocation quota. Anonymous users count as monthly active users and are not deleted automatically; a quiet personal game stays far under 50,000 and 500 MB, and a script creating anonymous users is capped at 30 per hour per IP. A free project pauses after a week with no traffic. The game keeps playing from the device; boards show the offline cache until the project is restored in the dashboard. Two free projects is the org limit. Realtime is not used.

## Architecture

`PaperGlideCore` is a Swift package with no SpriteKit, SwiftUI, or UIKit. It owns the physics step, scoring, collision, window spawning, the best-score and coach storage protocol, the share message, username rules, Toronto period keys, score validation, the sync client, and the analytics queue. `swift test` builds only this package and runs the client against fake backends.

The app target under `App/PaperGlide` is SwiftUI for the start, play, and end screens, and SpriteKit for drawing. `UserDefaultsGameStorage` adapts the storage protocol. Taps, score, and the end of a run play short tones synthesized with `AVAudioEngine` (no audio files, no third-party audio).

```
Package.swift
Sources/PaperGlideCore/     simulation
Tests/PaperGlideCoreTests/  XCTest, also compiled by the iOS test bundle
App/PaperGlide.xcodeproj    iOS app project
App/PaperGlide/             SwiftUI + SpriteKit
```

The local package path from the Xcode project is the repo root.

## Screens

- **Start:** best score, Play, Leaderboard, and Report a problem. The first launch offers a name. "later" dismisses it. A sync chip shows while a finished run is still waiting. Report a problem opens a paper card on the start sky.
- **Play:** score, and the coach hint until the first tap ever.
- **End:** score, best, Retry, Share, Home, and a secondary Leaderboard. Share opens the system share sheet with text that includes the score and "Paper Glide". A new local best can offer the name once per launch if it was skipped or the device was offline.
- **Leaderboard:** Daily, Weekly, and All-time. Back returns to the screen that opened it.

Daily boards reset at 00:00 America/Toronto. Weekly boards reset Monday at 00:00 America/Toronto. A run whose Toronto day or week has already closed when it syncs counts only toward all-time.

## Dashboard

The owner dashboard is a static site in `dashboard/`. It talks to Supabase with the anon key and magic-link sign-in. Queries go through SQL functions that check `analytics_admins`.

```sh
cd dashboard
cp config.example.js config.js
# set supabaseUrl and supabaseAnonKey
python3 -m http.server 8787
```

Open `http://localhost:8787`. The default view is Last 7 days, grouped by Day. Range and grouping are stored in the URL. `config.js` is gitignored. Do not put the service-role key in it.

`node --test dashboard/test/logic.test.mjs` checks Toronto bucketing, the default range, and the on-screen copy. `scripts/test-analytics-sql.sh` applies both migrations to a throwaway local database and checks the allowlist, rollups, empty ranges, and 90-day cleanup. It does not connect to the hosted project.

## Supabase analytics setup

After the accounts migration, run `supabase/migrations/20261110160000_analytics.sql` in the SQL editor. Then:

1. Insert the viewer address: `insert into public.analytics_admins (email) values ('you@example.com');`
2. In Authentication → URL configuration, set Site URL to the dashboard origin and add that origin to the redirect allow list so the magic link can return.
3. Enable the `pg_cron` extension. The migration schedules `analytics-raw-cleanup` daily. If the extension was off, the migration prints the `cron.schedule` statement to run after enabling it.
4. Create a Cloudflare Pages project, set the production root to `dashboard/`, and add the same origin in the Supabase redirect allow list. No build command is required.

The migration does not change `profiles`, `runs`, or their functions. Raw events and crash diagnostics older than 90 days are deleted. Daily rollups and player reports stay.

A personal test week (30 accounts, 4 sessions a day, clicks stored as totals per control) is about 1.0 MB of tuples, about 0.2% of the 500 MB free-tier database before indexes. Ninety days of raw rows at that rate stays on the order of 15–30 MB.

## Out of scope

Deferred to later milestones:

- Game Center, Sign in with Apple, App Attest
- account recovery or renames
- share beyond the existing system share sheet
- friends or push
- replying to reports from the dashboard

No third-party analytics or crash SDKs are included. Visuals are drawn shapes. Nothing here is a copy of another game's name, art, or audio.
