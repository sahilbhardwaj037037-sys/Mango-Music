# Mango Music

A native macOS SwiftUI music player with explicit YouTube search, audio-only HLS streaming through yt-dlp and a persistent mpv process. Checkpoint 4 adds local SQLite persistence for Favorites, History, the manual queue, and current-track metadata, plus UserDefaults settings. Checkpoint 5 adds public native macOS media integration and playback synchronization. The existing interface, branding, icon, and system Light/Dark appearance are preserved.

Automated persistence, native API, playback, and Debug build checks pass. The user confirmed Checkpoint 4 Favorites/History/Queue/preferences restore after restart without autoplay. **For Checkpoint 5, the user manually confirmed the Xcode Debug launch, audible YouTube playback, Control Center rendering and Play/Pause/Next/Previous, background playback and Control Center commands with the window closed, Dock reopening, and Cmd+Q stopping playback/quitting without visible errors on this Mac.** Physical keyboard media keys, Bluetooth headphone controls, system-level seeking, physical sleep/wake, output-device changes, and process-level orphan checks remain manually unverified. See [VALIDATION.md](VALIDATION.md); previous persistence evidence is retained in [VALIDATION_CHECKPOINT4.md](VALIDATION_CHECKPOINT4.md).

## Native macOS media controls

Mango Music uses MediaPlayer's MPNowPlayingInfoCenter and MPRemoteCommandCenter (available on the macOS 14 target), NSWorkspace sleep/wake notifications, and CoreAudio default-output notifications. Only title, artist/channel, known duration, actual mpv elapsed time, and rate/state are published; there is no artwork or media URL. Ordinary elapsed anchors publish at most every five seconds; metadata, state, seeks, and discontinuities update immediately. Stop, completion without another queue item, errors, and quit clear the metadata. Control Center rendering and Play/Pause/Next/Previous delivery are manually confirmed on this Mac. macOS may choose another Now Playing app or omit controls elsewhere; physical hardware and system seeking still need the checklist below.

Supported registered commands are Play, Pause, Toggle Play/Pause, Next, Previous, absolute playback-position seek when duration is known, and Stop. Commands and the bottom player use one capability/controller path; Next uses only your manual queue. Rapid toggles preserve intent until mpv acknowledges each command. Play/Pause are idempotent; Next/Previous preserve a genuine pause. Pause while Loading cancels that attempt, including late resolution. The existing in-app shortcuts remain local to the window. No global key tap or Accessibility permission was added. Compatible keyboard/headphone/USB commands use the same macOS path, without universal-device claims.

The app registers handlers once at application scope and removes its own handlers on teardown. The owned mpv is launched with `--media-controls=no --input-media-keys=no`, so the child does not compete with Mango Music. mpv 0.41.0 is the validated version for these flags. `--stop-screensaver=no` avoids child sleep prevention. Window closure/Dock reopening do not register another integration or player. On system sleep or a changed default audio device, active playback/resolution stops, the owned audio process is terminated, and unstarted queued items are preserved. Sleep also invalidates queued commands and releases an idle owned child; wake never starts audio. Press Play explicitly to resolve a fresh stream and restart from the beginning; a small notice explains the interruption. Switching apps or display-only sleep does not invoke this stop policy. Network/startup errors retain explicit Retry without auto-skipping.


## Standalone local app (Checkpoint 6)

The isolated packaging pipeline builds **Mango Music.app** with an arm64 application and minimal mpv, plus verified standalone yt-dlp with its own embedded Python runtime. The tested search/HLS path needs no installed Homebrew/Python/Deno or external dylibs. It targets macOS 14; runtime checks were performed on this Mac, not a macOS 14 machine. The upstream yt-dlp helper retains its universal architecture.

See [PACKAGING.md](PACKAGING.md) for pinned acquisition, offline builds, licenses, ad-hoc signing, sandbox trade-offs, and safe installation/rebuilding. Output is `.build/packaging/output/Mango Music.app`. **The user manually verified the isolated standalone app on this Mac: Finder launch without Xcode, real YouTube search and audible playback, Play/Pause/Next/Previous/volume, manual queue playback, Control Center playback controls, background playback and Dock reopening, restoration of Favorites/History/Queue/settings, and Cmd+Q stopping playback.** Earlier Debug results remain separate. macOS 14 runtime compatibility, hardware media keys/headphones, system seeking, physical sleep/wake, output changes and process-level orphan checks remain manually unverified. No matching installed copy was found in `/Applications` or `~/Applications` during the follow-up check. The `/Applications/Mango Music.app` installation plan is documented in PACKAGING.md and awaits separate approval; nothing has been installed or replaced. This is local-use packaging, without Developer ID signing, notarization, or public-distribution claims.

## Running

- macOS 14+, Xcode with Swift 6, separately installed executable `yt-dlp` and `mpv`.
- Open `MangoMusic.xcodeproj`, select MangoMusic → My Mac → Debug, and Run.
- Runtime lookup checks Homebrew/local installation paths, Python framework versions for yt-dlp, and absolute PATH entries. The app never installs or updates tools.
- SQLite3 is the macOS system library, linked directly by SwiftPM/Xcode. There are no third-party Swift database dependencies.
- Debug remains unchanged with external development tools. Stock Xcode Release remains sandboxed. The local packaging script builds a separate Release configuration with App Sandbox disabled for bundled helpers and Unix IPC; see the security and signing limits in [PACKAGING.md](PACKAGING.md).

Type a song/artist and press Return. Search is explicit and limited to ten results. Single-click selects; double-click, Return, or context Play plays. Play Next prepends to Up Next; Add to Queue appends. Playback controls, buffering/error/Retry, queue reorder/remove/clear, Favorites, and History retain the native layout. Closing the window leaves playback running; the Dock reopens it. Cmd+Q flushes library changes before quitting and stopping owned processes.

## Local data and restoration

The Debug database is `~/Library/Application Support/MangoMusic/library.sqlite3`. SQLite may create `-wal` and `-shm` sidecars alongside it. The directory/file are created with private permissions. Sandboxed configurations use their per-user Application Support location. No database belongs in the Git repository.

- **Favorites:** one row per song, with its date added. Hearts update immediately in this window; a Saving banner stays visible until the serialized transaction commits. A failed write shows an unsaved-changes error with Retry. Quit is cancelled if unsaved edits cannot be flushed.
- **History:** one row per song, ordered by most recent play with a play count. A play counts only after mpv reports file-loaded and the first positive playback-clock position while playing. Selection, queuing, failed starts, pause/resume, and seeking do not add a count. Retry within the same attempt does not double-count; explicit replay after Stop/completion counts again. The 100 most recent distinct songs are retained; counts for evicted rows are not retained. There is no Clear History action.
- **Queue:** only explicitly added entries are saved, including their independent UUIDs and exact order. Intentional duplicates remain independent. Direct play leaves upcoming entries intact. A selected queued item is recoverable until the first playback-clock event; if interrupted/failed before starting, it returns to Up Next on Stop, switching away, quit, or restoration. Started entries stay consumed. An exhausted queue stops. Errors never silently skip.
- **Current track:** title/artist/known duration restore in a stopped, non-streaming state at zero elapsed time. Started tracks are not re-enqueued. Pressing Play for a recovered unstarted queued selection consumes that same queue identity once; removing it from Up Next respects the removal. Playback begins only on a user action and resolves a fresh URL. Position, pause/buffering/error state, and navigation-back history are not restored.
- **Settings:** volume and sidebar visibility use UserDefaults. Volume restores only finite numeric values, clamped to 0–1; missing/invalid values use 0.7. Sidebar accepts stored booleans, otherwise expanded. Appearance stays system-adaptive.

Opening the app makes no YouTube requests and does not launch mpv. Startup shows Restoring and prevents library edits until a consistent snapshot loads. Read errors offer Retry while preserving existing data. SQLite work runs off the main actor, with prepared/bound SQL, atomic versioned migrations, transactions, foreign keys, and WAL. A revision check rejects stale writes from another instance. Simultaneous editing in multiple instances is unsupported; conflicts require preserving/reconciling edits rather than overwriting another instance.

Only stable YouTube IDs and minimal metadata/references/timestamps/counts are stored. No signed streaming URLs, cookies, credentials, thumbnails, or audio files are persisted. No cloud services/accounts, recommendations, downloads, Core Data, SwiftData, AI, or Mini Player were added. HLS preference and playback architecture remain as documented in [YOUTUBE_PLAYBACK_DIAGNOSIS.md](YOUTUBE_PLAYBACK_DIAGNOSIS.md).

## Validation

```sh
swift build
swift test
./Scripts/check.sh
# Optional installed mpv + generated local audio + temporary SQLite, no network:
MANGO_MPV_INTEGRATION=1 swift test
# Optional real macOS API registration/readback (no hardware events or Control Center proof):
MANGO_NATIVE_MEDIA_INTEGRATION=1 swift test --filter 'SystemMediaTests.native'
# Separate optional network checks; isolated test settings, no user database:
MANGO_YOUTUBE_INTEGRATION=1 MANGO_YOUTUBE_DIAGNOSTICS=1 \
  swift test --filter 'MPVIntegrationTests.youtubeManualQueue|YouTubePlaybackIntegrationTests'
xcodebuild -project MangoMusic.xcodeproj -scheme MangoMusic \
  -configuration Debug -destination 'platform=macOS,arch=arm64' \
  CODE_SIGNING_ALLOWED=NO build
```

Ordinary tests use isolated temporary databases/UserDefaults and no network. The Xcode app scheme has no separate Test action; tests run via SwiftPM. Follow the media-control checklist in [VALIDATION.md](VALIDATION.md); the two-relaunch persistence checklist remains in [VALIDATION_CHECKPOINT4.md](VALIDATION_CHECKPOINT4.md). [ARCHITECTURE.md](ARCHITECTURE.md) covers the schema, migrations, serialized writes, shutdown, and recovery limits.

Checkpoint 3 held library data only in memory; data already lost by quitting that version cannot be recovered. Back up the full MangoMusic Application Support folder with the app fully closed. Do not remove SQLite sidecars while the app is running. Corrupt/unknown/newer databases are never automatically erased or recreated. Automatic repair/backup, conflict merging, database encryption and cloud sync remain outside scope; Checkpoint 6 packaging is described above. A save transaction is limited to 10,000 favorites/queue/history rows; excessive data produces a visible error rather than silent truncation (normal History retention is 100 distinct songs).
