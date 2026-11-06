# Paper Glide

Offline iOS prototype. A paper plane glides through open windows in scrolling building frames. Tap anywhere for an upward push; gravity does the rest.

This milestone is local only. There is no account, network client, or backend.

## Requirements

- **App:** Xcode 16 or newer (the checked-in project uses Xcode 16 synchronized folders). Deployment target is **iOS 16.0**. An iPhone simulator is enough. No Apple Developer team is configured; signing is automatic and unset.
- **Logic tests:** Swift 5.9 or newer. `swift test` does not need Xcode or a Mac.

SwiftData is not used. It requires iOS 17, and this target is iOS 16. The best score and the first-run coach flag are stored in `UserDefaults` (`paperGlide.bestScore`, `paperGlide.coachCompleted`).

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

- A tap queues one upward impulse for the next physics slice. Gravity then accelerates the plane down. Upward and downward speed are capped.
- The score increases by **1** only when the plane's trailing edge (its tail, the left side) passes the obstacle's trailing edge (the right side of that frame). Each window scores once.
- Overlapping a window frame, or touching the top or bottom of the page, ends the run.
- The best score updates when a finished run beats the stored best. The end screen shows "New best!" only when the score is strictly higher. A tie, a lower score, or a first run that scores 0 does not.
- "tap to glide" is shown only until the first tap of the first run, then the flag is saved and the hint stays hidden.

## Architecture

`PaperGlideCore` is a Swift package with no SpriteKit, SwiftUI, or UIKit. It owns the physics step, scoring, collision, window spawning, the best-score and coach storage protocol, and the share message. `swift test` builds only this package.

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

- **Start:** best score, Play, and disabled Leaderboard and Report buttons labelled coming soon.
- **Play:** score, and the coach hint until the first tap ever.
- **End:** score, best, Retry, Share, Home. Share opens the system share sheet with text that includes the score and "Paper Glide".

## Out of scope

Deferred to later milestones:

- backend and any network calls
- leaderboards
- usernames
- telemetry
- the report form
- account linking

No third-party SDKs are included. Visuals are drawn shapes. Nothing here is a copy of another game's name, art, or audio.
