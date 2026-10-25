# Mango Music

A native macOS SwiftUI music player with explicit YouTube search, audio-only HLS streaming through yt-dlp and a persistent mpv process. Checkpoint 4 adds local SQLite persistence for Favorites, History, the manual queue, and current-track metadata, plus UserDefaults settings. The existing interface, branding, icon, and system Light/Dark appearance are preserved.

Automated database/restoration and playback tests pass, as does the native Debug build. **Checkpoint 4's visual/audible quit-and-relaunch acceptance remains unverified.** The user's successful Checkpoint 3 listening/lifecycle checks are historical evidence; they do not establish SQLite restoration. Seeking and Previous were not separately manually confirmed at Checkpoint 3. See [VALIDATION.md](VALIDATION.md).

## Running

- macOS 14+, Xcode with Swift 6, separately installed executable `yt-dlp` and `mpv`.
- Open `MangoMusic.xcodeproj`, select MangoMusic → My Mac → Debug, and Run.
- Runtime lookup checks Homebrew/local installation paths, Python framework versions for yt-dlp, and absolute PATH entries. The app never installs or updates tools.
- SQLite3 is the macOS system library, linked directly by SwiftPM/Xcode. There are no third-party Swift database dependencies.
- Debug App Sandbox remains disabled for external tools. Release remains sandboxed; external-tool streaming in Release is unsupported and not distribution-ready.

Type a song/artist and press Return. Search is explicit and limited to ten results. Single-click selects; double-click, Return, or context Play plays. Play Next prepends to Up Next; Add to Queue appends. Playback controls, buffering/error/Retry, queue reorder/remove/clear, Favorites, and History retain the native layout. Closing the window leaves playback running; the Dock reopens it. Cmd+Q flushes library changes before quitting and stopping owned processes.

## Local data and restoration

The Debug database is `~/Library/Application Support/MangoMusic/library.sqlite3`. SQLite may create `-wal` and `-shm` sidecars alongside it. The directory/file are created with private permissions. Sandboxed configurations use their per-user Application Support location. No database belongs in the Git repository.

- **Favorites:** one row per song, with its date added. Hearts update immediately in this window; a Saving banner stays visible until the serialized transaction commits. A failed write shows an unsaved-changes error with Retry. Quit is cancelled if unsaved edits cannot be flushed.
- **History:** one row per song, ordered by most recent play with a play count. A play counts only after mpv reports file-loaded and the first positive playback-clock position while playing. Selection, queuing, failed starts, pause/resume, and seeking do not add a count. Retry within the same attempt does not double-count; explicit replay after Stop/completion counts again. The 100 most recent distinct songs are retained; counts for evicted rows are not retained. There is no Clear History action.
- **Queue:** only explicitly added entries are saved, including their independent UUIDs and exact order. Intentional duplicates remain independent. Direct play leaves upcoming entries intact. A selected queued item is recoverable until the first playback-clock event; if interrupted/failed before starting, it returns to Up Next on Stop, switching away, quit, or restoration. Started entries stay consumed. An exhausted queue stops. Errors never silently skip.
- **Current track:** title/artist/known duration restore in a stopped, non-streaming state at zero elapsed time. Started tracks are not re-enqueued. Pressing Play for a recovered unstarted queued selection consumes that same queue identity once; removing it from Up Next respects the removal. Playback begins only on a user action and resolves a fresh URL. Position, pause/buffering/error state, and navigation-back history are not restored.
- **Settings:** volume and sidebar visibility use UserDefaults. Volume restores only finite numeric values, clamped to 0–1; missing/invalid values use 0.7. Sidebar accepts stored booleans, otherwise expanded. Appearance stays system-adaptive.

Opening the app makes no YouTube requests and does not launch mpv. Startup shows Restoring and prevents library edits until a consistent snapshot loads. Read errors offer Retry while preserving existing data. SQLite work runs off the main actor, with prepared/bound SQL, atomic versioned migrations, transactions, foreign keys, and WAL. A revision check rejects stale writes from another instance. Simultaneous editing in multiple instances is unsupported; conflicts require preserving/reconciling edits rather than overwriting another instance.

Only stable YouTube IDs and minimal metadata/references/timestamps/counts are stored. No signed streaming URLs, cookies, credentials, thumbnails, or audio files are persisted. No cloud services/accounts, recommendations, downloads, Core Data, SwiftData, AI, media keys, or Mini Player were added. HLS preference and playback architecture remain as documented in [YOUTUBE_PLAYBACK_DIAGNOSIS.md](YOUTUBE_PLAYBACK_DIAGNOSIS.md).

## Validation

```sh
swift build
swift test
./Scripts/check.sh
# Optional installed mpv + generated local audio + temporary SQLite, no network:
MANGO_MPV_INTEGRATION=1 swift test
# Separate optional network checks; isolated test settings, no user database:
MANGO_YOUTUBE_INTEGRATION=1 MANGO_YOUTUBE_DIAGNOSTICS=1 \
  swift test --filter 'MPVIntegrationTests.youtubeManualQueue|YouTubePlaybackIntegrationTests'
xcodebuild -project MangoMusic.xcodeproj -scheme MangoMusic \
  -configuration Debug -destination 'platform=macOS,arch=arm64' \
  CODE_SIGNING_ALLOWED=NO build
```

Ordinary tests use isolated temporary databases/UserDefaults and no network. The Xcode app scheme has no separate Test action; tests run via SwiftPM. Follow the exact two-relaunch manual checklist in [VALIDATION.md](VALIDATION.md). [ARCHITECTURE.md](ARCHITECTURE.md) covers the schema, migrations, serialized writes, shutdown, and recovery limits.

Checkpoint 3 held library data only in memory; data already lost by quitting that version cannot be recovered. Back up the full MangoMusic Application Support folder with the app fully closed. Do not remove SQLite sidecars while the app is running. Corrupt/unknown/newer databases are never automatically erased or recreated. Automatic repair/backup, conflict merging, database encryption, cloud sync, and Checkpoint 5 are outside this checkpoint. A save transaction is limited to 10,000 favorites/queue/history rows; excessive data produces a visible error rather than silent truncation (normal History retention is 100 distinct songs).
