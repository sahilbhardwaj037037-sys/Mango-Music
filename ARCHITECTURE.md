# Mango Music architecture — Checkpoints 1–5

## Native playback

SwiftUI observes the main-actor `MusicLibrary`. Search remains explicit/cancellable through `SongSearching` and bounded Swift `Process` execution. Playback uses `AudioStreamResolving` → `MPVPlaybackEngine` → `MPVConnection`. The audio-only selector remains `bestaudio[protocol^=m3u8]/bestaudio`, addressing the reproduced direct-stream HTTP 403 without headers, cookies, client overrides, or added dependencies. [YOUTUBE_PLAYBACK_DIAGNOSIS.md](YOUTUBE_PLAYBACK_DIAGNOSIS.md) records the Checkpoint 3 investigation.

One owned, idle audio-only mpv child is started only for playback. Its private 0700 `mkdtemp` directory contains the Unix IPC socket. Newline-framed JSON uses request IDs, observed properties, generation UUIDs, and playlist entry IDs; stale requests and duplicate EOF cannot consume extra queue entries. Startup/command/load deadlines and process termination/cleanup remain. Raw signed URLs/diagnostics are not logged; mpv disk caching and saved playback positions are disabled.

## Persistence boundary

`LibraryPersisting` exposes async load, atomic snapshot save with expected revision, and close. Sendable snapshots contain only songs, favorite dates, aggregated History, ordered queue identities, current-track metadata, a recoverable queued selection, and revision. Production explicitly injects `SQLiteLibraryStore` in the App. A model without a store is intentionally ephemeral for unit tests; tests that exercise persistence inject temporary database URLs. No test opens the user's real database or uses their UserDefaults domain.

`SQLiteLibraryStore` is an actor. Its connection/statements are created, used, finalized, and closed on that actor, away from SwiftUI. The macOS SQLite3 library is linked directly, with no ORM/third-party package. All values use prepared statements/bound parameters. SQL identifiers and control statements are static.

The Debug location is `~/Library/Application Support/MangoMusic/library.sqlite3`, resolved through the per-user Application Support API. A sandboxed build resolves its container's corresponding location. New directories/files use 0700/0600. Foreign keys are enabled, WAL and synchronous FULL are used, lock waits are bounded at 250 ms, and a progress handler interrupts long SQL operations after roughly three seconds. These bounds do not guarantee deadlines for a stalled filesystem/OS call.

## Schema and migrations

`PRAGMA user_version` is 2. Timestamps are real Unix seconds; optional durations are seconds/NULL. The in-memory identifier is `youtube:<11-character ID>`; the database stores the validated raw eleven-character ID.

| Table | Key and contents |
| --- | --- |
| `songs` | `video_id` primary key with ID check; nonempty title, artist/channel, optional bounded finite duration |
| `favorites` | `video_id` primary key/foreign key; `added_at` |
| `history` | `video_id` primary key/foreign key; unique row UUID `entry_id`, `played_at`, positive `play_count` |
| `queue` | UUID `entry_id` primary key; song foreign key; unique contiguous nonnegative `position` |
| `session` | Singleton `id=1`; optional current song; optional pending queue UUID/song pair; nonnegative `revision` |

`history_recent(played_at DESC, video_id)` supports recent-first ordering with deterministic timestamp ties. The primary/unique indexes support song references, favorite deduplication, queue identity, and position. Foreign-key/integrity checks and decoded-value validation reject broken data rather than silently dropping rows.

A fresh empty version-0 database creates the internal version-1 schema and migrates to version 2 in one transaction. Version 1 → 2 adds `play_count` with default 1 for existing History rows and the recent-history index, preserving data. Version 1 is an internal migration baseline, not a database shipped in Checkpoint 3. Schema verification runs before commit. Failed migrations roll back; future versions and unrecognized nonempty version-0 files are refused. No corruption recovery path deletes, renames, resets, or replaces the user's database automatically. Preserve a closed-app backup of the complete folder, including any sidecars.

## Serialized saves and errors

Library mutations are centralized; the view no longer directly edits the queue array. The UI updates optimistically and exposes Saving/unsaved state. One main-actor writer task captures a snapshot, awaits the store, then writes the newest snapshot if edits arrived meanwhile. Edits during an in-flight save are not lost; rapid actions coalesce. A write transaction checks the database revision, upserts referenced song metadata, replaces collection/session rows, and removes only unreferenced song metadata. All steps commit together or roll back. Known duration is retained when incoming metadata lacks it. Successful commit advances the revision; a stale instance fails instead of overwriting another instance's changes.

On failure, the last committed database and in-memory edits remain, a fixed error is visible, and Retry explicitly retries saving. The unsaved indicator only clears when the newest snapshot commits. This makes an optimistic favorite heart distinct from confirmed durable saving. Load failure disables library actions until Retry succeeds; settings remain independent. Conflict merging is intentionally unsupported. A stale-instance conflict may require external reconciliation/preserving in-memory edits before reopening; Retry does not override the revision safeguard.

## History and queue semantics

A play is counted on the first positive mpv position after file-loaded while playing. File-loaded alone, selection/queuing, or a failed start does not count. History has one row per song, stable row UUID, most recent timestamp, and accumulated count, with the latest 100 distinct songs retained. Pause/resume, seek, and Retry in the same selected attempt do not increment again. An explicit Play after Stop/completion or a new selection starts a new counting attempt. Removing an old row under retention also removes its prior count. There is no new Clear History action.

Upcoming entries have stable UUIDs, allowing intentional duplicate songs. Play Next prepends, Add appends, and reorder/remove/clear persist. Direct search playback leaves the upcoming queue intact. Selecting a queued entry removes it from upcoming and retains its UUID/song in `session` until real playback starts. A failed/interrupted unstarted selection is put back at the front when switching away/Stop/quit/restoration, with UUID deduplication; if it was already present its order is preserved. While stopped that reference allows Play to consume the same recovered entry once. Removing/clearing that recovered upcoming item clears its recovery reference. Clear Queue otherwise affects upcoming items, not an active selection.

The first qualifying position clears the recovery reference and records History atomically with the resulting queue snapshot. If a crash precedes that commit, the last committed recovery reference can replay an interrupted item rather than lose it (at-least-once recovery). Successfully started current items stay consumed after relaunch. EOF advances one explicit queued item or stops; failure stops with Retry. Duplicate/stale completion events are ignored. No recommendations or unrelated autoplay exist.

## Startup, settings, and quit

Startup restores collections and current-track metadata asynchronously, while actions are disabled. Current position is zero, playback is stopped, and no stream is resolved or mpv launched. Pressing Play is an explicit new playback attempt with a freshly resolved URL. Playback navigation-back history, transient pause/buffering/errors, and signed URLs are not saved. UserDefaults restores finite numeric volume clamped to 0–1 (invalid/missing → 0.7) and boolean sidebar state (invalid/missing → expanded). Light/Dark remains system-adaptive.

`applicationShouldTerminate` uses `.terminateLater`. The library blocks new edits, cancels search, stops playback/returns any unstarted queued selection, flushes the latest save, then terminates owned mpv, closes SQLite, and replies to AppKit. Failed flush cancels quitting, retains edits, keeps the store/player usable, and shows the recoverable error. No async write is entrusted solely to `willTerminate`; its playback cleanup remains idempotent. Normal window closure keeps the library/player alive, and the existing openWindow action handles Dock reopening.

## Evidence and limits

The database tests cover fresh/reopened/versioned/unknown/corrupt/read-only/locked files, transaction rollback, conflicts, binding/constraints, dates/counts, queue identities/order, rapid/in-flight actions, startup without player/network, flush failure, and quit/reopen. Local mpv integration additionally writes and reopens a temporary SQLite library. The user confirmed Checkpoint 4 Favorites/History/Queue/preferences restore after restart without autoplay in the Checkpoint 5 request. That does not verify new native media/hardware behavior. See [VALIDATION.md](VALIDATION.md).

Release sandbox settings are unchanged and external-tool playback remains unsupported there. No accounts, cloud/database server, Core Data/SwiftData, encryption/backup UI, persistence conflict merging, artwork, downloads, or Checkpoint 6 packaging was added. Checkpoint 5 media integration is described below.

SQLite's [transaction behavior](https://www.sqlite.org/lang_transaction.html), [user_version pragma](https://www.sqlite.org/pragma.html#pragma_user_version), and [busy timeout](https://www.sqlite.org/c3ref/busy_timeout.html) inform the implementation.

## Checkpoint 5 — one controller and native adapters

`MusicLibrary` is the authoritative main-actor controller. Its transient requested-pause intent is distinct from actual mpv-observed pause/position. Rapid toggles alternate the latest intent instead of repeatedly using a delayed acknowledgement. Explicit Play/Pause are idempotent. UI and remote command availability derive from the same capability set; seeking requires a loaded, non-ended track and known duration. Previous/Next while genuinely paused pass an initial pause into the engine before loadfile, avoiding a brief audible start. Errors are distinct from a genuine user pause, so an explicit Next after error starts the chosen queued item. Pause during resolution cancels/returns the pending item and rejects late results. None of these transient fields enters SQLite.

`SystemMediaIntegration` is owned by the application delegate, never a window/view. Repeated onAppear/attach is idempotent. It subscribes to model changes through an observation-ignored main-actor callback; closing a window does not tear it down. The public macOS adapters are `NativeSystemMediaAdapter` (MediaPlayer) and `NativePlaybackLifecycle` (NSWorkspace/CoreAudio). Protocols and pure snapshot/publication policy allow offline/hardware-free tests. The existing local Space/Return and menu shortcuts remain; there is no new global keyboard monitor or permission requirement.

MediaPlayer callbacks arrive on an unspecified executor. `MediaCommandGate` protects only enabled kinds, generation and registration epoch with a lock, copies a Sendable command payload, and schedules work on the main actor. It never sends an MPRemoteCommandEvent across actors or synchronously blocks the main queue. The model rechecks capabilities and playback generation before executing. A Next accepted for a prior track is discarded after EOF/UI advancement, preventing a second consumption. Handler return success means accepted for dispatch, not that future asynchronous IPC is guaranteed to succeed. Registration epochs reject callbacks queued before teardown/re-registration.

Seven owned target tokens implement Play/Pause/Toggle/Next/Previous/absolute Seek/Stop. Unsupported continuous seek/skip/rate/repeat/shuffle/rating/language commands are disabled. Only owned tokens are removed; no removeTarget(nil) broad removal. Capability setters are cached to avoid repeated native setter work on every position event. Actual OS command routing is subject to Now Playing app arbitration and hardware/firmware support.

## Now Playing publication and platform scope

The normalized snapshot publishes title, optional artist/duration, elapsed seconds, rate/default rate, and audio media type. It omits empty artist/unknown duration, clamps invalid time, and contains no stream URLs, artwork, IPC paths, tokens, or persistence data. Playing anchors use rate 1; paused/loading/buffering anchors use rate 0. Buffering retains the playing command/state intent while freezing extrapolated time. Loading is represented as paused/rate-zero until actual load. Stop/error/exhaustion/quit clears nowPlayingInfo and sets macOS playbackState stopped. A restored current track is not published as active media on startup.

Apple extrapolates elapsed time. Ordinary clock updates are anchored at most once per five seconds, with immediate updates on generation/title/artist/duration/phase changes, significant clock discontinuities, and mpv playback-restart seek anchors. No polling timer or synthetic player clock was added. mpv remains the source of actual position/state; command intent affects button/capability responsiveness, not fabricated elapsed time.

The installed SDK declares these MediaPlayer APIs available from macOS 10.12.2, so they fit the macOS 14 target. macOS requires explicit MPNowPlayingInfoCenter.playbackState; no iOS AVAudioSession or unavailable multi-player session API is used. No Music-library authorization, microphone capture, Accessibility permission, private MediaRemote API, or device-specific Bluetooth stack was introduced. Runtime readback on macOS 26.7.1 verifies API acceptance and handler/listener cleanup; it does not prove Control Center rendering, lock-screen UI, physical key delivery, or headphone compatibility. Some system surfaces do not expose scrubbing; absolute seek is advertised only when capable. No API newer than the macOS 14 deployment target is required.

The child mpv is started with media-controls and input-media-keys disabled to prevent a second Now Playing owner/command path. stop-screensaver is disabled as well; mpv 0.41.0 is the validated dependency. No entitlement or Debug/Release policy change was made.

## Interruptions and teardown

NSWorkspace willSleep/didWake and a CoreAudio default-output listener live at app scope. Listener/observer registration is idempotent, uses registration epochs, and is removed on teardown (native removal status is verified). Device-ID equality filters duplicate route notifications. System sleep invalidates the generation and releases an owned child even when idle, so a queued pre-sleep Play cannot become actionable again after wake. An actual default-device change stops active playback/resolution. Both interruption paths preserve pending manual entries through the existing serialized SQLite writer and terminate the owned child synchronously. The IPC cleanup task is awaited before an explicit later load. Wake only restores command capability; it never launches/resolves/resumes. Explicit Play restarts the current track with a fresh stream from the beginning. This conservative policy avoids unexpected output after headphones disconnect. Display sleep/focus changes do not stop playback, and no keep-awake assertions exist.

Ordinary pause/seek/volume/navigation reuses one persistent process. After an interruption a later explicit playback may start a replacement, after the previous child/socket cleanup; tests check actual PID exit and paused seek/reload. Network/decoder/startup failures keep the existing explicit error/Retry path and never silently skip. No automatic reconnection loop was added.

Cmd+Q still uses the SQLite flush/terminateLater handshake. Commands are disabled and metadata clears when closing; a failed flush cancels quit and re-enables applicable commands while preserving unsaved edits. On actual termination the delegate tears down media targets/output/workspace observers, clears metadata, and performs idempotent owned-player cleanup. No schema migration or changed persistence format was needed for Checkpoint 5. Prior schema/queue/privacy documentation above remains applicable.

The implementation follows Apple's [MPNowPlayingInfoCenter](https://developer.apple.com/documentation/mediaplayer/mpnowplayinginfocenter), [macOS playbackState](https://developer.apple.com/documentation/mediaplayer/mpnowplayinginfocenter/playbackstate), and [MPRemoteCommandCenter](https://developer.apple.com/documentation/mediaplayer/mpremotecommandcenter) APIs and the [mpv option reference](https://mpv.io/manual/stable/). Manual proof and test counts are recorded in [VALIDATION.md](VALIDATION.md); archived Checkpoint 4 evidence remains in [VALIDATION_CHECKPOINT4.md](VALIDATION_CHECKPOINT4.md).
