# Mango Music

A native macOS SwiftUI music player with explicit YouTube search, audio-only HLS streaming through yt-dlp and a persistent mpv process. Checkpoint 4 adds local SQLite persistence for Favorites, History, the manual queue, and current-track metadata, plus UserDefaults settings. Checkpoint 5 adds public native macOS media integration and playback synchronization. The existing interface, branding, icon, and system Light/Dark appearance are preserved.

**V2 test release 2.0.1/build 202:** staged at `.build/v2-2.0.1-202/output/Mango Music.app` (54.25 MiB). The user confirms the original Repeat One/All window shaking is fixed in Build 201. Build 202 changes only routine save-status presentation: short saves remain invisible, and slow saves can show a stable delayed label in the same 22-point region. **Save-label flicker fix: AWAITING MANUAL VISUAL VERIFICATION.** The native menu-bar **Appearance → System / Light / Dark**, its persistence and styling are unchanged; no in-app selector was added. See [RELEASE_BUILD_202.md](RELEASE_BUILD_202.md) for tests and the protected launch command. Build 201 and earlier artifacts, the installed V1 and real user data are preserved; no Phase 4B work occurred.

Automated persistence, native API, playback, and Debug build checks pass. The user confirmed Checkpoint 4 Favorites/History/Queue/preferences restore after restart without autoplay. **For Checkpoint 5, the user manually confirmed the Xcode Debug launch, audible YouTube playback, Control Center rendering and Play/Pause/Next/Previous, background playback and Control Center commands with the window closed, Dock reopening, and Cmd+Q stopping playback/quitting without visible errors on this Mac.** Physical keyboard media keys, Bluetooth headphone controls, system-level seeking, physical sleep/wake, output-device changes, and process-level orphan checks remain manually unverified. See [VALIDATION.md](VALIDATION.md); previous persistence evidence is retained in [VALIDATION_CHECKPOINT4.md](VALIDATION_CHECKPOINT4.md).

## Checkpoint 7, Phase 1 — Repeat and Favorites playback

Favorites now has **Play All** and **Shuffle**. Both play a snapshot continuously; Shuffle fixes its order for the session. Added favorites join the next snapshot; removed songs are skipped in future selections. The current favorite retains the existing pink speaker/title indication. The player repeat button cycles **Off → One → All → Off** and saves the choice across launches.

On natural completion: Repeat One restarts the current song; otherwise manually queued songs play before the next favorite. After the queue drains, playback resumes at the next favorite without moving or duplicating the playlist position. Repeat All wraps the active Favorites snapshot, including a single favorite, and never recreates consumed queue entries. Manual Next/Previous bypass Repeat One. Direct Play ends the active playlist; Repeat All does not loop a standalone song or consumed manual queue. Errors stop with Retry; use Next to bypass an unavailable song. This Phase 1 policy remains when Smart Autoplay is Off; Phase 2B adds optional recommendations after finite playback. Offline downloads are introduced in Phase 3B below.

The snapshot is session-only. Relaunch preserves repeat preference and existing SQLite data, restores stopped metadata, and never autoplays. The stable installed `/Applications/Mango Music.app` reported by the user is unchanged. These features are included in the separately staged Phase 4A V2 package; Debug instructions remain in [VALIDATION.md](VALIDATION.md).

## Phase 1.5 — History management

History now offers **Delete from History** in each row's context menu (or select a row and press Delete), plus **Clear History…** with Cancel/Clear confirmation. These remove listening records only; Favorites, Queue, active playlists, playback, and music files are preserved.

Use the native **Auto-cleanup** picker for Never (default), After 7 days, After 30 days, or After 90 days, and **Keep** for Unlimited (default), 100 songs, or 500 songs. Both preferences persist. Selecting a stricter policy immediately removes eligible older entries; cleanup also runs on library restoration, new playback, and scheduled expiry while open. Ages use elapsed 24-hour days since the latest play, and limits retain the newest distinct songs. Expanding a policy does not restore deleted records. Cleared/deleted songs may appear again on a later playback attempt.

The user reports Phase 1 manual playback checks passed: Repeat Off/One/All, Favorites Play All/Shuffle, manual queue priority and playlist continuation. The user also reports all five Phase 1.5 History manual checks passed; follow [VALIDATION.md](VALIDATION.md) using an isolated Xcode test home. The installed stable application remains unchanged.

## Phase 2B — Smart Autoplay

The player has an **Autoplay** switch directly below the transport/volume row. It defaults Off and remembers your choice. When On, YouTube Mix recommendations continue after the manual queue and Favorites finish. A track label distinguishes **YouTube Mix** from **Related search** fallback. Loading and unavailable/cooldown messages appear beside the switch.

Natural completion follows: **Repeat One → manual queue → remaining Favorites → Repeat All Favorites wrap → opted-in Autoplay → stop**. Manual Next bypasses Repeat One and keeps a genuine pause, including when waiting for recommendations. Repeat All loops an active finite Favorites snapshot; it never recreates consumed manual queue entries or loops a radio batch. Queue detours preserve playlist/radio continuation. With Autoplay Off, Phase 1 playback behavior remains.

Recommendations are anonymous, bounded to 20, deduplicated against recent selections/History and the manual queue, and kept only in memory. Audio resolves just before playback through the existing persistent mpv engine. Only an explicitly unavailable/empty Mix gets one bounded artist/channel search; it is labeled as search. Throttling/login challenges suppress fallback and trigger a two-minute cooldown. Three consecutive automatic playback failures stop with a visible message; manual and Favorites errors keep explicit Retry.

Stop, loading cancellation, sleep/output interruption, and quit cancel pending transitions. Restoring the preference never starts playback or recommendations; explicitly play a song first. Disabling Autoplay preserves a currently playing song but cancels waiting continuation. Reopening a window or waking does not start audio. No cookies, login, downloads, new dependencies, or SQLite migration are required for recommendations. YouTube can change recommendations, omit artist metadata, throttle requests, or make individual videos unavailable. Playback may pause between tracks while resolving/fetching; it is not gapless. Autoplay is included in the separately staged Phase 4A V2 package.

## Phase 3B — Downloads and Offline Mode

Use the **down-arrow circle beside a song row** in Search, Favorites, History or Queue to download an authorized YouTube source. The same action shows queued/progress/cancel, a downloaded checkmark, or Retry. Open **Downloads in the sidebar** for status, title/channel, size, completed storage total, Play, **Delete Download…**, and **Clear Downloads…**. Deletion requires confirmation and preserves Favorites, History and Queue. Downloads has an empty state; failed, cancelled and interrupted jobs remain available for explicit Retry.

A single cancellable worker downloads into private staging, verifies a self-contained audio file with mpv and a SHA-256 checksum, then publishes without overwriting existing files. Incomplete files never become playable downloads. Storage is under `~/Library/Application Support/MangoMusic/Downloads`, alongside the existing SQLite library. Defaults cap each attempt at 15 minutes, each song at 512 MiB, total managed bytes at 5 GiB, and preserve 256 MiB free space. A second app instance cannot modify a folder owned by an active Downloads manager. Quit cancels active/queued jobs and flushes metadata; restart reconciles files without starting downloads or playback.

The **Offline Mode switch beneath the player controls**, next to Autoplay, persists. Changing it stops playback and cancels pending online work; press Play explicitly afterward. Offline Mode permits verified downloads only and blocks search, stream resolution, new downloads and recommendations. Online mode also prefers a valid local copy, falling back to streaming when missing/damaged. Repeat, Favorites/Shuffle, Queue, History and native media commands use the existing controller and persistent playback process. An unavailable offline queue/favorite stops with an error and keeps existing Retry/Next behavior; it is not silently skipped.

Download selection is audio-only, preferring native HLS, then M4A and other audio-only formats. AAC/M4A, Opus/WebM/Ogg, MP3, FLAC, WAV and MPEG-TS/AAC containers are admitted only after decoder validation; service availability varies. Existing staged tools passed generated HTTP WAV and audio-only HLS tests; current engine playback also passed generated M4A/WAV with kernel network denial. **No real YouTube recording was downloaded during validation.** This does not establish service-wide YouTube download reliability. Live streaming evidence and failures are recorded separately in [VALIDATION.md](VALIDATION.md).

Conversion runs only when native ffmpeg **and** ffprobe executables are verified. Standalone discovery stays inside the bundle and never assumes Homebrew; Phase 4A now bundles both version 8.0.1 tools and verifies generated-audio AAC/M4A conversion. Direct playable downloads and native HLS need no conversion helper; unsupported inputs still fail safely. Debug may use existing development tools. No global tools were installed, and the installed application/user data were untouched. Keep Debug and staged V2 data isolated: older schema-v2 builds cannot open a v3 database. Actual YouTube recording downloads remain unverified.

## Native macOS media controls

Mango Music uses MediaPlayer's MPNowPlayingInfoCenter and MPRemoteCommandCenter (available on the macOS 14 target), NSWorkspace sleep/wake notifications, and CoreAudio default-output notifications. Only title, artist/channel, known duration, actual mpv elapsed time, and rate/state are published; there is no artwork or media URL. Ordinary elapsed anchors publish at most every five seconds; metadata, state, seeks, and discontinuities update immediately. Stop, completion without an eligible next song, errors, and quit clear the metadata. Control Center rendering and Play/Pause/Next/Previous delivery are manually confirmed on this Mac. macOS may choose another Now Playing app or omit controls elsewhere; physical hardware and system seeking still need the checklist below.

Supported registered commands are Play, Pause, Toggle Play/Pause, Next, Previous, absolute playback-position seek when duration is known, and Stop. Commands and the bottom player use one capability/controller path; Next prioritizes your manual queue, then the active Favorites snapshot, then opted-in related songs. Rapid toggles preserve intent until mpv acknowledges each command. Play/Pause are idempotent; Next/Previous preserve a genuine pause. Pause while Loading cancels that attempt, including late resolution. The existing in-app shortcuts remain local to the window. No global key tap or Accessibility permission was added. Compatible keyboard/headphone/USB commands use the same macOS path, without universal-device claims.

The app registers handlers once at application scope and removes its own handlers on teardown. The owned mpv is launched with `--media-controls=no --input-media-keys=no`, so the child does not compete with Mango Music. mpv 0.41.0 is the validated version for these flags. `--stop-screensaver=no` avoids child sleep prevention. Window closure/Dock reopening do not register another integration or player. On system sleep or a changed default audio device, active playback/resolution stops, the owned audio process is terminated, and unstarted queued items are preserved. Sleep also invalidates queued commands and releases an idle owned child; wake never starts audio. Press Play explicitly to resolve a fresh stream and restart from the beginning; a small notice explains the interruption. Switching apps or display-only sleep does not invoke this stop policy. Manual/Favorites network/startup errors retain explicit Retry; automatic tracks use the bounded failure policy above.


## Standalone local app (Checkpoint 6)

The isolated packaging pipeline builds **Mango Music.app** with an arm64 application and minimal mpv, plus verified standalone yt-dlp with its own embedded Python runtime. The tested search/HLS path needs no installed Homebrew/Python/Deno or external dylibs. It targets macOS 14; runtime checks were performed on this Mac, not a macOS 14 machine. The upstream yt-dlp helper retains its universal architecture.

See [PACKAGING.md](PACKAGING.md) for pinned acquisition, offline builds, licenses, ad-hoc signing, sandbox trade-offs, and safe installation/rebuilding. Output is `.build/packaging/output/Mango Music.app`. **The user manually verified the isolated standalone app on this Mac: Finder launch without Xcode, real YouTube search and audible playback, Play/Pause/Next/Previous/volume, manual queue playback, Control Center playback controls, background playback and Dock reopening, restoration of Favorites/History/Queue/settings, and Cmd+Q stopping playback.** Earlier Debug results remain separate. macOS 14 runtime compatibility, hardware media keys/headphones, system seeking, physical sleep/wake, output changes and process-level orphan checks remain manually unverified. The earlier installation preparation in PACKAGING.md is historical; the user reports the stable Checkpoint 6 app is now installed at `/Applications/Mango Music.app`. Phase 1 leaves that bundle untouched. This is local-use packaging, without Developer ID signing, notarization, or public-distribution claims.

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
- **History:** one row per song, ordered by most recent play with a play count. A play counts only after mpv reports file-loaded and the first positive playback-clock position while playing. Selection, queuing, failed starts, pause/resume, and seeking do not add a count. Retry within the same attempt does not double-count; explicit replay after Stop/completion counts again. History defaults to Never cleanup and Unlimited entries; optional age and count limits remove older records and their counts. Individual deletion and confirmed Clear History use the same atomic persistence writer.
- **Queue:** only explicitly added entries are saved, including their independent UUIDs and exact order. Intentional duplicates remain independent. Direct play leaves upcoming entries intact. A selected queued item is recoverable until the first playback-clock event; if interrupted/failed before starting, it returns to Up Next on Stop, switching away, quit, or restoration. Started entries stay consumed. An exhausted queue resumes an active Favorites snapshot or stops. Errors never silently skip.
- **Current track:** title/artist/known duration restore in a stopped, non-streaming state at zero elapsed time. Started tracks are not re-enqueued. Pressing Play for a recovered unstarted queued selection consumes that same queue identity once; removing it from Up Next respects the removal. Playback begins only on a user action and resolves a fresh URL. Position, pause/buffering/error state, and navigation-back history are not restored.
- **Settings:** volume, sidebar visibility, repeat mode, Smart Autoplay, and History cleanup/limit policies use UserDefaults. Repeat mode accepts Off/One/All, otherwise Off. Volume restores only finite numeric values, clamped to 0–1; missing/invalid values use 0.7. Sidebar accepts stored booleans, otherwise expanded. Appearance stays system-adaptive.

Opening the app makes no YouTube requests and does not launch mpv. Startup shows Restoring and prevents library edits until a consistent snapshot loads. Read errors offer Retry while preserving existing data. SQLite work runs off the main actor, with prepared/bound SQL, atomic versioned migrations, transactions, foreign keys, and WAL. A revision check rejects stale writes from another instance. Simultaneous editing in multiple instances is unsupported; conflicts require preserving/reconciling edits rather than overwriting another instance.

Collection tables store stable YouTube IDs and minimal metadata/references/timestamps/counts. No signed streaming URLs, cookies, credentials or thumbnails are persisted. Phase 3B adds independently managed download metadata and verified audio files under Downloads. No cloud accounts, Core Data, SwiftData, AI or Mini Player were added. Phase 2B recommendations use anonymous YouTube Mix with bounded search fallback. HLS preference and playback architecture remain as documented in [YOUTUBE_PLAYBACK_DIAGNOSIS.md](YOUTUBE_PLAYBACK_DIAGNOSIS.md).

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

Checkpoint 3 held library data only in memory; data already lost by quitting that version cannot be recovered. Back up the full MangoMusic Application Support folder with the app fully closed. Do not remove SQLite sidecars while the app is running. Corrupt/unknown/newer databases are never automatically erased or recreated. Automatic repair/backup, conflict merging, database encryption and cloud sync remain outside scope; Checkpoint 6 packaging is described above. Favorites and Queue remain limited to 10,000 rows each per save. History has no fixed row cap under Unlimited; resource limits or the existing SQL deadline can produce a visible save error without silent truncation or loss of the previous committed data.
