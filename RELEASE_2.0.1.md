# Mango Music 2.0.1 / Build 201 — isolated visual and appearance retest

Subsequent user finding: the original Repeat One/All window shaking is **confirmed fixed in Build 201**. Remaining routine saving-text flicker is addressed separately in [Build 202](RELEASE_BUILD_202.md), awaiting manual visual verification. This document preserves Build 201's release-time evidence and artifact; appearance/menu behavior is unchanged by Build 202.

29 October 2026, Asia/Kolkata. Successor test build to the preserved Phase 4A **2.0/build 200** package. No installation, Phase 4B, Android development or automatic app GUI launch is part of this work. The installed V1, real user data/preferences and the pre-existing shared scheme remain protected. Build 200's 30 manual passes, zero failures and one media-key skip are historical evidence, not new Build 201 results.

## Changes and verification boundary

- **VIS-01: FIX IMPLEMENTED / AWAITING MANUAL VERIFICATION.** `MainWindow` uses one permanently reserved 22-point status line for ordinary library/Downloads saves; idle, either writer and simultaneous writers have identical geometry. Restoration/error banners and Retry remain intact. Idle status is hidden from accessibility and the status line does not intercept input. No persistence operations, EOF handling, controller, Queue priority, Repeat, Shuffle or Autoplay semantics changed.
- **Appearance: IMPLEMENTED / AWAITING MANUAL VERIFICATION.** Native menu bar **Appearance → System / Light / Dark**, persisted by `@AppStorage("appearanceMode")`, default/fallback System. Window-level native appearance preference uses nil/light/dark; System leaves appearance to macOS. Changing this UI setting does not create a new MusicLibrary or register another media integration. No database migration or new preference domain.
- All seven audited explicit hue uses now use shared theme roles. Dark preserves the original pink/green and repeat fill. Light uses darker pink/green accents; the rest remains native semantic styling. Automated contrast checks passed at least 4.5:1 for highlighted text and 3:1 for completion icons against native Aqua/Dark Aqua window, control and text backgrounds. Translucent materials, selected rows, dialogs, disabled states, high-contrast settings and actual display rendering still require manual review.

The save-region geometry tests support the proposed layout fix but do not establish that the original observed repeat flicker is fully resolved. No automated result is a substitute for a user-confirmed visual retest. No new GUI, audible, window, Control Center or appearance interaction pass is claimed.

## Artifact and versioning

App: `/Users/sahilbhardwaj/Developer/MangoMusic/.build/v2-2.0.1-201/output/Mango Music.app`

Version **2.0.1**, build **201**; identifier `com.localmusic.MangoMusic`; **56,863,471 logical file bytes / 54.23 MiB**. arm64, declared minimum macOS 14.0. The checked-in app Info.plist is now the single source of version/build for Xcode and packaging; packaging no longer hardcodes 2.0/200. The new Release uses fresh DerivedData under this versioned directory and retains the established explicit unsandboxed packaging override and private ad-hoc signing.

Preserved baseline: `.build/phase4a/output/Mango Music.app`, **2.0/build 200**. The new work directory, output, manual HOME and launcher do not replace its artifacts or test data. No generated binaries/media/private inventories are committed.

Final read-only hash/size/modification-time inventories match for the installed V1 bundle, real MangoMusic Application Support/preferences and the Build 200 app. The shared scheme remains byte-identical at Git blob `9ca951e610568feed117ad46ec37d2097105d1e0` and is excluded from commits. No staged app or helper remains running; unrelated Homebrew mpv processes were left alone.

## Automated, fixture and helper evidence

| Validation | Result |
| --- | --- |
| VIS-01 focused regressions | **34 tests / 4 suites passed**, including offscreen native-hosted geometry and existing Repeat, History and download-manager tests |
| Appearance + save-status tests | **6 tests / 2 suites passed**: enum mapping, isolated AppStorage persistence/fallback, native-surface contrast, original dark colors, fixed status geometry/messages |
| Full local suite against new bundle | Passing runner result: **164 discovered declarations / 22 suites**; three live-only declarations gated for separate bounded runs. Displayed Swift Testing totals include disabled declarations; parameterized tests have additional cases. |
| Separate bounded live streaming | Three public-video cases passed; real search/manual queue and one natural Mix EOF transition passed with the new staged helpers, persistent mpv and null audio. No single combined all-live/full-suite batch is claimed. |
| Swift build / project plist / shared scheme XML | Passed via Scripts/check.sh |
| Fresh packaged Xcode Release | **BUILD SUCCEEDED** |
| Bundle integrity | Passed architecture/minimum/linkage/permissions/signatures; **103 embedded yt-dlp native files** inspected |
| Package rejection fixtures | **6 passed**, including missing/non-executable conversion-tool rejection |
| mpv helper smoke | Generated-audio clock, pause/resume, seek dispatch, volume and owned PID/socket cleanup passed; null audio |
| Generated download/convert | HTTP WAV, native AAC HLS without download-path FFmpeg, production AIFF→AAC/M4A conversion passed with bundled tools |
| Exact conversion dependency paths | Generated WAV → bundled yt-dlp → exact bundled ffprobe/ffmpeg → AAC/M4A → bundled mpv passed with system-only PATH and temporary HOME; localhost stopped before decode |
| Network-denied current-engine probe | Generated M4A/AAC, Ogg Opus, FLAC and PCM WAV clocks/control/EOF, same mpv PID, missing-file handling and owned PID/socket cleanup passed under kernel network denial except Unix IPC |
| App GUI launch / quit / appearance interaction | **Not run**, as requested; protected launcher compiled only |

The first full local batch, run alongside helper smoke/compile workloads, hit the 30-second test deadlines in all three generated-download fixtures. With concurrent external workloads finished, the full batch passed unchanged in 15.529 seconds. No production/test deadline was increased and no playback behavior changed. Resource contention is a possible factor, not a proven diagnosis; the failed log is retained. This is distinct from VIS-01 and is not presented as initial success.

Dependencies remain **yt-dlp 2026.10.21, mpv 0.41.0, ffmpeg/ffprobe 8.0.1**, built/verified from the same pinned cache. mpv and conversion tools link only to macOS system libraries; yt-dlp retains its embedded runtime and verified upstream payload. Tested paths do not depend on Homebrew, installed Python or developer shell PATH. No new dependencies were acquired or installed.

Private ignored evidence is under `.build/v2-2.0.1-201`: `vis01-tests.log`, `appearance-tests.log`, `full-tests.log` (initial failure), `full-tests-final.log`, `package.log`, `logs/xcode-release.log`, `validator-tests.log`, `mpv-smoke.log`, `conversion-smoke.log`, `offline-results.json`, `live-playback.log`, `live-mix-queue.log`, launcher compile log, artifact hashes and protected-file inventories. Live streaming is separate evidence from generated downloads; actual YouTube recording-download provenance remains unverified.

## Protected manual launch — run by the user only

The launcher is compiled from `Scripts/Packaging/IsolatedLaunchProbe.swift` but was **not executed**. It requires project `.build` paths, refuses another Mango Music instance, launches the exact supplied staged executable, sets HOME/CFFIXED_USER_HOME and restricted PATH, blocks writes to `/Applications` and the real home outside the isolated HOME, and denies reading the real library/preferences file. macOS-delegated services remain outside a universal process-only isolation guarantee; retain protected-file comparisons when gathering manual evidence.

```sh
cd /Users/sahilbhardwaj/Developer/MangoMusic &&
  .build/v2-2.0.1-201/isolated-launch-probe \
    "$PWD/.build/v2-2.0.1-201/output/Mango Music.app" \
    "$PWD/.build/v2-2.0.1-201/manual-home" --manual
```

The new manual HOME will hold `Library/Application Support/MangoMusic/library.sqlite3`, its independent `Downloads` directory, and isolated preferences via CFFIXED_USER_HOME. Keep Terminal running; quit with Cmd+Q. Rerun the same command for persistence testing. Do not use Finder, `open` or an existing Dock shortcut to launch the staged app against the real home. Keep V1 closed. The existing rollback/backup/migration plan in [UPGRADE.md](UPGRADE.md) remains a deferred Phase 4B plan only.

## Required manual retest

1. **VIS-01:** Repeat One and single/multiple-track Repeat All through natural EOF, online and downloaded/offline. Watch the content/sidebar/player at transition and first playback clock. Repeat on Search, Favorites, History, Queue and Downloads screens at narrow/wide sizes. Mark fixed only if the shaking is gone; report any remaining toolbar/player jitter separately.
2. **Saving/error behavior:** Saving status must not move content; Favorites/History/Queue/Downloads still persist. Verify accessible status and native Retry behavior when an isolated save error is encountered. Never induce errors by modifying the real library.
3. **Appearance:** Select each menu option, verify selection state and relaunch persistence. In System, change macOS appearance manually and verify the app follows; explicitly test Light→System and Dark→System. Check titlebar, sidebar, playback bar, search, all collection/download screens, native selection, hover, dialogs and disabled/progress/error states. Confirm the dark design remains familiar and highlighted text/icons remain readable.
4. **No functional regression:** Theme changes must not stop/restart audio, alter selection/queue order, trigger downloads or duplicate media commands. Recheck audible streaming/local playback, pause/seek/volume, queue priority, Shuffle/Repeat/Autoplay, download cancel/retry/delete confirmation and Offline Mode.
5. **Lifecycle:** Relaunch preferences/library without autoplay; Control Center, background/window-close/reopen and clean Cmd+Q. Keyboard/headphone media keys remain previously skipped until tested. Only reopen the running V2 instance; do not launch V1 through an old shortcut.

Remaining limits include unverified new GUI behavior, actual macOS 14 runtime, device-specific controls, actual YouTube recording-download provenance, unsupported codec/service cases, and private ad-hoc signing without notarization/public redistribution readiness. No Phase 4B installation or actual-data migration was performed.
