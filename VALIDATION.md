# Mango Music — Checkpoint 6 validation

25 October 2026, Asia/Kolkata. Checkpoint 6 packages a local Release app; previous Debug manual confirmations are archived verbatim in [VALIDATION_CHECKPOINT5.md](VALIDATION_CHECKPOINT5.md). Those results do not establish manual verification of the packaged Release app. Earlier persistence and HLS evidence remains in VALIDATION_CHECKPOINT4.md and YOUTUBE_PLAYBACK_DIAGNOSIS.md.

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

## Manual verification still needed for this package

No new human manual pass is claimed. From the isolated output bundle, confirm Finder double-click, correct visible icon, audible YouTube search/playback, all player controls including Previous, seeking and volume, explicit queue completion, window-close/background playback, Dock reopening, and Control Center rendering/Play/Pause/Next/Previous. Quit/relaunch and verify Favorites/History/Queue/preferences restore without autoplay. Verify Cmd+Q while music is playing stops sound and inspect the application-owned helpers/sockets.

The previous six unverified hardware/system checks remain unverified: physical Mac keyboard media keys, Bluetooth headphone controls, Control Center seeking, physical sleep/wake, audio output changes, and process-level no-orphan confirmation after manually quitting the actual app. Helper-level automated process checks do not relabel that final item as manually passed. Other devices and system surfaces remain platform-dependent.

## Publication and limits

This is local-use packaging with third-party notices and pinned source/build manifests. Private local building is supported; public redistribution compliance, Developer ID and notarization are not complete or in scope. Runtime testing on macOS 14 hardware is still needed despite compatible deployment declarations. Existing user data stays at ~/Library/Application Support/MangoMusic/library.sqlite3 with unchanged preferences and bundle identifier.

The final staged review must contain only source/tests/scripts/docs, no app/helper binaries, source tarballs, caches, personal databases/history, credentials, signed URLs, cookies or signing material. Only after successful automated validation may the requested commit `Package Mango Music as a standalone macOS app` be pushed normally to existing origin/main. The final response records its hash and live remote match; no history rewrite is authorized.
