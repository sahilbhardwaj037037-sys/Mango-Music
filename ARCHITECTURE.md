# Mango Music architecture — Checkpoint 4

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

The database tests cover fresh/reopened/versioned/unknown/corrupt/read-only/locked files, transaction rollback, conflicts, binding/constraints, dates/counts, queue identities/order, rapid/in-flight actions, startup without player/network, flush failure, and quit/reopen. Local mpv integration additionally writes and reopens a temporary SQLite library. Checkpoint 4 visual/audible restoration remains unverified; Checkpoint 3 manual evidence is historical and does not imply a new acceptance check. See [VALIDATION.md](VALIDATION.md).

Release sandbox settings are unchanged and external-tool playback remains unsupported there. No accounts, cloud/database server, Core Data/SwiftData, encryption/backup UI, persistence conflict merging, artwork, downloads, new media features, or Checkpoint 5 was added.

SQLite's [transaction behavior](https://www.sqlite.org/lang_transaction.html), [user_version pragma](https://www.sqlite.org/pragma.html#pragma_user_version), and [busy timeout](https://www.sqlite.org/c3ref/busy_timeout.html) inform the implementation.
