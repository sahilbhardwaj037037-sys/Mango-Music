# Checkpoint 1 validation

Last checked: October 24, 2026. The current version uses fictional mock songs and simulated playback only.

## Current environment

- Full Xcode 27.1, build 27A9275, is installed and selected.
- Swift 6.4; Apple Silicon; macOS 26 development host.
- Minimum deployment target: macOS 14. Older macOS releases and Intel hardware have not been runtime-tested.
- No third-party dependencies or external audio tools are needed for this checkpoint.

Full Xcode was unavailable during initial implementation. That earlier limitation has been resolved. The application now builds and launches from Xcode on My Mac.

## Publication validation commands

Run from the repository root:

```sh
./Scripts/check.sh

xcodebuild -project LocalMusic.xcodeproj -scheme LocalMusic \
  -destination 'platform=macOS' -derivedDataPath .build/XcodeDerivedData \
  CODE_SIGNING_ALLOWED=NO build
```

With full Xcode selected, the check script executes:

```sh
export CLANG_MODULE_CACHE_PATH="$PWD/.build/clang-cache"
export SWIFTPM_MODULECACHE_OVERRIDE="$PWD/.build/module-cache"
swift build --cache-path .build/cache
swift test --cache-path .build/cache --disable-xctest
plutil -lint LocalMusic.xcodeproj/project.pbxproj
xmllint --noout LocalMusic.xcodeproj/xcshareddata/xcschemes/LocalMusic.xcscheme
```

| Check | Actual result |
| --- | --- |
| Native Xcode application target build | **Passed — BUILD SUCCEEDED** |
| Swift package executable build | **Passed** |
| Swift Testing model suite | **6 passed, 0 failures** |
| Xcode project property list | **Passed** |
| Shared scheme XML | **Passed** |
| App launch in Xcode / My Mac | **Confirmed by the developer** |
| Existing Xcode-launched app process and window | **Independently confirmed after the reported console diagnostic** |

The Xcode build emits a metadata-extraction warning because the app has no AppIntents dependency. It does not prevent the build. Compiler plugins required running the checks outside the coding tool's restricted sandbox; no project settings were changed to bypass that restriction.

Tests cover search filtering and empty results, independent duplicate queue entries, queue reordering, timed playback advancement and stopping, favorites/pause/previous state, and sidebar visibility persistence.

Local build output and raw diagnostic logs are retained only under ignored `.build/`. Those artifacts can include machine-specific paths and are excluded from publication.

## Investigated console diagnostic

The exact message reported during an Xcode launch was:

```text
fopen failed for data file: errno = 2 (No such file or directory)
```

Unified logs identified Apple's `libCoreFSCache.dylib` inside OpenGL.framework as the emitter. Each occurrence was followed by `Invalidating cache` from the same library and thread. The records do not name the missing file.

This is a macOS framework diagnostic emitted inside the LocalMusic process. Application source contains no matching log or explicit data-file loading operation. The app remained running with its window visible afterward. No functionality impact was observed, and no application code or log-suppression settings were changed. The evidence supports framework cache handling; it does not establish which cache file was missing.

## Screenshots and visual verification

Earlier executable launches using per-app Light/Dark overrides created a native 800 × 560 window. Screen capture access was unavailable, so no screenshots were captured. Those launch checks do not establish that every visual or input behavior has passed review.

## Manual visual and interaction review checklist

The app build and launch are confirmed. Remaining items require hands-on review:

- [x] Open `LocalMusic.xcodeproj`, select LocalMusic / My Mac, build and run with full Xcode (confirmed by the developer; application build also independently verified).
- [ ] Review Light and Dark appearance; verify readable secondary text, selected rows and current-song pink indicators.
- [ ] Confirm the initial window, native title bar, traffic lights, minimum size, and larger window layouts have no overlapping controls.
- [ ] Collapse/expand using the visible toolbar button and Command+B; verify the content expands and sidebar visibility survives relaunch.
- [ ] Use Command+F from every screen; type a query containing spaces and submit Return. Verify the input is focused and Space never starts playback while typing.
- [ ] Single-click and arrow through songs; double-click and press Return in a focused list to play. Verify selection and the currently playing indicator remain distinguishable.
- [ ] Add a song twice; reorder its queue entries independently, remove one with its button, remove a selected entry with Delete, and clear the queue.
- [ ] Drag an upcoming row onto another, and verify Move to Top works through the context menu.
- [ ] Toggle hearts on different screens; verify Favorites synchronizes, History records playback, and their empty states remain readable at minimum size.
- [ ] Exercise previous/play/pause/next, seek to an arbitrary time and the end, change volume, and verify all controls only update mock state.
- [ ] Confirm Space respects focused native controls and Return/Delete do not interfere with text editing.
- [ ] Inspect button hover/help text and keyboard focus. Use VoiceOver to review search, song actions, playback and volume labels.
- [ ] Capture genuine Light and Dark screenshots after allowing screen capture through the normal macOS process, if desired.

## Scope and remaining limits

- Only sidebar visibility persists; queue, favorites, history, volume and playback reset on restart.
- Model tests do not cover pointer gestures, focus, drag-and-drop, accessibility behavior or visual layout.
- The Xcode project has one application target. The test target is defined by `Package.swift`.
- No real search/audio, yt-dlp/mpv calls, database, distribution packaging, signing/notarization workflow or Checkpoint 2 functionality is implemented.

## Publication preparation

The local repository is prepared on `main`. No initial commit, remote repository or push has been made; these require explicit approval after reviewing the proposed file list.

The publication candidate includes the shared Xcode project, workspace and scheme, all Swift source, model tests, validation script, package manifest and documentation. Ignore rules exclude generated output, user-specific settings, local databases, caches, logs, temporary files, credentials and signing material. Candidate files are checked for personal paths, account identifiers and common secret patterns before approval is requested.
