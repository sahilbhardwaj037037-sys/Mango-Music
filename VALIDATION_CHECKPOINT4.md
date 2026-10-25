> Archived Checkpoint 4 report from commit ce37903. Its unverified manual status describes that earlier report; in the Checkpoint 5 request the user subsequently confirmed Favorites, History, Queue and preferences survive restart without autoplay. Current media integration evidence is in [VALIDATION.md](VALIDATION.md).

# Mango Music — Checkpoint 4 validation

25 October 2026, Asia/Kolkata.

**Automated persistence/restoration and playback checks pass, the native Debug build passes, and the existing project validation script passes. Manual visual/audible SQLite restoration is not verified.** The user explicitly authorized commit/push if automated validation succeeds and no serious data-loss/migration issue remains. The final report supplies the resulting commit/remote verification; this file does not embed its own commit hash.

## Git safety before development

- Existing project: `~/Developer/MangoMusic`; branch `main`; clean working tree.
- Existing origin: `https://github.com/sahilbhardwaj037037-sys/Mango-Music.git`.
- Baseline HEAD: `1dd40b2d10d8f4e3bf5587ad7f6b1def7ca3e3ee` (completed Checkpoint 3).
- A fresh `git fetch origin` and `git rev-list --left-right --count main...origin/main` returned `0 0`. No preliminary push was needed.
- No unrelated changes were present. Existing commits, source, branding/icon, and repository were preserved; no reset, force-push, or history rewrite was used.

Implementation was initially compiled/tested in an isolated temporary staging copy, then applied to the still-clean existing project. Final checks below ran from the actual repository. Database tests never open the user's real music database. All test models use isolated UserDefaults; the app alone explicitly injects the production database location.

## Implemented and reviewed

`LibraryPersisting`/`LibrarySnapshot` define an injectable async boundary. `SQLiteLibraryStore` serializes SQLite3 off the main actor, binds values through prepared statements, finalizes statements, enables foreign keys/WAL/FULL synchronization, validates loaded data, uses transaction/revision checks, and closes resources. Failed migrations/writes roll back. Corruption, unknown/future schemas, read-only/locked databases, and stale writers produce fixed recoverable errors, without automatic deletion/recreation or raw diagnostic logging.

The schema is version 2. A fresh database creates the internal v1 schema and upgrades transactionally; v1 → v2 adds a default play count and recent-history index without losing existing rows. Future/unrecognized schemas are refused. Version 1 is an internal migration fixture/baseline, not a database shipped in Checkpoint 3. See [ARCHITECTURE.md](ARCHITECTURE.md) for table/column details and the complete queue/history rules.

Debug storage: `~/Library/Application Support/MangoMusic/library.sqlite3` plus SQLite `-wal`/`-shm` sidecars when needed. New directory/file permissions are 0700/0600. The Application Support API also respects sandboxed container locations. No expiring URLs, cookies, credentials, artwork, or media files are persisted. The Release sandbox setting is unchanged and external-tool Release playback remains unsupported.

Favorites persist one song/date-added pair per song. History aggregates one row per song, with latest timestamp/count and a retention limit of 100 distinct songs. A count requires file-loaded plus a positive playback-clock position while playing; failed starts, pause/resume, seek, and same-attempt Retry do not add a count. Explicit replay after Stop/completion is a new play. Queue entry UUIDs preserve intentional duplicates/order. Current unstarted queued selections have a durable recovery reference; recovery preserves them once, and explicit removal/clearing is respected. Started current entries stay consumed; restored current metadata is stopped at zero, without network/player startup.

UserDefaults persist volume/sidebar. Volume validates type/finiteness, clamps to 0–1, and falls back to 0.7. Sidebar validates booleans and falls back to expanded; appearance stays system-adaptive. A save banner/error distinguishes optimistic UI changes from durable saving. Cmd+Q uses AppKit's asynchronous termination handshake: flush latest edits, then terminate mpv/close SQLite. Failed flush cancels quit and preserves edits; no-op quit does not attempt an unnecessary write. Lock waits are bounded and long SQL work is interrupted, though an OS/filesystem stall cannot be strictly bounded.

## Final automated checks

Run from `~/Developer/MangoMusic`:

```sh
MANGO_MPV_INTEGRATION=1 swift test
```

**63 test declarations passed; the two network-only declarations were skipped.** Swift Testing's summary includes skipped declarations and reports “65 tests … passed” across nine suites (1.680 seconds). Parameterized tests include additional cases. Zero failures. This includes real local mpv decoding/control/queue events together with a temporary SQLite save/flush/close/reopen check.

```sh
./Scripts/check.sh
```

**Passed:** Swift package build, offline test suite, `plutil` project lint, and shared-scheme XML validation. The ordinary offline suite has 62 passing declarations and three opt-in integration declarations skipped (65 declarations total). It makes no network calls. The Xcode app scheme still has no separate Test action; tests run through SwiftPM.

A separate optional live run kept network checks outside the offline suite:

```sh
MANGO_YOUTUBE_INTEGRATION=1 MANGO_YOUTUBE_DIAGNOSTICS=1 \
  swift test --filter 'MPVIntegrationTests.youtubeManualQueue|YouTubePlaybackIntegrationTests'
```

**2 declarations passed, zero failures/skips (13.597 seconds):** three canonical public videos exercised real HLS load/clock/duration, pause/resume, observed volume, seek, and Stop; the search-based manually populated queue exercised streamed EOF/advancement/exhaustion. History now correctly aggregates repeated plays into one row with an increased count. The live checks ran before the final no-op-quit optimization; that optimization was then covered by the complete offline/local suite and final Debug/script reruns. The HLS resolver/IPC engine themselves are unchanged by Checkpoint 4. All automated audio uses null output; no new audible claim is made.

### Coverage added

- Fresh database, directory creation, reopening, unknown duration/Unicode/quoted SQL-bound metadata.
- Schema versioning/v1 upgrade, retained rows/count initialization, future version refusal, unknown schemas, and failed-migration rollback.
- Favorite/queue constraints, deduplication, atomic rollback, invalid IDs, and unreferenced metadata cleanup.
- History ordering/count round trips; no selection/file-loaded-only/failed-start count; no double count on Retry/pause/seek; explicit replay count.
- Queue identity, intentional duplicates, exact ordering, removal/clear, real restart, pending recovery, no duplicate recovery, and respecting recovered-item removal.
- Real started queued items stay consumed; stopped current metadata restores with no player load/resolution; duplicate EOF cannot advance twice.
- Settings restoration, invalid/non-finite/boolean volume, bounds, sidebar type validation.
- Corrupt bytes preserved, read-only write failures, invalid paths, locked-database timeout/retry, stale-writer conflict, close/reuse rejection.
- Rapid edits, edits during an in-flight save, immediate quit flushing, visible save/load failure, successful Retry, cancelled quit preserving resources/edits, and quitting without unnecessary writes.
- Existing search, HLS-format, IPC, cancellation, local audio, and playback regression tests retained; fixtures now emit a real-start clock event and live History assertions use aggregated counts.

## Native build

```sh
xcodebuild -project MangoMusic.xcodeproj -scheme MangoMusic \
  -configuration Debug -destination 'platform=macOS,arch=arm64' \
  -derivedDataPath /tmp/MangoMusic-Checkpoint4-Final CODE_SIGNING_ALLOWED=NO build
```

**BUILD SUCCEEDED**, including a rerun after the final quit-path fix. This verifies native Debug compilation/linking with system SQLite3, not distribution signing or Release external-tool compatibility. The environment remains Swift 6.4/Xcode 27.1, mpv 0.41.0, selected Homebrew yt-dlp 2026.10.21. No new dependency or macOS security change was made.

## Manual status and exact acceptance instructions

**Checkpoint 4's visual/audible two-relaunch test was not performed.** Automated temporary-database restart tests do not substitute for that check. No production database was seeded with test songs, and the real app was not launched against personal data as an automated test.

The user previously confirmed audible YouTube playback, Play/Pause/volume, manual additions/Next/automatic advancement, History, uninterrupted window closure, Dock reopening, and Cmd+Q stopping audio at Checkpoint 3. Those results remain historical; they do not claim verification of the new persistence behavior. Seeking and Previous were not separately manually confirmed.

1. Stop any older Xcode run/other Mango Music instance. Open `MangoMusic.xcodeproj`, select MangoMusic → My Mac → Debug, and Run the latest source. Wait for Restoring to finish; do not press Play yet. Confirm no audio starts automatically.
2. Search for several public songs, press Return, and add at least three Favorites. Confirm hearts agree across Search/Favorites. Add at least three songs to Up Next, including an intentional duplicate if desired, and reorder them. Note the expected order.
3. Start one queued song and let actual audio/time begin so History is recorded. Leave at least two upcoming entries. Check History; repeated explicit plays should reuse its song row (counts are not separately shown in the UI). Change volume, for example to 25%, and collapse/expand the sidebar to a known state.
4. Cmd+Q, including immediately after an edit if desired. A normal save should finish and quit without hanging. If a library error occurs, record it; quitting should cancel while unsaved changes remain so Retry can preserve them.
5. Relaunch. Without pressing Play, verify Favorites, History recency, exact remaining queue order/duplicates, volume, and sidebar state. The current song may display stopped at zero; it must not stream/launch mpv automatically. A queued song that had started should remain consumed; one interrupted before real playback should return once to Up Next.
6. Remove a Favorite, reorder/remove an upcoming entry, then Cmd+Q and relaunch again. Verify those changes persist. There is no existing Clear History action, so none was added. Optionally Clear Queue and perform a third relaunch to confirm it stays empty.
7. Optionally interrupt a queued selection during Loading with Stop, quit/relaunch, and press Play for the recovered current item. It should consume that exact queued identity once. Explicit removal of the recovered upcoming item must not resurrect it on quit.
8. Confirm normal playback, background window closure, Dock reopening, and Cmd+Q cleanup still work in the new build. Seeking/Previous remain separately unconfirmed until you test them; do not infer manual success from automated coverage.

## Limits and data handling

- History retains 100 distinct recent songs; evicted counts are not retained. Playback position/back-navigation/search results are not restored. Current playback is never resumed automatically.
- Checkpoint 3 had only in-memory library collections; data already lost on quitting that version cannot be migrated back. Existing UserDefaults settings are reused.
- Collection writes cap at 10,000 rows each; oversized/invalid data produces an error rather than silent truncation. Large files/slow or stalled disks can require repair/recovery outside the app.
- Multiple concurrently editing instances are unsupported. Revision conflicts preserve the committed database/in-memory edits and reject overwrites; there is no automatic merge. Back up/reconcile edits before reopening a stale instance.
- On read/write error, no automatic reset or destructive repair occurs. Back up the complete Application Support folder with the app fully closed; do not delete live WAL/SHM sidecars. Automated backups, encryption, repair/export UI, and cloud sync are outside scope.
- No SQLite files, personal listening history, signed streams, credentials, build output, or caches belong in Git. All test rows are synthetic/public integration fixtures in temporary stores, never personal data.
- No Checkpoint 5, accounts, recommendations, downloads/artwork, Mini Player, media keys, AI, Core Data/SwiftData, new repository, or UI redesign was introduced.

## Files added or modified

- Added: `MangoMusic/Services/LibraryPersistence.swift`, `MangoMusic/Services/SQLiteLibraryStore.swift`, `Tests/MangoMusicTests/PersistenceTests.swift`.
- Modified production/config: `MangoMusic/App/MangoMusicApp.swift`, `MangoMusic/Models/Song.swift`, `MangoMusic/ViewModels/MusicLibrary.swift`, `MangoMusic/Views/LibraryContent.swift`, `MangoMusic/Views/MainWindow.swift`, `MangoMusic.xcodeproj/project.pbxproj`, `Package.swift`.
- Modified tests: `Tests/MangoMusicTests/PlaybackTests.swift`, `Tests/MangoMusicTests/MPVIntegrationTests.swift`, `Tests/MangoMusicTests/YouTubePlaybackIntegrationTests.swift`.
- Updated: `README.md`, `ARCHITECTURE.md`, `VALIDATION.md`.

Final publication requires a complete staged diff/security/artifact review and the exact commit message `Persist Mango Music library and queue with SQLite`, followed by a normal push to existing `origin/main`, live remote hash comparison, and a clean working tree. These were authorized in the task after successful automated validation; unperformed manual checks are disclosed rather than marked passed.
