# Mango Music V2 — Phase 4A standalone release validation

This report preserves the **2.0/build 200** baseline and its user-reported manual results. The subsequent VIS-01/appearance implementation is packaged separately as **2.0.1/build 201**; see [RELEASE_2.0.1.md](RELEASE_2.0.1.md). Build 200 remains unchanged. The successor's VIS-01 status is **FIX IMPLEMENTED / AWAITING MANUAL VERIFICATION**; appearance is implemented but has no new GUI pass yet.

29 October 2026, Asia/Kolkata. Started on `main` at finalized Phase 3B commit `15eb38487dac03f8faae146ec2bbef1f4f8594ec`; fresh fetch/live remote verification matched `origin/main`. The existing shared Xcode scheme remains uncommitted and byte-for-byte preserved (Git blob `9ca951e610568feed117ad46ec37d2097105d1e0`).

## Artifact and scope

- Final app: `/Users/sahilbhardwaj/Developer/MangoMusic/.build/phase4a/output/Mango Music.app`.
- Version **2.0**, build **200**, identifier `com.localmusic.MangoMusic`; arm64, declared minimum macOS 14.0.
- Logical file total: **56,772,637 bytes / 54.14 MiB**, including runtime dependencies, resources, signatures and notices. This is not allocated disk space or a compressed installer size.
- Xcode **Release BUILD SUCCEEDED**. The recipe retains the existing explicit `ENABLE_APP_SANDBOX=NO` packaging override and ad-hoc signing; ordinary checked-in Xcode signing/sandbox settings remain unchanged. This is a private local package, not a Developer ID/notarized/public release.
- Includes the current Search/streaming, Favorites, History, Queue, Repeat, Shuffle, Autoplay, Downloads/Offline Mode, native-media and background-lifecycle implementation. No production Swift behavior was changed in this phase.
- Old development package outputs are preserved. The first Phase 4A artifact is retained as `Mango Music-validation-1.app`; the final rebuild incorporates the updated conversion-tool license notice. All four helper binaries remain byte-identical and the application executable's `__TEXT,__text` section is identical; the resource seal changes its signature.

The installed `/Applications/Mango Music.app` was inspected read-only and never executed, replaced or installed over. The real library/preferences were inventoried read-only, not opened through the app, migrated or copied into a test. No Android or Phase 4B work occurred. No binaries, downloaded media, raw signed URLs, personal databases or private hash inventories belong in the commit.

## Dependencies and runtime evidence

| Component | Version | Validation |
| --- | --- | --- |
| yt-dlp | 2026.10.21 official universal executable | Pinned upstream cache verified; embedded payload unchanged by signing; version, generated downloads, live search/resolution and exact executable paths tested |
| mpv | 0.41.0, pinned CoreAudio fix | Static audio-focused arm64 build; clock/control/EOF, persistent PID, network-independent local decoding and owned process/socket cleanup |
| ffmpeg and ffprobe | 8.0.1 | Separate static arm64 CLI builds from the same checksum-pinned source as mpv's FFmpeg libraries; native AAC/PCM encoding, selected audio demuxers/decoders/muxers |
| Required mpv libraries | libass 0.17.4, libplacebo 7.349.0, FreeType 2.14.1, HarfBuzz 12.2.0, FriBidi 1.0.16 | Statically linked; pinned fast_float and build-only Vulkan headers retained; full manifests/notices bundled |
| yt-dlp embedded runtime | Python 3.14 plus upstream native TLS/runtime files | **103 embedded native files** audited for arm64, compatible declared minimums, signatures and bundle-relative/system linkage |

The validator verifies native executable permissions, architecture/deployment declarations, libraries/rpaths, bundle metadata/icon assets, nested/deep signatures, no App Sandbox entitlement and absence of private/build data. mpv/ffmpeg/ffprobe require only macOS system dynamic libraries; yt-dlp extracts its embedded runtime normally. No Homebrew libraries, developer shell PATH, installed Python or external conversion executables are needed by the tested packaged paths.

`conversion_smoke.py` runs all four tools with `PATH=/usr/bin:/bin` and a temporary HOME/CFFIXED_USER_HOME. It serves a generated four-second WAV on localhost, forces yt-dlp AAC/M4A extraction with `--ffmpeg-location`, verifies diagnostics identify **both exact bundled executable paths**, and validates AAC output with bundled ffprobe. Localhost is stopped before bundled mpv decodes the result. This establishes yt-dlp conversion dependency discovery as well as execution; production still converts only otherwise unsupported audio containers.

The Swift generated-AIFF integration separately exercises the actual `YTAudioDownloadService` unsupported-container branch: bundled ffprobe validates audio-only streams, bundled ffmpeg produces M4A, the source file is removed only after conversion, and bundled mpv validates the result after the source server stops. Generated native HLS still passes with conversion disabled in the download service; its fixture is now encoded by the packaged FFmpeg rather than Homebrew.

## Automated and fixture results

| Check | Result and boundary |
| --- | --- |
| Complete local suite | Passing runner result: **158 discovered test declarations in 20 suites**; three live-only declarations gated and exercised separately below. Displayed Swift Testing totals include disabled declarations; parameterized declarations have additional cases. One new conversion declaration added to Phase 3B's 157. |
| Swift Debug build, project plist and shared scheme XML | Passed via `Scripts/check.sh` |
| Xcode packaged Release | BUILD SUCCEEDED, arm64/macOS-14 target; no installation |
| Bundle validator | Passed, including all four helpers and 103 embedded native files |
| Package rejection fixtures | **6 passed**: missing mpv, non-executable mpv, missing ffprobe, non-executable ffmpeg, newer declared minimum and damaged signature |
| Actual standalone executable | Two launch/normal-quit cycles passed, exact app PID/path, restricted PATH, schema-v3 database created/reopened under isolated HOME; no playback synthesized in this probe |
| Packaged mpv helper smoke | Generated local audio clock, pause/resume, seek dispatch, volume readback, normal exit and harness socket cleanup passed; null output |
| Download/format fixtures | Generated HTTP WAV, native audio-only HLS without conversion, and production AIFF→AAC/M4A conversion passed with staged helpers |
| Controller/storage fixtures | Favorites/History/Queue preservation, Repeat/Shuffle/Autoplay priority, one worker, progress, duplicate prevention, cancel/late callbacks, Retry, budgets, corruption/missing files, confirmation/deletion, offline policy, persistence/restart reconciliation and quit covered by the complete suite |
| Database migration | Seeded v2→v3 preserves collection/session data and independent download/library revisions; rollback/conflict/corrupt/newer-version regressions pass |
| V1 compatibility | Historical Checkpoint 6 storage code compiled in ignored staging refuses the generated v3 database with `newerSchema`; installed V1 was not launched |
| Kernel-denied offline decoding | Current production engine compiled with `OfflinePlaybackProbe.swift`: generated eight-second M4A/AAC, Ogg Opus, FLAC and PCM WAV play with network denied except Unix IPC; positive clocks, pause/seek/resume, one EOF/file, same mpv PID, graceful missing-file failure, owned PID exit/socket-directory removal |

The first local batch had one `.conflict` failure in the exclusive download-folder lease handoff test. The focused check passed, then both the complete rerun and final artifact batch passed. No root cause or production fix is claimed for that transient failure. A first dependency smoke timed out during standalone yt-dlp's 15-second version check; a bounded 60-second cold-start allowance passed. These failures are retained in ignored logs rather than presented as initial success.

## Bounded real-service streaming — separate evidence

Three canonical public-video streaming cases (`dQw4w9WgXcQ`, `jNQXAC9IVRw`, `9bZkp7q19f0`) passed on a later bounded run. Real YouTube search/manual queue and one natural YouTube Mix EOF transition also passed, using the packaged tools and the persistent production mpv engine with null audio output. The initial three-video batch timed out during resolution; a later run requested `--no-parallel` and passed. Concurrency is a possible factor, not an established root cause. No single all-live/full-suite batch is claimed.

These are stream/control checks, not audible GUI observations or audio recordings downloaded from YouTube. **No actual YouTube recording download was verified.** All completed download fixtures use generated/authorized audio. The six user-reported Phase 3B Debug manual passes remain in `VALIDATION.md` and are not relabeled as new V2 standalone observations.

## Isolated application data and protected files

`IsolatedLaunchProbe.swift` requires separate app/test-home paths under project `.build` and refuses another running Mango Music instance. It starts the **actual packaged executable without Xcode** through `sandbox-exec`, supplies HOME/CFFIXED_USER_HOME and `PATH=/usr/bin:/bin`, and verifies the database really appears under that home. A temporary kernel policy denies writes to `/Applications` and to the real home outside the isolated home, and denies reads of the real MangoMusic Application Support directory/preferences file. This is validation-only confinement; the shipping package remains unsandboxed.

Real-home Cocoa/system services remain macOS-managed; a temporary profile is not a universal isolation claim about every OS service. Before/after hashes, sizes, modification timestamps and symlink inventories of the installed app, real MangoMusic Application Support and preferences provide additional evidence that those protected files stayed unchanged. These private inventories remain under ignored `.build/phase4a`. Unrelated mpv processes were not touched. Tests use generated media, temporary SQLite files and dedicated UserDefaults suites.

## Reproduction and evidence locations

With the previously acquired verified cache, no new network acquisition is needed. The packaging command refuses an existing output; choose a fresh work directory to repeat it without overwriting an artifact.

```sh
.build/packaging/tools/bin/python Scripts/Packaging/package.py --work-dir .build/phase4a
.build/packaging/tools/bin/python Scripts/Packaging/validate.py '.build/phase4a/output/Mango Music.app'
.build/packaging/tools/bin/python Scripts/Packaging/test_validation.py '.build/phase4a/output/Mango Music.app'
python3 Scripts/Packaging/smoke.py '.build/phase4a/output/Mango Music.app'
python3 Scripts/Packaging/conversion_smoke.py '.build/phase4a/output/Mango Music.app'
MANGO_PACKAGED_APP="$PWD/.build/phase4a/output/Mango Music.app" \
  MANGO_MPV_INTEGRATION=1 MANGO_NATIVE_MEDIA_INTEGRATION=1 \
  MANGO_DOWNLOAD_INTEGRATION=1 Scripts/check.sh
MANGO_PACKAGED_APP="$PWD/.build/phase4a/output/Mango Music.app" \
  MANGO_YOUTUBE_DIAGNOSTICS=1 swift test --scratch-path .build/MangoMusicPackage \
  --cache-path .build/cache --disable-xctest --no-parallel --filter YouTubePlaybackIntegrationTests
MANGO_PACKAGED_APP="$PWD/.build/phase4a/output/Mango Music.app" \
  MANGO_MIX_INTEGRATION=1 MANGO_YOUTUBE_INTEGRATION=1 \
  swift test --scratch-path .build/MangoMusicPackage --cache-path .build/cache \
  --disable-xctest --filter 'MixAutoplayIntegrationTests|MPVIntegrationTests.youtubeManualQueue'
```

Compile `OfflinePlaybackProbe.swift` with the current `MangoMusic/{Models,Services,ViewModels}/*.swift` sources, `-parse-as-library -swift-version 6 -lsqlite3`, then run it through `sandbox-exec -f Scripts/Packaging/offline.sb` with arguments `play <bundled-mpv> <generated-eight-second-files...>`. Existing owned tone fixtures under `.build/phase3a-research/source` were reused read-only. The probe checks that a kernel-denied IPv4 connection returns EPERM/EACCES, rather than assuming a stopped local server proves offline isolation.

Ignored evidence: `.build/phase4a/package-final.log`, `logs/xcode-release.log`, `final-artifact-tests.log`, `validator-tests.log`, `smoke-local.log`, `conversion-smoke-final.log`, `final-launch.log`, `offline-results.json`, `live-playback-final.log`, `live-mix-queue.log`, `v1-reject.log`, and private `artifact.json`/protected-file inventories. Earlier failed/focused batch logs remain alongside them. Helper build logs remain under `.build/packaging/logs`. No global tools were installed or updated.

## Subsequent user-reported packaged manual results

The user reports **30 PASS, 0 FAIL, 1 SKIP** for isolated version **2.0/build 200**, with functional playback, downloads, Offline Mode, persistence and macOS integration passing. Keyboard/headphone media keys were skipped and remain unverified. These are human-reported observations, separate from automated/fixture results above; no individual 31-item transcript or specific recording-download provenance was supplied.

The user also reports brief UI shaking/flicker/glitching around EOF restart/transition in Repeat One and Repeat All, disappearing after playback resumes; repeat behavior itself remains correct. This is the **Build 200 VIS-01 defect**, despite the functional checklist's zero reported failures. A successor fix is now implemented in Build 201 and awaits manual verification; Build 200 has not been modified or visually retested. No claim of a visually defect-free app is made. See [GUI_FINDINGS.md](GUI_FINDINGS.md) for the historical investigation and current implementation status. The initial findings follow-up was documentation-only; subsequent implementation/package evidence is separate in RELEASE_2.0.1.md.

## Limits and remaining checks before installation

- The subsequent user report establishes the functional manual areas above. It does not supply an itemized transcript establishing every device/runtime scenario or a separate Finder/Launch Services test. The automated executable launch remains distinct evidence. VIS-01 remains unresolved.
- No actual YouTube recording download has been verified. Service changes, formats, expiry, throttling, restrictions and missing external JavaScript runtime can still break specific sources. No login/cookies/DRM bypass or unbounded retry was added.
- Audio conversion is available for the selected compiled inputs and AAC/M4A output; unsupported codecs/containers still fail. This does not claim complete FFmpeg format support, video support or full-duration corruption scanning.
- Actual macOS 14 runtime, keyboard/headphone controls, system seeking, sleep/wake and output-device changes remain manual/platform-dependent. Current SDK warnings for the macOS-14-compatible spawn-chdir API and ordinary AppIntents metadata extraction remain documented, without build failure.
- Ad-hoc signing, no notarization/Developer ID, unsandboxed shipping package, incomplete public redistribution/source-obligation audit; private local use only. No DMG/PKG/GitHub Release produced.

For future regression testing, use the `--manual` isolated launcher command in `PACKAGING.md`; do not double-click the staged app against the real home. The original groups below are retained as a regression checklist, not a claim that the user's report left every functional group pending. Explicitly retest repeat-transition visuals after any fix and record device-specific checks separately:

1. Launch without Xcode under the protected launcher, check window/icon, no startup playback/download and normal Cmd+Q; test Dock reopening and Finder/Launch Services in an appropriately isolated account/environment if needed.
2. Authorized search and audible playback, play/pause/seek/volume, Next/Previous, Queue priority, Favorites Play All/Shuffle, Repeat and opted-in Autoplay.
3. Generated or explicitly authorized downloads: progress, duplicate prevention, cancel/retry, completion, Delete/Clear Cancel/Confirm and collection preservation. Actual YouTube download reliability remains unverified until a specifically authorized source is tested and documented.
4. Offline Mode, verified downloaded playback with network disconnected, pause/seek/repeat/shuffle/queue, clear failure for online-only selections, and explicit restart behavior when disabling Offline Mode.
5. Quit/relaunch Downloads, Favorites/History/Queue/preferences and Offline Mode persistence; no auto-start, interrupted transfer recovery, and clean shutdown while playing/downloading.
6. Actual Control Center Play/Pause/Next/Previous, background playback after window close, reopening, hardware controls, sleep/output interruptions and owned-process/socket cleanup; test an actual macOS 14 machine where required.

The deferred app/data backup, transactional migration, compatibility and paired rollback plan is in [UPGRADE.md](UPGRADE.md). Phase 4A ends with the staged artifact and evidence; **no installation or real-data migration is authorized here**.
