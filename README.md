# Mango Music

Mango Music is a native macOS application built with Swift and SwiftUI. Checkpoint 2 adds real YouTube search through an existing local yt-dlp installation. **Playback is still simulated: the app does not stream or play audio.** Queue, favorites and history remain in memory.

## Requirements

- macOS 14 or later. Runtime checks use Apple Silicon on macOS 26.
- Full Xcode with Swift 6 support. Validated with Xcode 27.1 and Swift 6.4.
- An existing executable yt-dlp installation and its working Python runtime, if that installation requires Python.
- Network access when you explicitly submit a search.

The service checks these fixed executable locations in order:

1. `/Library/Frameworks/Python.framework/Versions/3.14/bin/yt-dlp`
2. `/opt/homebrew/bin/yt-dlp`
3. `/usr/local/bin/yt-dlp`

The app never installs or updates tools automatically. Other executable locations require a deliberate service configuration change. No paid API, accounts, API keys, browser, WebView, Electron, third-party Swift dependencies or mpv integration are used.

## Open and run

The repository directory is now `MangoMusic`. Open `MangoMusic.xcodeproj`, select **MangoMusic → My Mac**, choose **Debug**, and press **Command+R**.

- Display name: **Mango Music**
- Project, target, scheme, executable and Swift module: `MangoMusic`
- Swift package test target: `MangoMusicTests`
- Bundle identifier: `com.localmusic.MangoMusic`

The identifier retains the previous reverse-domain prefix. macOS treats it as a separate preferences/container identity; the former app's saved sidebar visibility is not migrated. Git history and the existing origin remote are preserved.

`MangoMusic/App/Info.plist` supplies application metadata. The existing icon and visible Mango Music branding are unchanged. If signing requires a team, choose your local team without committing personal signing settings.

## Search and mock playback

Type a song, artist or other search phrase and press **Return**. Typing alone, opening the app, navigating and clearing the input do not start network requests. Retry explicitly resubmits the last valid submitted query. Cancel stops the active process. New submissions cancel previous requests; late responses cannot replace the newer search state.

Up to ten results show title, channel and duration where supplied. Unknown duration is shown as **—**. Loading, empty, cancelled and error states are distinct. Error states offer Retry when there is a valid submitted query.

Search is YouTube-only: the validated phrase is one `ytsearch10:` argument. The native service uses a fixed executable URL and argument array, never a shell. Its options include:

```text
--ignore-config --no-plugin-dirs --no-cache-dir --simulate --skip-download
--flat-playlist --dump-single-json --no-progress
--socket-timeout 15 --retries 1 --extractor-retries 1 -- ytsearch10:<query>
```

The flags follow [yt-dlp’s official command-line options](https://github.com/yt-dlp/yt-dlp#usage-and-options). JSON metadata is decoded into songs. No audio, video, thumbnails or artwork are downloaded. Returned titles and channel names are display data; metadata is never used to construct executable commands. User configuration files and plugins are disabled so they cannot add downloader hooks or commands.

Queries must contain 1–200 characters and no control characters. Both output pipes are drained off the main actor, with bounded buffers and a 45-second overall timeout. Cancellation terminates the process, with a kill fallback for an unresponsive child. UI errors use safe messages instead of displaying raw server/subprocess diagnostics, queries or local paths.

Double-click or Return on a selected result **simulates** playback. There is no audio. Real search songs can be queued, favorited and recorded in mock history. Unknown-duration tracks have no seek range and remain at zero elapsed time; manual Next still advances the queue.

Existing features remain:

- Resizable native window, collapsible sidebar and saved sidebar visibility.
- Automatic Light/Dark appearance, San Francisco typography and pink accent.
- Up Next add/remove/clear/reorder, Favorites and recently played History.
- Persistent mock playback bar with previous/play/pause/next, seek and volume state.
- No song artwork or visualizers.

| Shortcut | Action |
| --- | --- |
| Command+B | Toggle sidebar |
| Command+F | Open Search and focus the input |
| Return in Search | Submit a real YouTube search |
| Return in a focused song list | Simulate playback of the selection |
| Space | Toggle mock playback outside text inputs and native controls |
| Delete in Up Next | Remove the selected queue entry |

## Architecture

```text
MangoMusic/
  App/             SwiftUI app, commands and Info.plist
  Assets.xcassets/  Existing macOS AppIcon
  Models/          Songs and queue/history identities
  ViewModels/      Main-actor observable library and search state
  Services/        SongSearching, YouTubeSearchService, ProcessRunning, ProcessRunner
  Views/           Sidebar, search states, lists and mock playback controls
  Utilities/       Window-scoped keyboard bridge
MangoMusic.xcodeproj/  App target and shared MangoMusic scheme
Tests/MangoMusicTests/ Offline decoding, process, search state and library tests
Scripts/check.sh      Swift package build, tests and project format checks
Package.swift         Executable and test targets
VALIDATION.md         Actual results and remaining manual checks
```

`MusicLibrary` synchronizes navigation, favorites, queue, history and playback on the main actor. `SongSearching` isolates search from the UI; `ProcessRunning` isolates subprocess management from yt-dlp decoding. Both are injectable for offline tests and can be replaced by a bundled helper or another native service later. The Swift package excludes Xcode-only assets/Info.plist and is a test/development executable, not the distributable app bundle.

## Local development security decision

**The MangoMusic application target disables App Sandbox only for Debug builds**, with the owner's explicit approval, to execute the separately installed yt-dlp and its Python runtime. The process runs with the local user's permissions. This changes no macOS-wide security setting and does not disable SIP or Gatekeeper.

Only fixed tool locations and fixed options are used. No YouTube metadata is executed. The subprocess receives a minimal environment rather than inherited credential or Python injection variables. Search remains user initiated.

**Release retains App Sandbox and is not supported for external-tool search in this checkpoint.** Distribution, signing, notarization, bundled tooling and a sandbox-compatible helper/permissions design require separate work before release. The service boundaries allow that design to be reconsidered without replacing the SwiftUI frontend. No temporary broad sandbox exceptions are added.

## Build and validation

From the repository root:

```sh
xcodebuild -project MangoMusic.xcodeproj -scheme MangoMusic \
  -configuration Debug -destination 'platform=macOS' \
  -derivedDataPath .build/SearchDerivedData CODE_SIGNING_ALLOWED=NO build
./Scripts/check.sh
```

The script builds the Swift package, runs all automated tests and validates the shared project/scheme. It uses fresh project-local cache and package build paths so precompiled artifacts from the old directory are not reused. Tests inject fixtures or use local system executables; they do not contact YouTube. Live search is checked separately and explicitly.

See [VALIDATION.md](VALIDATION.md) for results, limits and manual instructions. Keep `.build`, DerivedData, local caches/databases, Xcode user settings, credentials and signing files out of Git; ignore rules remain in place.

## Roadmap

- Checkpoint 1: native UI and mock library/playback foundation.
- Checkpoint 1.1: Mango Music branding and supplied app icon.
- Internal rename: MangoMusic project, module, scheme, package and directory.
- Checkpoint 2: real YouTube metadata search; playback remains mock.
- Checkpoint 3: real audio playback — **not started**. No mpv integration is included.

Persistent storage, distribution packaging and a sandbox-compatible bundled-helper design remain separately scoped future work.
