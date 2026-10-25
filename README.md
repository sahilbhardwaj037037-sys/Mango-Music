# Mango Music

A native macOS SwiftUI music player with user-initiated YouTube search, in-memory favorites/history/manual queue, and a persistent mpv audio engine. Mango Music branding and the existing icon are preserved.

Checkpoint 3 implements real audio streaming through yt-dlp and persistent mpv, preferring audio-only HLS to address direct-stream HTTP 403 failures. All 42 tests pass with local and live integrations enabled, and the Xcode Debug build passes. The user personally confirmed audible YouTube playback, Play/Pause, volume, manual queue/Next, automatic queue advancement, History, window closure/Dock reopening, and Cmd+Q stopping playback. **Seeking and Previous have automated coverage but are not manually verified.** See [VALIDATION.md](VALIDATION.md) and [YOUTUBE_PLAYBACK_DIAGNOSIS.md](YOUTUBE_PLAYBACK_DIAGNOSIS.md).

## Requirements and running

- macOS 14 or later, Xcode with Swift 6.
- Executable `yt-dlp` and `mpv` installed separately. The app never installs or updates them.
- Runtime lookup checks `/opt/homebrew/bin`, `/usr/local/bin`, Python framework version directories for yt-dlp, and absolute directories in the inherited PATH. Finder/Dock PATH may differ from Terminal. Candidates must be executable; tests can inject explicit URLs.
- Open `MangoMusic.xcodeproj`, choose MangoMusic → My Mac → Debug, and Run.
- Debug keeps App Sandbox disabled for external tools. Release retains `ENABLE_APP_SANDBOX = YES`; external tools/IPC are not supported by that configuration. Release is not ready for distribution.

## Search and playback

Type a song or artist and press Return. Search is explicit, asynchronous, cancellable, and limited to ten results. Single-click selects; double-click, Return, or context-menu Play starts playback. Play Next inserts at the front of Up Next; Add to Queue appends. Hearts store favorites for this session.

The bottom player offers Play/Pause, Stop, Previous, Next, elapsed time, actual duration, seeking, and volume. Loading/buffering appear in the toolbar; failures appear above the seek slider with Retry. Seeking is disabled until mpv reports a duration. Retry resolves a fresh URL and never skips to another song. Play after Stop or completion restarts the displayed song. Loading must finish before Pause is available; Stop and choosing another song cancel it.

Only explicitly added songs enter Up Next. Direct playback leaves Up Next intact. Next consumes its first item; successful EOF does the same. An empty queue stops. Previous seeks to zero after three seconds; otherwise it pops the prior selected track from navigation history, without re-enqueueing the track being left. That history includes track selections whose playback failed; the visible History list records only tracks mpv successfully loaded. Playing a queue entry removes only that entry. Duplicate entries have independent identities. Reorder, remove, and Clear Queue affect upcoming tracks; clearing does not stop the current song.

Closing the window leaves the app and playback running. Clicking the Dock icon reopens the single main window. Cmd+Q cancels search/resolution, terminates the owned mpv child, and removes its private socket directory. No login item or background service is installed.

## Architecture and privacy

SwiftUI → `MusicLibrary` → `AudioStreamResolving` / `AudioPlaying`. The production implementations are `AudioStreamResolver` and `MPVPlaybackEngine`; `MPVConnection` owns JSON IPC. See [ARCHITECTURE.md](ARCHITECTURE.md).

Resolution uses Swift Process with literal argument arrays, `bestaudio[protocol^=m3u8]/bestaudio`, `--get-url`, disabled configuration/plugins/cache, no playlist, and no media download. IDs are strictly validated. HLS is preferred for the public formats that failed direct playback; the fallback remains audio-only. Some videos without accessible HLS can still fail and show Retry. Signed HTTPS URLs remain in memory, are never logged, and are freshly resolved for every playback attempt. No cookies, authentication, DRM bypass, artwork, thumbnails, subtitles, paid API, browser, Electron, WebView, AI service, or SQLite are used. mpv buffers audio in memory; disk caching and saving playback positions are explicitly disabled.

## Tests

```sh
swift test
# Optional: installed mpv, generated local PCM audio, null output, no network:
MANGO_MPV_INTEGRATION=1 swift test --filter MPVIntegrationTests.localAudioIPC
# Optional: live YouTube search, resolution, and a two-entry queue:
MANGO_YOUTUBE_INTEGRATION=1 swift test --filter MPVIntegrationTests.youtubeManualQueue
# Optional: three canonical public videos with observed pause/resume, seek, volume:
MANGO_YOUTUBE_DIAGNOSTICS=1 swift test --filter YouTubePlaybackIntegrationTests
xcodebuild -project MangoMusic.xcodeproj -scheme MangoMusic \
  -configuration Debug -destination 'platform=macOS,arch=arm64' \
  CODE_SIGNING_ALLOWED=NO build
```

Ordinary tests use fixtures and require no network or installed media tools. The existing Xcode app scheme has no Test action/test target; run the test suite with SwiftPM. `CODE_SIGNING_ALLOWED=NO` builds verify compilation, not signing or distribution.

Queue, favorites, and history are intentionally in memory. Sidebar visibility remains a UserDefaults preference. Media keys, Mini Player, and persistence are outside this checkpoint.
