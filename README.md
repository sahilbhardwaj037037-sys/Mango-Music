# LocalMusic

LocalMusic is a native macOS music application built with Swift and SwiftUI. It aims for a simple, lightweight interface inspired by native macOS music libraries, with a sidebar, song lists and playback controls.

**Current status: Checkpoint 1. All songs are fictional mock data. The app does not stream or play real music, search YouTube, or run external audio tools.**

## Requirements

- macOS 14 or later. Current development and launch checks were performed on Apple Silicon with macOS 26.
- Full Xcode with the macOS SDK and Swift 6 support. The current project has been built with Xcode 27.1 and Swift 6.4.
- Git to clone the repository.
- No third-party packages, API keys, music accounts, yt-dlp or mpv are required for Checkpoint 1.

## Open and run

1. Clone this repository and open `LocalMusic.xcodeproj` in Xcode.
2. Select the shared **LocalMusic** scheme and **My Mac** destination.
3. Press **Command+R** to build and launch.

Xcode generates the Info.plist. If Xcode requests a signing team, select your own local team; do not commit personal signing settings. Standalone distribution, notarization and release packaging are outside the current scope.

For an unsigned local build from the repository root:

```sh
xcodebuild -project LocalMusic.xcodeproj -scheme LocalMusic \
  -destination 'platform=macOS' -derivedDataPath .build/XcodeDerivedData \
  CODE_SIGNING_ALLOWED=NO build
```

Check the active developer tools with `xcode-select -p` and `xcodebuild -version`. Full Xcode is required for the application target. If Command Line Tools are selected, use a per-command `DEVELOPER_DIR` pointing to your Xcode installation rather than changing system settings.

## Checkpoint 1 features

- Native, resizable window with an initial size of approximately 800 × 560 points and a sensible minimum size.
- Automatic Light/Dark appearance, San Francisco typography, pink accent, subtle hover states and sidebar animation. No artwork or decorative images.
- Collapsible sidebar with Search, Up Next, Favorites and History. Sidebar visibility persists across launches.
- Search by song title or artist across ten fictional tracks. Return submits the query; unmatched queries show an empty state.
- Native row selection and a separate current-song indicator. Double-click or Return in a focused song list simulates playback.
- Queue with independently identifiable duplicate entries, add/remove, clear, drag reordering and a Move to Top context action. Playing a queued entry consumes it.
- Synchronized favorites and recently played history with timestamps, capped at 100 entries.
- Always-visible playback bar with previous, play/pause, next, interactive progress and volume sliders. A mock timer advances progress and moves through the queue.
- Native controls, help text and accessibility labels.

| Shortcut | Action |
| --- | --- |
| Command+B | Toggle sidebar |
| Command+F | Open Search and focus the input |
| Space | Toggle mock playback outside text inputs and native controls |
| Return in Search | Submit the query and focus results |
| Return in a focused song list | Play the selected entry |
| Delete in Up Next | Remove the selected queue entry |

Previous restarts the current song after three seconds; otherwise it returns to the preceding mock song. Play at the end restarts the current song. Space preserves text editing and native control behavior.

Only sidebar visibility is stored between launches. Queue, favorites, history, volume and playback remain in memory.

## Architecture

The application uses one application-level `@Observable`, `@MainActor` state model. Every screen reads and updates the same model so queue, favorites, history and playback stay synchronized. Views contain presentation and local focus/selection state. The keyboard bridge scopes Space handling to the application window and leaves text editing alone.

```text
LocalMusic/
  App/             SwiftUI scene and command menus
  Models/          Songs, queue/history entries and navigation destinations
  ViewModels/      MusicLibrary shared state and mock playback transitions
  Views/           Window, sidebar, song lists and playback bar
  Utilities/       AppKit keyboard event bridge
LocalMusic.xcodeproj/
  project.pbxproj
  project.xcworkspace/contents.xcworkspacedata
  xcshareddata/xcschemes/LocalMusic.xcscheme
Tests/LocalMusicTests/  Swift Testing model tests
Scripts/check.sh       Package build, tests and project format checks
Package.swift          Dependency-free executable and model test targets
VALIDATION.md          Verification results, limits and manual review checklist
```

The Xcode project defines the application target. `Package.swift` provides an alternative executable build and the model test target. Future external search and playback services can be added separately; none are implemented yet.

## Validation

Run the available package and format checks:

```sh
./Scripts/check.sh
```

The script uses project-local caches. It supports full Xcode and retains a fallback for the Command Line Tools configuration used during initial development. It does not install tools or change system settings. The application build is a separate `xcodebuild` command shown above.

You can also open `Package.swift` separately in Xcode and run its model tests. See [VALIDATION.md](VALIDATION.md) for actual results and the remaining manual UI checklist. A successful model test run does not verify every focus, drag-and-drop or accessibility interaction.

## Development roadmap

- **Checkpoint 1 — implemented:** native UI, fictional search results, mock queue, favorites, history and simulated playback. The app builds and launches in Xcode.
- **Checkpoint 1 review — pending:** complete the manual Light/Dark, resizing, keyboard, drag-and-drop and accessibility checklist.
- **Checkpoint 2 — not started:** agree on the next scope before adding real search or playback. Any future yt-dlp or mpv integration needs a separate implementation and validation pass.
- **Later, separately scoped:** durable storage, packaging, signing and notarization. No release timeline or implementation commitment is implied.

## Repository hygiene

Shared Xcode project files, workspace metadata and schemes belong in Git. Build output, DerivedData, `.build`, user-specific Xcode state, editor settings, local databases, logs, credentials and signing material are ignored. Keep any future environment examples free of real secrets.

This checkpoint makes no external network requests and starts no audio processes.
