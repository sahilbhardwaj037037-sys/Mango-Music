# Mango Music — Phase 3B Offline Downloads validation

Validation date: 29 October 2026, Asia/Kolkata. This section supersedes earlier scope/schema statements for the current implementation; earlier phase evidence below remains historical.

## Safety and implementation

Started on `main`, synchronized with `origin/main` at `5a80452e45047c1b6af6e4c654d59e0456c5529e`, with no unpushed commits. The pre-existing shared Xcode scheme has been preserved byte-for-byte (Git blob `9ca951e610568feed117ad46ec37d2097105d1e0`) and is excluded from this change's commit. It is the expected remaining working-tree modification after commit.

Implemented one-worker downloads/progress/cancel/retry, private staging and exclusive atomic publication, decoder/hash validation, managed storage budgets, independent SQLite v3 download metadata, restart reconciliation, confirmation-based Downloads deletion/clear, local-first resolution and persisted Offline Mode. Collection/session saves retain existing Favorites, History, Queue and recovery semantics. No real user database/preferences were opened by tests, no installed app was modified/launched, no new package or installation was produced, and no later phase began. Only generated owned audio was downloaded. Existing staged binaries were reused read-only.

## Automated results

- Complete suite with local mpv, native media and generated-download integrations: **157 discovered test declarations in 20 suites, passing runner result**. Three live-only declarations were disabled in this batch and exercised separately below; Swift Testing's displayed total includes disabled declarations. This adds 24 declarations to the preceding 133-test suite. Parameterized declarations include multiple cases.
- Separately enabled live regressions: **three public-video playback cases passed** (`dQw4w9WgXcQ`, `jNQXAC9IVRw`, `9bZkp7q19f0`); **YouTube search/manual queue passed**; **YouTube Mix EOF transition with persistent mpv passed**. These stream to null output; they are not audio downloads, audible UI observations, or proof of service-wide reliability.
- Xcode Debug: **BUILD SUCCEEDED**, arm64, signing disabled only for the command; derived data under ignored `.build/Phase3BDerivedData`. No application was run by the build. The ordinary AppIntents metadata-extraction warning does not affect this app. A current SDK deprecation warning for the macOS-14-compatible spawn chdir API is retained.
- Native schema-v2 → v3 migration preserves seeded Favorites, History/counts, Queue order/identities and session metadata. Independent download/library revisions do not conflict with one another; stale download revisions roll back. Version-1/newer/unknown/corrupt database regression checks remain included. Every database is temporary.
- Download fixtures cover lifecycle/progress, one worker, duplicate prevention, cancellation/late callbacks, retry, validation failure, no-overwrite publication conflicts, checksum corruption/missing files, deletion/clear preserving collections, startup interruption cleanup/no auto-resume, offline preference and no-online-call boundaries, offline Queue/Favorites/Repeat/Shuffle ordering with Autoplay enabled, quit cancellation, failed-save/quit/retry, unsafe paths/symlinks, exclusive folder ownership, budgets and restricted packaged conversion discovery.
- Real POSIX subprocess tests verify cancellation kills owned descendants and bounded timeout/admission failures. Raw yt-dlp diagnostics and signed stream references are not committed.

Commands (all outputs/data under ignored development or temporary directories):

```sh
MANGO_PACKAGED_APP="$PWD/.build/packaging/output/Mango Music.app" \
  MANGO_MPV_INTEGRATION=1 MANGO_NATIVE_MEDIA_INTEGRATION=1 \
  MANGO_DOWNLOAD_INTEGRATION=1 Scripts/check.sh
MANGO_PACKAGED_APP="$PWD/.build/packaging/output/Mango Music.app" \
  MANGO_YOUTUBE_DIAGNOSTICS=1 \
  swift test --scratch-path .build/MangoMusicPackage --cache-path .build/cache \
  --disable-xctest --filter YouTubePlaybackIntegrationTests
MANGO_PACKAGED_APP="$PWD/.build/packaging/output/Mango Music.app" \
  MANGO_MIX_INTEGRATION=1 MANGO_YOUTUBE_INTEGRATION=1 \
  swift test --scratch-path .build/MangoMusicPackage --cache-path .build/cache \
  --disable-xctest --filter 'MixAutoplayIntegrationTests|MPVIntegrationTests.youtubeManualQueue'
xcodebuild -project MangoMusic.xcodeproj -scheme MangoMusic \
  -configuration Debug -destination 'platform=macOS,arch=arm64' \
  -derivedDataPath .build/Phase3BDerivedData CODE_SIGNING_ALLOWED=NO build
```

Compiler/plugin execution, localhost servers and native integration use the approved execution environment. Logs: `.build/phase3b-final-tests.log`, `phase3b-live.log`, `phase3b-live-mix-queue.log`, `phase3b-xcode.log`.

An earlier combined batch with all live/source tests enabled failed: generated-download and public streaming timeouts, a Mix deadline, and a timing-sensitive History expiry assertion. No single all-live batch is claimed to pass. Fixture setup was corrected to use async waits rather than blocking the main actor; the final complete local batch and separate bounded live batches above pass. The first HLS fixture also lacked declared audio codecs and was rejected by the strict audio-only selector; a correctly declared audio-only master manifest passes. No production broadening to video downloads was used to bypass that rejection.

## Actual download/offline evidence and limitations

`DownloadIntegrationTests` serves a generated four-second PCM WAV and generated AAC HLS from localhost only. Staged yt-dlp 2026.10.21 runs with its restricted bundle PATH and no conversion executables. HTTP download bytes equal the generated WAV. Native HLS downloads audio fragments into one self-contained file; staged mpv 0.41.0 validates it after the source server stops. FFmpeg is used read-only to **generate the HLS fixture**, not on the downloader's PATH. Corrupt bytes and a remote-reference playlist fail decoder validation. The HTTP integration exercises managed publication and local playback, then ordinary HTTP streaming again in the same persistent mpv process to check per-file restrictions do not stick.

A separate ignored harness compiles the **current** engine/controller/storage sources and runs under `sandbox-exec` with `(deny network*)` except Unix-domain IPC. An IPv4 connect attempt verifies EPERM/EACCES. It plays only the existing Phase 3A generated M4A, Opus, FLAC and WAV tones: positive clocks, pause/seek/resume, one natural EOF per file, same mpv PID, graceful missing-file error, exited owned PID and removed socket directory. Output is null; this proves network-independent decoding/control, not audible output. Local commands/results remain in `.build/phase3b-research` (`run_offline_probe.py`, `offline-results.json`, `offline-formats.json`); none are staged for Git.

**No actual YouTube/HLS recording download was tested.** The generated native-HLS result is fixture evidence, separate from the real-service streaming tests. YouTube format selection, service changes, expiry, restrictions and throttling may still make a download fail. There is no cookie/login/DRM bypass and no automatic retry loop. Available title/channel metadata comes from the selected Song; duration is validated locally. Channel is not verified artist attribution; thumbnails are not downloaded.

Admitted extensions are M4A/MP4, Opus/Ogg/WebM, MP3/AAC, FLAC, WAV and TS; only positively decoded, audio-only self-contained containers become complete. Actual current-engine offline format evidence is M4A/AAC, Ogg Opus, FLAC and PCM WAV; generated HLS supplies AAC in MPEG-TS bytes (yt-dlp may name the file `.mp4`). Other codec/container combinations remain decoder/service dependent. A positive start and checksum are not a full-duration corruption scan.

Standalone conversion requires verified native ffmpeg and ffprobe executables in the bundle. The existing staged app does not provide these; direct playable downloads need no conversion and unsupported containers fail cleanly. Debug can discover existing development helpers. No new conversion tools were installed or bundled. Budgets are 512 MiB/attempt, 5 GiB actual managed bytes, 256 MiB free reserve, 15-minute attempt deadline, 10-second decoder probe, maximum six-hour known duration; disk checks are sampled, not filesystem quotas. Interrupted downloads restart fresh only on explicit Retry. Completed storage shown in the UI excludes incomplete/failed leftovers, but admission counts disk bytes. Full hash checks can delay startup/local resolution for large files. Offline missing favorites/queue entries stop with error/Retry/Next rather than automatically skipping.

Schema v3 is an additive forward migration. Older v2 builds refuse a v3 database safely; do not point the installed older app at the isolated Debug database. User-performed GUI/audible/download/Control Center checks for Phase 3B are pending; earlier manual phase passes do not cover new Downloads behavior.

## Manual Phase 3B checklist — isolated Xcode Debug only

1. Quit the installed app normally. Open the project in Xcode, select MangoMusic / My Mac / Debug. Retain the existing scheme's isolated HOME and CFFIXED_USER_HOME at `/Users/sahilbhardwaj/Developer/MangoMusic/.build/phase1-manual-home`. Run the Debug product with Cmd+R. Never change these to the real home. Confirm no playback/download starts on launch.
2. Search for content you have permission to download. Use the down-arrow circle beside a song. Confirm queued/progress/cancel and Downloaded states. Repeat the action: no duplicate. Check Downloads sidebar title/channel, file size, completed total and empty state. A real source failure should show a useful error and explicit Retry; it must not appear completed.
3. Cancel an active/queued job; confirm no completed item and no later unexpected playback. Retry explicitly. Quit during a transfer and relaunch; verify recoverable cancelled/interrupted state without automatic restart. Existing helper tests cover owned subprocess cleanup independently.
4. Play a completed download online, then enable Offline Mode next to Autoplay. It stops current playback; press Play. Confirm audible local playback, pause/resume/seek/volume, Repeat One/All, Favorites Play All/Shuffle and manual Queue priority. If desired, disconnect the network on this test Mac and confirm playback still works. Restore connectivity afterward. Missing online-only selections must fail clearly, without Mix/search. Turning Offline Mode off must not auto-start playback or downloads.
5. In Downloads select Delete Download… and Cancel, then confirm deletion. Test Clear Downloads… both ways. Favorites, History and Queue must remain. Deleting the currently playing local download stops it. Check total storage updates. Use only the isolated Debug library for missing/corrupt-file experiments.
6. Quit/relaunch: verify Downloads and Offline Mode persist, no automatic playback/downloads, and existing Favorites/History/Queue settings survive. Exercise Control Center Play/Pause/Next/Previous, closing/reopening the window, background playback and Cmd+Q. Hardware media controls and actual macOS 14 runtime remain manual checks; no package/install is part of this phase.

---

# Mango Music — Checkpoint 7, Phase 2B validation

28 October 2026, Asia/Kolkata. Started at `db4ce09d4dbf8ab66ff7a83f54af9fc7a95026b4` on main; a fresh fetch confirmed zero commits ahead/behind. The complete ignored Phase 2A report was read before editing. The pre-existing shared scheme modification (blob `9ca951e610568feed117ad46ec37d2097105d1e0`) is preserved and excluded from this implementation commit. It remains the sole expected uncommitted change after finalization.

## Phase 2B automated results

- **133 tests passed in 16 suites**, with all opt-in integration declarations enabled, no skips/failures. Existing 106 tests plus 27 Phase 2B test declarations; parameterized tests additionally exercise multiple variants.
- Swift package Debug build, Xcode project plist validation, and shared scheme XML validation passed via `Scripts/check.sh`.
- Xcode Debug: **BUILD SUCCEEDED**, using `.build/Phase2BDerivedData`; command-line signing disabled without modifying the checked-in signing/security settings. No app was launched or installed by this build.
- Provider fixtures cover validated URL construction/arguments, capped/deduplicated metadata parsing, missing artist/duration, unavailable/private/live entries, malformed/null/wrong-Mix responses, one search fallback with distinct provenance, cache re-filtering, transport/parse errors without fallback, and throttling/auth cooldown suppressing new subprocess calls.
- Coordinator fixtures cover default Off/strict preference persistence, no startup helper/network, EOF versus manual Next, duplicate/stale events, queue/Favorites/Repeat priority, continuation after detours, paused and delayed Next, toggling Off/On, empty/failing providers, three automatic stream failures, manual errors retaining Retry, and late data after Stop, interruption, shutdown, quit, direct selection, Previous, or cancelled loading.
- A specific reviewed race is covered: manual Next while recommendation prefetch is pending now stops old audio/cancels prior resolution through the serialized playback task chain. Late old player events cannot restore the old UI or trigger extra transitions.
- Temporary SQLite round trips verify Favorites, queue UUID/order, selected-song metadata and History survive automatic playback/quit; persisted Autoplay On restores without any player or recommendation call. Schema v2 and LibrarySnapshot remain unchanged. No real user SQLite or preferences are used.
- Existing local mpv IPC, native media API/lifecycle, History management/migrations/conflict/rollback, search and playback regression suites passed.

The final full command was:

```sh
MANGO_MPV_INTEGRATION=1 MANGO_NATIVE_MEDIA_INTEGRATION=1 \
MANGO_YOUTUBE_INTEGRATION=1 MANGO_YOUTUBE_DIAGNOSTICS=1 \
MANGO_MIX_INTEGRATION=1 Scripts/check.sh
xcodebuild -project MangoMusic.xcodeproj -scheme MangoMusic \
  -configuration Debug -destination 'platform=macOS,arch=arm64' \
  -derivedDataPath .build/Phase2BDerivedData CODE_SIGNING_ALLOWED=NO build
```

Compiler/plugin execution used the established approved execution mode outside the restrictive tool sandbox. All project build outputs remain under ignored `.build`. An initial test build required a private test helper access-level correction. Final implementation/test/documentation diffs and whitespace were reviewed before commit.

## Bounded live Phase 2B evidence

`MixAutoplayIntegrationTests.liveMixSelectionAndPersistentMPV` uses the production YouTubeMixProvider/MusicLibrary/AudioStreamResolver/MPVPlaybackEngine path, isolated UserDefaults and no production database. It explicitly opts in, loads public seed `dQw4w9WgXcQ`, waits for actual audio position and one capped 20-entry Mix request, then seeks near the end so real mpv EOF automatically selects a non-seed Mix candidate. The candidate must show a positive playback clock, `.mix` provenance, an empty manual queue, and the same owned mpv PID. Stop/connection teardown follow. The final live check passed using existing development tools and null audio output. This establishes one real natural transition, not universal recommendation relevance, a live fallback failure, audible output, or a human UI observation. Fallback/throttling behavior is deterministic fixture coverage; no deliberate rate-limit stress was performed.

The separate existing live checks also passed: YouTube search/manual queue and three canonical public-video playback cases. No signed stream URLs/raw diagnostics/audio files were committed. Phase 2A's staged bundled-helper/restricted-PATH research is distinct from this Debug integration; no new standalone package was built or installed.

## User-performed Phase 2B manual results

The user reports completing all six manual tests below successfully in Xcode for implementation commit `5b5e6dd30a6ce4721fc78829cfcbee66b88bf9bd`. These are user-performed manual observations, separate from the 133 automated tests and null-output integration checks above. Codex did not perform or infer these GUI results.

| Manual test | User-reported result |
| --- | --- |
| Autoplay switch and persistence | PASS |
| YouTube Mix automatic playback | PASS |
| Manual Queue priority | PASS |
| Favorites priority | PASS |
| Repeat compatibility | PASS |
| Stop and Next behavior | PASS |

This report confirms these six checks only. It does not independently establish VoiceOver, hardware controls, physical sleep/output changes, background-window behavior, process cleanup, live fallback/throttling, or universal YouTube availability. No tests or builds were rerun for this documentation-only finalization. Production sources, the installed application, real user data, and the pre-existing shared scheme edits were unchanged.

## Manual Xcode verification checklist

The six user-reported passes above complete the reported Phase 2B manual tests. The broader checklist below is retained for future regression testing; items outside that report remain unverified.


1. Quit the installed Mango Music normally. Open `/Users/sahilbhardwaj/Developer/MangoMusic/MangoMusic.xcodeproj`; select **MangoMusic → My Mac**, **Run → Debug**. Retain the existing isolated `HOME` and `CFFIXED_USER_HOME` values `/Users/sahilbhardwaj/Developer/MangoMusic/.build/phase1-manual-home` under Edit Scheme → Run → Arguments. Keep these local scheme edits uncommitted. Press **Cmd+R** to run the Debug product, not the installed bundle.
2. Find the **Autoplay** switch beneath the transport/volume row. Verify initial Off, keyboard/VoiceOver labels/help, and persistence after quit/relaunch. Relaunch must remain stopped even with Autoplay On; enabling the switch while stopped must not start playback.
3. Explicitly play a public music track, enable Autoplay, and let it finish (or seek near the end after audio starts). Verify a non-seed song follows with a **YouTube Mix** label. Related search fallback is labeled **Related search** if naturally encountered; do not fabricate failures using real user data or credentials. Test fixtures cover fallback independently.
4. During Favorites Play All, insert manual queue songs: they play first, then the next favorite, then radio after the finite playlist ends under Repeat Off. Repeat One repeats naturally but manual Next bypasses it. Repeat All wraps Favorites before radio and never recreates consumed queue entries.
5. Pause and use Next; the next selection must stay paused, including delayed recommendations. Press Next during Finding related songs: old audio must stop while waiting. Add a queued song while waiting: it should start with priority. Exercise rapid Next/Previous and switch changes without duplicate transitions.
6. Turn Autoplay Off during an automatic song: current playback continues and no further automatic song starts. Stop or cancel loading/waiting: no late automatic playback. Stop followed by toggling On must stay stopped until explicit Play. Quit while loading/finding and relaunch: no autoplay or restored recommendation buffer.
7. Confirm Control Center commands, window-close/background continuation, Dock reopening, volume/seek, Favorites/History/Queue persistence, History delete/clear/policies, and responsive layout. Sleep/output changes must stop and require explicit Play; wake alone never resumes. Hardware and VoiceOver checks remain manual.

## Known limits and safety

Mix/Radio is anonymous and service-dependent, with changing membership and incomplete artist metadata. Flat entries may become unavailable between discovery and resolution; IDs are deduplicated, but alternate uploads of the same recording can have different IDs. Channel/uploader is a display fallback, not verified performer attribution. Missing JavaScript runtime requirements for some YouTube formats remain an existing runtime limitation; no cookies, account access or dependencies were added.

Each provider process is capped at 30 seconds; one fallback can make the pair approach 60 seconds. Gaps while fetching/resolving are possible. Cache/buffer live only in the session; provider throttling suppresses requests for 120 seconds, other errors for 30 seconds, with no scheduled retry. After three consecutive automatic playback failures the user must choose a song or Retry; explicit manual/Favorites playback never silently skips errors. Previous starts a fresh recommendation context when returning to an earlier selection, while its Favorites cursor follows existing behavior.

`/Applications/Mango Music.app`, real user data, global tools, signing and security configuration are untouched. No packaging, installation, release, audio downloads or Phase 3 work occurred. The six user-performed Phase 2B passes above are separate evidence from automated checks; broader audible/background/hardware checks are not inferred from that report. The user-performed Phase 1.5 results below also remain separate evidence.

---

# Mango Music — Phase 1.5 History Management validation

Phase 1 GitHub finalization completed first: a fresh fetch and live remote check confirmed local/main and origin/main at `78651ce18aaa0f4fa0f35dc36c8f20443d90e49f`, with zero commits ahead/behind and the Phase 1 commit present on origin/main. No redundant Phase 1 commit was created. The user reports Phase 1 manual playback testing passed, including repeat modes, Favorites Play All/Shuffle, queue priority, and playlist continuation.

A pre-existing shared Xcode scheme modification supplies isolated manual-test HOME/CFFIXED_USER_HOME settings and Xcode formatting/TestAction changes. It was preserved byte-for-byte and excluded from Phase 1.5 commits. The final Git status must report this existing local modification rather than claim a clean working tree or discard user work.

## Phase 1.5 results — 28 October 2026, Asia/Kolkata

- Full suite: **106 tests passed in 13 suites**, all opt-in integrations enabled, no skipped declarations. This includes local mpv, native media registration/lifecycle, live YouTube search/manual queue, and three public-video playback cases.
- Swift package Debug build and project plist/shared-scheme XML validation passed through `Scripts/check.sh`.
- Xcode Debug: **BUILD SUCCEEDED**, with project-local `.build/Phase15DerivedData` and command-line signing disabled; no checked-in signing/security configuration change.
- New `HistoryManagementTests`: individual UUID deletion and durability; clear request/cancel/confirm and empty-state behavior; all three age policies and cutoff boundary; cleanup on startup and scheduled idle expiry; 100/500 newest-first limits and later playback; default Unlimited beyond the old SQLite guard (10,002 persisted rows); valid/invalid preference restoration; preservation of Favorites, Queue, playlist, current playback and session metadata; failed-save visibility/retry.
- Existing playback, repeat, playlist, system media, persistence/migration/corruption/conflict, and background-lifecycle regressions all passed. All database/settings tests use temporary SQLite files and unique UserDefaults suites.
- Complete implementation/test/documentation diff and whitespace reviewed before commit. The initial test run exposed submicrosecond timestamp precision differences in fixture equality after SQLite conversion; deterministic whole-second fixtures and identity comparisons correct those assertions.

Commands:

```sh
MANGO_MPV_INTEGRATION=1 MANGO_NATIVE_MEDIA_INTEGRATION=1 \
MANGO_YOUTUBE_INTEGRATION=1 MANGO_YOUTUBE_DIAGNOSTICS=1 Scripts/check.sh
xcodebuild -project MangoMusic.xcodeproj -scheme MangoMusic \
  -configuration Debug -destination 'platform=macOS,arch=arm64' \
  -derivedDataPath .build/Phase15DerivedData CODE_SIGNING_ALLOWED=NO build
```

## User-performed Phase 1.5 manual results

The user reports that all five tests below passed in Xcode for Phase 1.5 implementation commit `e1e7a487a5b31b225ce2521da47c5c78d78ea13e`. These are user-performed manual observations, separate from the automated results above; Codex did not perform or infer these GUI checks.

| Manual test | User-reported result |
| --- | --- |
| Individual History Delete | PASS |
| Clear History / Cancel | PASS |
| Clear History / Confirm | PASS |
| Auto-cleanup Settings and Persistence | PASS |
| History Limits and Persistence | PASS |

This report confirms these five checks only. It does not independently establish VoiceOver, narrow-window layout, elapsed-day expiry, background-window behavior, audible output, device controls, or process cleanup. No tests/builds were rerun for this documentation-only finalization. The installed app, real user data, and pre-existing shared scheme edits were not changed.

## Phase 1.5 manual testing

Use the isolated Xcode launch instructions in the Phase 1 section below; the pre-existing local scheme already points both HOME and CFFIXED_USER_HOME to `.build/phase1-manual-home`. Quit the installed app normally first. Keep both environment variables enabled, select MangoMusic → My Mac → Debug, and Cmd+R. Never run manual tests against the real user library.

1. Play several test songs, open History, right-click one and choose Delete from History. Verify only that record disappears immediately and stays removed after relaunch. Also try selecting a row and pressing Delete. Delete the currently playing record and verify audio and playlist progression continue.
2. Click Clear History… and choose Cancel: entries stay. Repeat and choose Clear: entries disappear; Favorites/Queue remain and audio continues. An empty History disables Clear while retaining both policy pickers.
3. Change Auto-cleanup through Never/7/30/90 days and Keep through Unlimited/100/500 songs. Quit/relaunch to verify selections persist. Automated fixtures cover old dates and large collections; do not change the system clock or real database to fabricate manual cases. Choosing stricter policies immediately removes eligible older test rows; loosening them cannot restore deleted entries.
4. Verify keyboard navigation, VoiceOver labels, confirmation dismissal/Cancel/Clear, narrow-window controls, background playback/window reopening, and Control Center controls. Recheck repeat/Favorites/queue behavior and no autoplay on relaunch.

The five user-performed History checks above now pass; additional accessibility, audible, and other checklist items not included in that report remain manually unverified. Unlimited retains all rows subject to system resources and the existing SQL deadline; save errors retain the prior committed database and show Retry. Cleanup uses elapsed 24-hour days since the most recent play and runs on reopening after the app was closed. No app was launched for testing by this implementation, no real user data was opened/modified, `/Applications/Mango Music.app` was untouched, and no packaging/install/release or Phase 2 work was performed.

---

# Mango Music — Checkpoint 7, Phase 1 validation

28 October 2026, Asia/Kolkata. Initial `main` was clean at `ab0af495627e1c7f92f78715a8118cebd5807e2f`; a fresh fetch confirmed HEAD and origin/main matched before edits. Phase 1 changes only the coordinator, two views, tests, and documentation. No SQLite migration, dependency, packaging, signing, installed app, or user-data change is part of this work. Checkpoint 6 evidence below is historical; the user now reports the stable app is installed at `/Applications/Mango Music.app`, which this phase leaves untouched.

## Phase 1 automated validation

Final result: **97 tests passed in 12 suites**, all opt-in declarations enabled, including all three public-video cases; no skips or failures. Swift Debug package build, plist/XML checks, and **Xcode Debug BUILD SUCCEEDED**. The complete source/test/documentation diff and whitespace checks were reviewed before commit. Tests used existing development helpers; bundled-runtime discovery and packaging sources remain unchanged.

- `Scripts/check.sh`: Swift Debug package build, full Swift Testing suite, project plist and shared-scheme XML validation.
- Full opt-in run uses `MANGO_MPV_INTEGRATION=1 MANGO_NATIVE_MEDIA_INTEGRATION=1 MANGO_YOUTUBE_INTEGRATION=1 MANGO_YOUTUBE_DIAGNOSTICS=1 Scripts/check.sh`. Test stores/settings are isolated; playback uses null output. No real library or preferences are opened for testing.
- `PlaylistTests` covers Off/One/All, natural EOF, duplicate/stale events, manual Next under One, Play All, Shuffle snapshot membership/order, empty/single/removed favorites, queue priority/resumption, repeat preference restoration, resolution/player failure without automatic retries, and cancellation races.
- `SystemMediaTests` additionally checks playlist-aware Next/Previous, preservation of pause, metadata and command availability, and repeated app/window attachment without duplicate registration. Existing background delivery, lifecycle, interruptions, persistence, and queue recovery regressions remain in the full suite.
- `MPVIntegrationTests.localAudioIPC` now drives real EOF through One, a remote manual Next into the queue, queue-to-playlist resumption, All wraparound, and Off exhaustion. It verifies that consumed manual entries do not loop and the same mpv PID serves the transitions. Generated silent WAV and temporary SQLite remain isolated.
- Live checks cover real YouTube search/manual queue and three canonical public videos. They establish stream/IPC regression behavior, not audible sound or a human Control Center observation. Phase 1 Favorites/repeat with real YouTube remains in the manual checklist below.
- Debug Xcode command: `xcodebuild -project MangoMusic.xcodeproj -scheme MangoMusic -configuration Debug -destination 'platform=macOS,arch=arm64' -derivedDataPath .build/Phase1DerivedData CODE_SIGNING_ALLOWED=NO build`.

Compiler macro plugins cannot run inside the initial restrictive execution sandbox. Checks use approved execution outside that sandbox with project-local staging; no project security or signing settings were changed. A new media test initially compared whole Song values against a fixture with a different duration; assertions now compare stable IDs, allowing the existing observed-duration update.

## Launch Phase 1 in Xcode with isolated data

1. Quit the installed Mango Music normally. Leave `/Applications/Mango Music.app` in place.
2. In Terminal, run:

   ```sh
   cd /Users/sahilbhardwaj/Developer/MangoMusic
   mkdir -p .build/phase1-manual-home
   chmod 700 .build/phase1-manual-home
   open MangoMusic.xcodeproj
   ```

3. Select **MangoMusic → My Mac**. In **Product → Scheme → Edit Scheme → Run → Info**, select **Debug** and the built **MangoMusic.app** executable. Do not select the installed application.
4. In **Run → Arguments → Environment Variables**, enable both `HOME` and `CFFIXED_USER_HOME`, each with the absolute value `/Users/sahilbhardwaj/Developer/MangoMusic/.build/phase1-manual-home`. This uses the same isolated-home approach as the existing launch probe, preserving the real SQLite/preferences. These local scheme settings should stay uncommitted. Leave signing/build settings unchanged.
5. Press **Cmd+R**. Start with the isolated empty Favorites; search and heart a few songs to create test data. The built executable should be under Xcode's Debug products, not `/Applications`. Tests run through SwiftPM; the Xcode scheme has no Test action.

## Phase 1 manual checklist and limits

- Empty Favorites: Play All/Shuffle disabled. Add one favorite, then several; verify Play All order and Shuffle's fixed session order, current-row highlight, keyboard focus, help/VoiceOver repeat labels, and narrow-window layout.
- Off: natural completion advances through Favorites and stops at the end. One: natural completion restarts the song; manual Next/Previous still navigate. All: final favorite returns to the first; a one-song snapshot repeats.
- While favorite A plays, add X and Play Next Y. Natural completion should play Y, X, then favorite B; All must never recreate X/Y. Queue reorder/remove/clear and explicit queued selections should still work. Removing a future favorite skips it; adding a favorite waits for the next Play All/Shuffle.
- Unavailable favorite: error remains visible without retry loops. Retry resolves again; Next bypasses it. Repeat modes never auto-retry a failure. Unstarted failed manual selections retain the earlier queue recovery policy.
- Use Control Center Play/Pause/Next/Previous during Favorites playback, including One and paused navigation. Close the window; let the playlist advance, use media commands, then reopen from Dock. Physical media keys/headphones and visual Control Center delivery still require human checks.
- Quit normally, relaunch from Xcode with the same isolated home, and verify repeat preference and test Favorites/History/Queue restore without autoplay. The playlist snapshot itself intentionally does not survive relaunch. Verify sound and owned-helper cleanup on Cmd+Q.

No human Phase 1 GUI, audible, VoiceOver, device, sleep/wake, or background-window checks have been claimed. There is no Phase 1 packaging, installer, installation, release, recommendation autoplay, or download implementation. The installed stable app and existing user data remain unchanged.

---

# Historical Checkpoint 6 validation

25 October 2026, Asia/Kolkata. Checkpoint 6 packages a local Release app; previous Debug manual confirmations are archived verbatim in [VALIDATION_CHECKPOINT5.md](VALIDATION_CHECKPOINT5.md). The subsequent user-reported standalone results below establish the listed manual checks for the isolated Release package on this Mac; they are separate from those earlier Debug results. Earlier persistence and HLS evidence remains in VALIDATION_CHECKPOINT4.md and YOUTUBE_PLAYBACK_DIAGNOSIS.md.

## Baseline and scope

The initial branch was `main`, with clean index/working tree at `62ba9d823c509f4f45b9b7e084ebd92be0ed880f`. Tracking and live origin/main matched. PACKAGING.md was then added as an uncommitted audit. The user explicitly approved Option 1: an isolated minimal audio-focused helper source build plus verified upstream standalone yt-dlp. No global Homebrew/Python tools or system installations were changed. No installed application was replaced. No /Applications installation, public release, notarization, DMG, or PKG was performed.

## Packaging configuration

- Native application and mpv: arm64; target and Mach-O declared minimum remain macOS 14.0. Standalone yt-dlp is the verified upstream universal executable containing arm64; all 103 embedded native runtime files were checked for arm64, minimum OS and library resolution. Their highest declared arm64 minimum is macOS 11. Actual runtime validation is on this Mac, not a macOS 14 machine.
- mpv 0.41.0, FFmpeg 8.0.1; minimal static link with system CoreAudio and SecureTransport TLS. Required libass/libplacebo remain linked with optional GPU/video/script features disabled. The same checksum-pinned upstream CoreAudio hotplug initialization fix used by the installed development mpv is applied. No external non-system mpv dylibs remain.
- yt-dlp 2026.10.21 matches its GitHub release asset digest and SHA2-256SUMS. Its embedded Python 3.14, certificates, SSL/curl and native modules were inspected. No installed Python or Deno is used by the tested search/HLS path. Future YouTube behavior or videos requiring a JavaScript runtime remain a limitation.
- `MangoBundledTools=true` selects app-relative helpers and fails rather than falling back to global tools. Packaged subprocess PATH contains only the bundle helper directory and system /usr/bin:/bin. Process argument arrays, HLS-first selection, persistent JSON IPC, queue, schema v2, preferences and media adapters are retained. The minimal helper has no scripting options, so only packaged launches omit the two scripting-only opt-out flags; development flags remain intact.
- The packaging command overrides Release `ENABLE_APP_SANDBOX=NO`, enabling the existing subprocess/Unix IPC/data architecture without sandbox inheritance changes. The signed result has no App Sandbox entitlement. It runs with the user's permissions, with less filesystem/network confinement than a sandboxed app. SIP, Gatekeeper and other macOS protections are unchanged. Ordinary Xcode Debug and Release project settings remain unchanged; stock sandboxed Release is not the packaged configuration. No App Store claim is made.
- Ad-hoc signing only: no valid local signing identity was available. Helpers/main executable are signed before the final app; signature and deep bundle verification pass. Embedded yt-dlp native payload entries remain byte-for-byte equal to the verified upstream archive after outer signing. No Developer ID or notarization claim.

## Automated results

Final clean recipe and validation results:

| Check | Result |
| --- | --- |
| Existing Scripts/check.sh | Passed; 87 discovered declarations, five opt-in declarations skipped |
| All Swift tests with local/native/live integrations enabled | **87 tests passed in 11 suites**, no skips; three public-video cases plus live search/manual queue |
| Package validator regression fixtures | **4 passed**: rejects missing helper, missing execution permission, newer deployment target and tampered signature |
| Xcode Debug | **BUILD SUCCEEDED**, original development configuration preserved |
| Packaged Xcode Release | **BUILD SUCCEEDED**, arm64/macOS 14 with explicit unsandboxed packaging override |
| Clean helper rebuild from pinned cached source archives | Passed, including recorded upstream CoreAudio patch |
| Bundle/signatures/embedded runtime | Passed; 103 embedded yt-dlp native files inspected, upstream payload preserved |
| Restricted-PATH live CoreAudio helper smoke | Passed: bundled executable PID paths, clock, pause/resume, seek dispatch, volume and owned PID/harness socket cleanup |
| Isolated Launch Services app startup and normal quit | Passed without Xcode; bundle path matched and isolated data home used; no playback in this launch probe |
| Package size | **47.37 MiB** logical file total, including helpers/resources/notices; mpv approximately 7.7 MiB |

The first minimal helper test exposed unsupported scripting-only launch flags, fixed by omitting them only for the scripting-disabled packaged build. An early standalone smoke asserted mpv itself removes the socket pathname; the corrected probe verifies harness cleanup, while the production local test verifies Mango Music removes its owned directory. Final combined tests and clean packaging pass after these corrections.

Commands use only project-local build staging and caches:

```sh
python3 Scripts/Packaging/prepare.py --acquire  # explicit pinned HTTPS acquisition only when needed
.build/packaging/tools/bin/python Scripts/Packaging/package.py  # no downloads
Scripts/check.sh
MANGO_PACKAGED_APP="$PWD/.build/packaging/output/Mango Music.app" \
  MANGO_MPV_INTEGRATION=1 MANGO_NATIVE_MEDIA_INTEGRATION=1 \
  swift test --scratch-path .build/MangoMusicPackage --cache-path .build/cache --disable-xctest
MANGO_PACKAGED_APP="$PWD/.build/packaging/output/Mango Music.app" \
  MANGO_YOUTUBE_INTEGRATION=1 MANGO_YOUTUBE_DIAGNOSTICS=1 \
  swift test --scratch-path .build/MangoMusicPackage --cache-path .build/cache --disable-xctest \
  --filter 'YouTubePlaybackIntegrationTests|MPVIntegrationTests.youtubeManualQueue'
python3 Scripts/Packaging/smoke.py '.build/packaging/output/Mango Music.app' --live --audio
.build/packaging/tools/bin/python Scripts/Packaging/test_validation.py '.build/packaging/output/Mango Music.app'
```

The Swift tests cover bundled discovery and missing/non-executable/script/symlink handling, restricted packaged PATH, compile-time scripting differences, existing search argument safety, persistence/restoration and no autoplay, controls, lifecycle ownership, local audio with persistent IPC, queue completion, native MediaPlayer registration/readback and listener cleanup. Live tests use the packaged search/resolution/player helpers with three public videos, position/duration, pause/resume, seek/volume, and manual queue advancement. Signed URLs and raw media diagnostics are not logged. Live tests use null output and do not establish audible sound.

The separate CoreAudio helper probe checks the actual selected output, progressing clock, pause/resume, seek dispatch and volume readback, bundled executable paths through proc_pidpath, owned PID exit and harness socket cleanup. mpv alone leaves its socket pathname; Mango Music's existing process owner removes its private directory. The production-path local test separately checks owned socket-directory removal and owned process exit on interruption. It does not prove an app-level Cmd+Q during audible Release playback.

Launch Services opens the actual isolated bundle with a restricted PATH and isolated HOME/CFFIXED_USER_HOME, confirms its bundle URL/process remains running, then requests normal application termination. This is an automated no-Xcode launch/quit probe, without playback; it is not a human Finder, Dock, icon or Control Center confirmation.

## User-reported standalone manual verification

The user personally launched the isolated `.build/packaging/output/Mango Music.app` from Finder without Xcode and reported all nine checks passed for the Checkpoint 6 package implemented in commit `cef93c6c7a994113ddbd85bd5bc7ed290eb1345b`:

| Check | Manual result |
| --- | --- |
| Finder launch without Xcode | Passed |
| Real YouTube search | Passed |
| Audible music playback | Passed |
| Play/Pause, Next, Previous and volume | Passed |
| Manual queue playback | Passed |
| macOS Control Center playback controls | Passed |
| Background playback after window close and Dock reopening | Passed |
| Favorites, History, Queue and settings after quit/relaunch | Restored successfully |
| Cmd+Q | Cleanly stops playback |

These are human observations of the isolated standalone app on this Mac, not results inferred from builds, null output or API readback. The report confirms Control Center playback controls as reported; it does not separately enumerate each system command. It does not separately confirm in-app seeking, icon appearance, automatic queue advancement, no autoplay after relaunch, or process/socket inspection. Cmd+Q stopping playback is not a process-level orphan check. Prior automated coverage of these paths remains separate. No tests or builds were rerun for this documentation-only follow-up.

### Remaining unverified or out of scope

- Runtime compatibility on an actual macOS 14 system; deployment/linkage declarations alone are insufficient.
- Physical Mac keyboard media keys and Bluetooth headphone controls.
- System-level seeking from Control Center, physical sleep/wake and audio output device changes.
- Process-level confirmation of no orphaned mpv/helper processes or IPC sockets after manually quitting the actual app.
- Other device/surface compatibility remains platform-dependent.
- Public redistribution compliance, Developer ID signing and notarization remain incomplete or outside scope.

## Installation preparation — no installation performed

A read-only follow-up inspection found no matching Mango Music application in `/Applications` or `~/Applications`: neither `Mango Music.app` nor `MangoMusic.app` exists there, and no immediate `.app` bundle with the Mango Music name or bundle identifier `com.localmusic.MangoMusic` was found. The isolated source app and existing `~/Library/Application Support/MangoMusic/library.sqlite3` are present. The source app's deep/strict code-signature verification passes. This is a point-in-time check; repeat it immediately before any approved copy, including checking for symlinks.

The proposed destination is `/Applications/Mango Music.app`. Installation is pending separate user approval. [PACKAGING.md](PACKAGING.md) records the exact plan: quit all copies, back up the complete Application Support folder and preferences outside Git, revalidate the source, refuse an occupied destination, copy without changing the bundle identifier/data path, verify the copied bundle and its actual launch path, and test playback/restoration/quit from the installed location. No app, database or preferences were copied, replaced or altered during this documentation update. Verification of the installed copy remains pending; isolated-app passes do not substitute for it.

## Publication and limits

This is local-use packaging with third-party notices and pinned source/build manifests. Private local building is supported; public redistribution compliance, Developer ID and notarization are not complete or in scope. Runtime testing on macOS 14 hardware is still needed despite compatible deployment declarations. Existing user data stays at ~/Library/Application Support/MangoMusic/library.sqlite3 with unchanged preferences and bundle identifier.

The final staged review must contain only source/tests/scripts/docs, no app/helper binaries, source tarballs, caches, personal databases/history, credentials, signed URLs, cookies or signing material. Only after successful automated validation may the requested commit `Package Mango Music as a standalone macOS app` be pushed normally to existing origin/main. The final response records its hash and live remote match; no history rewrite is authorized.


## Documentation-only follow-up

This follow-up changes only VALIDATION.md, README.md and PACKAGING.md. Playback code, tests, build configuration, existing user data and the verified app artifact are unchanged. The user authorized committing and pushing this documentation update to existing origin/main. Installation/replacement in /Applications still requires separate approval. No DMG, public release or global tool changes are included.
