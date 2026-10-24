# Mango Music — rename and Checkpoint 2 validation

Checked October 24, 2026, on Apple Silicon / macOS 26 with Xcode 27.1 and Swift 6.4. Minimum deployment remains macOS 14; older macOS versions and Intel runtime behavior have not been tested.

## Phase A: internal rename

The existing repository moved from `LocalMusic` to `MangoMusic`. Its Git history, origin, Mango Music branding and exact icon assets were retained. The Xcode object identifiers stayed stable while source/project paths, target, shared scheme, executable, package and test module references were updated.

- Xcode project: `MangoMusic.xcodeproj`
- Target, scheme, executable and module: `MangoMusic`
- Test target: `MangoMusicTests`
- Bundle identifier: `com.localmusic.MangoMusic`
- User-visible name: **Mango Music**

Changing the identifier gives macOS a new preferences/container identity. The former saved sidebar visibility is not migrated. Queue, history and favorites were already in-memory only. Fresh package and compiler-cache paths in `Scripts/check.sh` avoid using precompiled files tied to the original directory.

Phase A application build and all **six existing tests passed**. The renamed project opened in Xcode. The app launched, and macOS reported Mango Music, an available app icon, regular Dock activation policy and one on-screen window. Phase A was committed separately before search implementation.

## Phase B: real search

`YouTubeSearchService` calls the existing yt-dlp executable with explicit arguments and decodes flat-playlist JSON. It validates queries, caps the result list at ten, validates YouTube video identifiers, filters duplicate/unusable entries, handles optional channel/duration metadata and rejects malformed responses. Unknown or unreasonable duration is shown as **—**.

`FoundationProcessRunner` runs off the main actor, drains stdout/stderr concurrently, limits output and enforces an overall timeout. Cancellation handles start/cancel races, sends termination and escalates to a kill for an unresponsive process. Closing the main window or terminating the application cancels an active search. A cancelled or superseded request cannot change newer search state, even if a service ignores cancellation.

Requests only originate from explicit Return/Retry actions. Opening the app, editing text, clearing the input and ordinary navigation start no requests. No media or thumbnail downloads, audio streaming, mpv, paid API or browser integration was added. Search metadata can be used in the existing mock queue, favorites and history.

## Security decision

The owner explicitly approved disabling App Sandbox for local development. **Only Debug on the MangoMusic application target sets `ENABLE_APP_SANDBOX = NO`. Release retains `YES`.** No system-wide setting, SIP, Gatekeeper or unrelated target was changed.

The service uses fixed tool installation paths and `Process.executableURL` / argument arrays. It never invokes a shell or executes returned metadata. User downloader configuration/plugins and persistent caching are disabled. A minimal subprocess environment excludes inherited credential/Python injection variables. Raw subprocess/server text is not presented as a UI error. Distribution and a sandbox-compatible bundled-helper design remain future work; Release external-tool search is not supported by this checkpoint.

## Commands and actual results

Phase A:

```sh
xcodebuild -project MangoMusic.xcodeproj -scheme MangoMusic \
  -destination 'platform=macOS' -derivedDataPath .build/RenameDerivedData \
  CODE_SIGNING_ALLOWED=NO build
./Scripts/check.sh
```

Phase B:

```sh
xcodebuild -project MangoMusic.xcodeproj -scheme MangoMusic \
  -configuration Debug -destination 'platform=macOS' \
  -derivedDataPath .build/SearchDerivedData CODE_SIGNING_ALLOWED=NO build
./Scripts/check.sh
```

The script executes the Swift package build and test suite using `.build/MangoMusicPackage` and fresh project-local caches, then validates project plist and shared-scheme XML. No third-party packages are fetched.

| Check | Result |
| --- | --- |
| Phase A native Xcode build | Passed |
| Phase A package build / six tests | Passed |
| Phase B native Debug Xcode build | Passed |
| Phase B Swift package build | Passed |
| Automated tests | **27 tests in 3 suites passed** |
| Xcode project plist / scheme XML | Passed |
| Explicit live service search | **Passed: ten results, all ten with durations** |
| Final Debug app launch | Passed: Mango Music name, icon available and one on-screen window |

The live check called the production `YouTubeSearchService`/`FoundationProcessRunner` with “Bach cello suite” using the installed Python-framework yt-dlp (2026.08.19). A temporary native executable compiled the same service and model source to perform this one explicit search. It was not an automated unit test or a simulated JSON result. It downloaded no media/artwork and committed no returned metadata. The service also detects Homebrew installation paths; the Homebrew binary present locally reports 2026.10.21.

Automated tests are entirely offline. Coverage includes all existing queue/history/playback/sidebar behavior; fixture-based search integration; valid/empty/malformed JSON; missing and unknown metadata; duplicate removal and ten-result limit; input validation and literal arguments; missing executable and launch/nonzero errors; simultaneous pipe drainage beyond a pipe buffer; bounded output; actual child-process cancellation/timeout; initial idle state; loading, success, empty, error, Retry, clear and cancellation; stale success/error rejection; and favorites for real metadata with unknown-duration mock playback.

The previous mock-only search test was adapted to an injected fixture service; it does not contact YouTube. Its empty-input assertion now tests clearing to idle, since an empty input must not trigger a real search. The other five original regression tests retain their behavior.

The native build can emit the existing AppIntents metadata-extraction warning because no AppIntents dependency is present. Build logs, generated smoke executables, temporary previews and raw diagnostics remain only in ignored `.build/`. Signing, notarization, distribution and Release search were not validated.

## Manual checks

1. Open the new project, run **MangoMusic / My Mac / Debug**, and confirm Mango Music's name and original icon.
2. Type without pressing Return: no search should start. Press Return: verify loading and up to ten YouTube results, including channel and duration.
3. Submit a new query while one is loading, or press Cancel. Verify the newer results/cancelled state stay visible. Retry should resubmit the last valid query.
4. Clear the field: verify the initial search prompt, with no automatic request. Test an invalid or oversized query; it should show a validation message.
5. Disconnect networking using your normal controls and submit a search. Verify a safe error/timeout and Retry. Automated tests cover nonzero/missing-executable behavior without changing installed tools.
6. Add a result to the queue and favorites, submit another search, and revisit Favorites. Double-click/Return should update mock playback and history without producing sound.
7. Verify Command+B, Command+F, typing spaces, list Return/Delete, queue reorder, Light/Dark contrast, resizing and VoiceOver labels. Unknown duration should show a dash with seeking disabled.
8. Review the Debug-only sandbox setting and README security note before any future distribution work.

Screen capture access is unavailable; no fabricated screenshots or unperformed visual checks are claimed. Full keyboard/pointer/accessibility review remains manual. YouTube availability and metadata may change; the implementation handles process failure without silent fallback to mock search results.

## Historical console diagnostic

The Checkpoint 1 `fopen failed for data file: errno = 2 (No such file or directory)` message was traced to Apple's `libCoreFSCache.dylib` in OpenGL.framework, followed by `Invalidating cache`. No matching app file-loading operation was found, and no logging was suppressed. That earlier framework diagnostic is separate from yt-dlp error handling.

## Scope

Playback, seeking and volume remain mock state. Nothing from Checkpoint 3, including actual audio playback or mpv integration, is implemented. Existing commits and origin are retained; the rename and search are separate commits, pushed normally after validation.
