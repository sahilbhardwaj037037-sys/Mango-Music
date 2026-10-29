# Mango Music 2.0.1 / Build 202 — routine save-label flicker

29 October 2026, Asia/Kolkata. The user confirms that **Build 201 fixed the original Repeat One/All window shaking**. This successor addresses only the remaining routine saving-text flicker. **Save-label fix: IMPLEMENTED / AWAITING MANUAL VISUAL VERIFICATION.** No Build 202 GUI was launched or visually approved by this work.

## Cause and presentation-only fix

`MusicLibrary.beginPlayback` schedules a session save; the first positive playback clock records History and schedules another. A changed duration can also schedule metadata persistence. `scheduleSave` marks `hasUnsavedChanges` true, and the asynchronous writer clears it after the current edit revision commits. These are legitimate persistence operations. Build 201's `SaveStatusView.message` immediately mapped every flag change to visible/hidden text, exposing short save cycles even though its 22-point reserved region prevented layout movement. This is the strongest code-based explanation of the reported label flicker; no frame trace is claimed.

Only `MangoMusic/Views/MainWindow.swift` changes production presentation:

- `SaveStatusPresentation` waits **800 ms of continuous saving** before showing a label. Finishing a quick save invalidates that pending display.
- A long save displays the stable, generic **“Saving changes…”**, avoiding text changes when the library/Downloads writer mix changes.
- Once visible, the label hides after **one idle second**. A new save during that grace keeps it visible, bridging short gaps between writes. It may linger briefly after a commit; it is a courtesy status, not an authoritative database-commit confirmation.
- Errors or restoration immediately suppress/reset ordinary status. Existing error/restoration banners, keyboard-accessible native Retry buttons and all write/flush/quit behavior remain intact.
- View-bound task cancellation, generation guards and disappearance reset prevent stale show/hide callbacks. Already-cancelled tasks cannot invalidate a newer display timer.
- The reserved **22-point height** is unchanged. Hidden text remains excluded from accessibility, and the status region does not intercept pointer/keyboard input.

**MusicLibrary, SQLite/persistence services, mpv EOF handling, Repeat/Shuffle/Queue/Autoplay, downloads and all appearance code are unchanged.** Native menu-bar **Appearance → System / Light / Dark** stays exactly where it is, with the same persistence, mapping and styling. No in-app selector or new preference was added.

## Versioned artifact and safety

App: `/Users/sahilbhardwaj/Developer/MangoMusic/.build/v2-2.0.1-202/output/Mango Music.app`

Version remains **2.0.1**; build increments **201 → 202** in the app plist, which supplies both Xcode and package metadata. **56,887,823 logical bytes / 54.25 MiB**. arm64, declared minimum macOS 14.0, established unsandboxed private ad-hoc-signing recipe. Fresh Release staging/DerivedData are separate from earlier releases. The final rebuild followed an additional cancelled-task guard; its earlier validation artifact/log are retained separately under this new work directory.

Build 201 (`.build/v2-2.0.1-201/output/Mango Music.app`), Build 200 (`.build/phase4a/output/Mango Music.app`), the installed V1 app and real data/preferences are preserved. No generated binaries/media/private inventories are committed. The shared scheme remains byte-identical at Git blob `9ca951e610568feed117ad46ec37d2097105d1e0` and is excluded from the commit. No installation, Phase 4B or Android work occurred.

Final read-only before/after hashes, sizes and modification times match for both earlier release bundles, the installed V1 bundle and real MangoMusic data/preferences. No staged app/helper remains running; unrelated Homebrew mpv processes were left untouched. The new manual HOME has not been created because the GUI launcher was not run.

## Automated and package validation

| Check | Evidence |
| --- | --- |
| Focused regressions | **40 tests / 4 suites passed**, including eight save-status tests plus Repeat, History and download-manager coverage |
| Presentation tests | Controlled sleep gates verify repeated quick saves remain hidden, 800 ms display/one-second idle grace, gap bridging, error/disappearance reset, cancellation races, generic label and unchanged offscreen native-hosted geometry; no GUI window |
| Complete local suite with new bundled tools | **170 discovered declarations / 22 suites, passing runner result**; three live-only declarations gated for separate runs. Swift Testing totals include disabled declarations; parameterized declarations have additional cases. |
| Separate bounded live regressions | Three public-video streaming cases passed; real search/manual queue and a natural Mix transition passed with staged helpers and null output. No single combined all-live/full-suite pass is claimed. |
| Swift build / project plist / shared scheme XML | Passed via Scripts/check.sh |
| Fresh Xcode Release | **BUILD SUCCEEDED** |
| Bundle validation | Signatures, executable permissions, arm64/macOS-minimum declarations, library/rpath layout and **103 embedded yt-dlp native files** passed |
| Package rejection fixtures | **6 passed**, including missing/non-executable helper and conversion-tool rejection |
| Packaged mpv smoke | Generated local audio clock, pause/resume, seek dispatch, volume, owned process exit and harness socket cleanup passed with null output |
| Bundled yt-dlp/FFmpeg/ffprobe | Generated WAV download/extraction passed with system-only PATH and isolated HOME; yt-dlp reported exact bundled ffmpeg/ffprobe executable paths, produced AAC/M4A, and bundled mpv decoded after localhost stopped |
| GUI launch / visual verification | **Not performed**; protected launcher compiled only |

Runtime pins remain **yt-dlp 2026.10.21**, **mpv 0.41.0**, **ffmpeg/ffprobe 8.0.1**. Package/generated-audio helper checks are distinct from a GUI or audible human observation. No Homebrew/global runtime fallback or dependency acquisition was added. Existing actual-YouTube-recording-download provenance, runtime/device, unsupported-format and private-signing limitations remain.

Ignored logs/artifacts live under `.build/v2-2.0.1-202`, including `focused-tests-final.log`, `full-tests-final.log`, `package.log`, `logs/xcode-release.log`, `validator-tests.log`, `mpv-smoke.log`, `conversion-smoke.log`, `live-playback.log`, `live-mix-queue.log`, launcher compile log and private protected-file/artifact hashes. Earlier intermediate test/build evidence is preserved separately. Automated timing/layout checks establish the intended suppression policy; only the user can confirm that the distracting text flicker is gone in the packaged GUI.

## Protected manual launch — user action only

Quit other Mango Music instances first. The compiled launcher was **not executed**. It targets the exact staged executable, requires project `.build` paths, supplies isolated HOME/CFFIXED_USER_HOME and restricted PATH, denies writes to `/Applications` and the real home outside the isolated HOME, and denies reads of the real library/preferences file. OS-delegated services are not covered by an absolute process-only guarantee; retain before/after protected-file comparisons for manual evidence.

```sh
cd /Users/sahilbhardwaj/Developer/MangoMusic &&
  .build/v2-2.0.1-202/isolated-launch-probe \
    "$PWD/.build/v2-2.0.1-202/output/Mango Music.app" \
    "$PWD/.build/v2-2.0.1-202/manual-home" --manual
```

This fresh manual HOME keeps Application Support, SQLite, Downloads and preferences separate from Build 201 and real data. Keep Terminal running, quit with Cmd+Q and rerun the same command for persistence checks. Do not launch this bundle through Finder, `open` or an old Dock shortcut against the real home.

## Manual retest still required

1. Let multiple tracks reach natural EOF under Repeat One and Repeat All, online and downloaded/offline. Quick automatic saves should remain invisible; content must stay stationary. Include History/Queue screens and queued detours.
2. If a genuinely slow save occurs, confirm one stable “Saving changes…” label appears and settles without rapid flashing. Do not modify the real database or system permissions to induce slowness/failure.
3. Confirm Favorites, History counts, Queue and Downloads survive normal quit/relaunch. Existing save errors must still show the real error and usable Retry. Never infer durability solely from the courtesy label.
4. Confirm ordinary playback, controls, download cancel/retry and quit remain correct. Verify Appearance remains in the native menu bar and that no in-app selector appeared; modes/styling were not changed.

Record the **save-label** fix as visually verified only after user confirmation. The original window-shaking fix is already user-confirmed; no broad visual-defect-free claim is made.
