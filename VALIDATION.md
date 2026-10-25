# Mango Music — Checkpoint 5 validation

25 October 2026, Asia/Kolkata.

**Implementation and prior automated checks pass. The user personally verified the latest Xcode build launches, plays YouTube audio audibly, appears in Control Center, and responds to Control Center Play/Pause and Next/Previous, including while the window is closed. Dock reopening and Cmd+Q stopping playback/quitting without visible errors are also manually confirmed on this Mac.** Physical keyboard media keys, Bluetooth headphone controls, system seeking, physical sleep/wake, output-device changes, and process-level orphan checks remain manually unverified. These manual results are user-reported; they are distinct from the automated API readback checks.

Previous database evidence is preserved in [VALIDATION_CHECKPOINT4.md](VALIDATION_CHECKPOINT4.md); the user's Checkpoint 5 request additionally confirms Favorites, History, Queue and preferences survive restart without autoplay. The Checkpoint 3 HLS investigation remains in [YOUTUBE_PLAYBACK_DIAGNOSIS.md](YOUTUBE_PLAYBACK_DIAGNOSIS.md). Those earlier confirmations did not establish the new media integration. The subsequent manual report below confirms Control Center Next/Previous; it does not confirm physical media keys, headphones, or system-level seeking.

## Repository safety

Before modification, `main`, working tree and index were clean at `ce37903eca9fcd201e2bf5c8ac6cb169847c30b1`. Origin remained `https://github.com/sahilbhardwaj037037-sys/Mango-Music.git`. A fresh fetch and `git rev-list --left-right --count main...origin/main` returned `0 0`; no preliminary push was necessary. No unrelated changes were present. Development was initially compiled/tested in a temporary staging copy, then applied to the still-clean existing repository. Final checks ran from `~/Developer/MangoMusic`.

## Implementation and platform review

- Installed macOS 26.7.1; Swift 6.4/Xcode 27.1; deployment target remains macOS 14. SDK headers declare the chosen MediaPlayer APIs available from macOS 10.12.2.
- `MPNowPlayingInfoCenter` publishes title, optional artist/channel/duration, actual mpv elapsed time, rate/default rate and audio media type. macOS `playbackState` is set explicitly. Stop/error/exhaustion/quit clears the metadata. Ordinary anchors are limited to one per five seconds; metadata/state/discontinuities and seek anchors publish immediately. No synthetic playback timer or artwork is introduced.
- `MPRemoteCommandCenter` registers seven owned targets: Play, Pause, Toggle, Next, Previous, absolute position seek, Stop. Availability follows the same model capabilities as the bottom controls. No continuous seek/skip/shuffle/rate/rating/language commands are advertised. No global key event tap, Accessibility permission, iOS AVAudioSession, private MediaRemote API, or hardware-specific Bluetooth implementation is used.
- Media callbacks cross an unspecified native executor through a lock-protected Sendable gate to the main actor. Playback generations and registration epochs reject stale work; handlers are registered once at app scope, retained when a window closes, and individually removed at teardown. Native command status success acknowledges accepted dispatch; asynchronous IPC can still fail through the existing error UI.
- Explicit Play/Pause are idempotent, rapid toggles use requested intent until actual mpv acknowledgements, and elapsed time remains actual. Paused navigation sets pause before loading the new file. Seek is disabled on stopped/failed/loading tracks or unknown duration. Pause during resolution cancels late playback. Next during buffering and overlapping old EOF/remote events preserve exactly-once queue transitions.
- NSWorkspace sleep/wake and CoreAudio default-output observation use application lifetime. Active playback/resolution stops on system sleep/default-output changes; owned mpv is terminated and pending manual items preserved. Wake never loads/resolves/resumes; explicit Play starts a fresh stream from the beginning. Display sleep and focus changes do not call this stop path. Real physical sleep/routing is not claimed tested.
- mpv 0.41.0 is the tested dependency. New `--media-controls=no --input-media-keys=no` flags prevent its own native control path competing with Mango Music; `--stop-screensaver=no` respects sleep. The child otherwise remains persistent for ordinary controls/navigation. An interruption permits a later replacement only after cleanup.
- SQLite schema/data policy and the conditional termination flush remain intact. Media state/URLs are not persisted; no personal music database or UserDefaults domain was used in tests. Debug/Release sandbox policies, appearance, icon, branding, and external-tool lookup/HLS selection remain unchanged.

See [ARCHITECTURE.md](ARCHITECTURE.md) for details and official API references. No packaging/signing/notarization, installer, updater, cloud/account, artwork/download, recommendation, AI, or Checkpoint 6 work was introduced.

## Final automated results

From the actual project:

```sh
MANGO_MPV_INTEGRATION=1 MANGO_NATIVE_MEDIA_INTEGRATION=1 swift test
```

**82 test declarations passed and two network-only declarations were skipped.** Swift Testing reports 84 total declarations across ten suites, including skips (1.931 seconds). Parameterized tests include additional cases. Zero failures. All prior persistence/search/playback regressions remain, with fixtures updated for initial pause and interruption protocol support.

```sh
./Scripts/check.sh
```

**Passed:** Swift package build, ordinary offline suite, project `plutil` lint, and shared-scheme XML validation. That default suite has **79 passing declarations and five opt-in declarations skipped** (84 declared total): local mpv, two native runtime checks, and two network checks. It requires no physical hardware or network. The Xcode app scheme has no separate Test action; tests run through SwiftPM.

### What these tests establish

- Metadata mapping, absent/invalid duration/artist/time, exact key set without artwork/URLs, rate/state transitions, stopped/error clearing, throttling and small-seek clock anchors.
- Play/Pause idempotence, rapid delayed toggles, absolute seeking while paused, paused Next/Previous, explicit Next after failure, buffering Next, stale command/EOF rejection and queue exhaustion exactly once.
- Pause during resolution rejecting a late result, interruption never starting audio on wake, idle-sleep invalidation of queued pre-sleep Play commands, output-change stopping, registration epochs, disabled commands, background callback delivery on the main actor, owned handler cleanup and repeated simulated window attach.
- Application delegate integration ownership/termination cleanup through an injected adapter, independent of an actual displayed window. This is a simulated lifecycle check, not a real Dock/window test.
- Temporary SQLite state survives a sleep interruption while resolving an unstarted queue item; all corruption/migration/rapid-write/flush/close/restoration regressions remain.
- Real local mpv loads initially paused, seeks while paused, retains its PID for controls, exits the captured owned PID after interruption (OS-level check), can start again explicitly, and saves/reopens a temporary SQLite queue/history. Null output does not establish audible sound.

### Actual native API checks on this configuration

`MANGO_NATIVE_MEDIA_INTEGRATION=1` enables two real, hardware-free runtime checks:

1. Instantiate the real MediaPlayer adapter, register seven targets once despite repeated activation, set/read actual command enabled flags, publish/read actual title/elapsed/playbackState, transition paused, and clear/remove targets. All assertions passed.
2. Register the real CoreAudio default-output listener, verify it is installed, remove it and check the actual removal OSStatus is success, and repeat teardown safely. All assertions passed. Physical output changes and sleep/wake are not generated by this test.

These checks go beyond compilation while avoiding unsupported UI/hardware event injection. **They do not prove Control Center presentation, system routing to this app, a visible scrubber, lock-screen behavior, physical media keys, or any headphone model.** macOS selects the Now Playing app and which controls/surfaces it exposes; another app may have focus. The subsequent user report independently confirms Control Center presentation and Play/Pause/Next/Previous delivery on this Mac. The automated checks alone did not establish those results, and neither source establishes universal system UI/device compatibility.

## Separate live YouTube results

```sh
MANGO_YOUTUBE_INTEGRATION=1 MANGO_YOUTUBE_DIAGNOSTICS=1 \
  swift test --filter 'MPVIntegrationTests.youtubeManualQueue|YouTubePlaybackIntegrationTests'
```

**Two declarations passed, zero failures/skips (13.424 seconds).** The parameterized test exercised Rick Astley `dQw4w9WgXcQ`, PSY `9bZkp7q19f0`, and Me at the zoo `jNQXAC9IVRw` through the real HLS resolver/mpv/controller, checking load, clock/duration, pause/resume, observed volume, seek and Stop. The search-based queue test verified streamed near-EOF completion, manual advancement and exhaustion. All use isolated test settings/null output; no new audible result or physical media-command delivery is claimed.

## Xcode Debug build

```sh
xcodebuild -project MangoMusic.xcodeproj -scheme MangoMusic \
  -configuration Debug -destination 'platform=macOS,arch=arm64' \
  -derivedDataPath /tmp/MangoMusic-Checkpoint5-Final CODE_SIGNING_ALLOWED=NO build
```

**BUILD SUCCEEDED.** MediaPlayer/CoreAudio are linked from the installed Apple SDK. This is a native Debug compilation/link check, not signing/notarization/distribution validation. Release keeps its existing sandbox policy and external-tool limitation.

## User-reported manual verification

The user personally tested the latest Xcode build of implementation commit `4d1701ceffeb693b1117f0b0df41c90c3b565806` on their Mac and reported:

| Check | Manual result |
| --- | --- |
| Xcode Run Current Scheme | Builds and launches successfully |
| Real YouTube music | Plays with actual audible sound |
| macOS Control Center rendering | Mango Music appears; playback controls work |
| Control Center Play/Pause | Both controls work |
| Control Center Next/Previous | Both controls work |
| Red close button | Closing the window does not interrupt playback |
| Control Center with window closed | Continues controlling playback |
| Dock reopening | Restores the window; playback remains functional |
| Cmd+Q | Stops playback and quits without visible errors |

These observations confirm Control Center rendering and the reported remote playback commands on this Mac. The report does not separately establish exact title/channel/duration/elapsed-time accuracy, rapid-toggle behavior, system Stop/Toggle/seek delivery, metadata clearing after quit, physical media-key/headphone delivery, actual sleep/routing, or process/socket inspection. In particular, audible termination without visible errors is not process-level proof that no owned mpv remains. The prior automated results above are retained; no tests or build were rerun for this documentation-only update.

### Remaining manual verification

The following six items remain **not manually verified**:

- Physical Mac keyboard media keys.
- Bluetooth headphone media controls.
- System-level seeking from Control Center.
- Physical sleep/wake behavior.
- Audio output device changes.
- Process-level confirmation that no orphaned mpv remains after quitting.

Other device models and system UI surfaces remain platform-dependent. No universal hardware compatibility is claimed.

## Reference manual checklist — report only checks actually performed

The completed checks above need not be repeated for this documentation update. The original checklist is retained as a reference for the six remaining checks and for optional checks not separately reported; it does not mark every detail of a completed checklist step as verified.

Use the latest source in Xcode Debug. Stop an older Xcode instance first so there is one Mango Music instance, and pause other media apps to make system routing easier to assess. Do not paste signed media URLs or raw subprocess output when reporting results.

1. Select MangoMusic → My Mac → Debug and Run. Confirm restored library/preferences, no startup audio, and no new player until explicit Play.
2. Search a publicly available song, press Return and double-click a result. **Listen** to confirm audible playback and advancing time.
3. Open macOS Control Center and inspect Now Playing. Confirm Mango Music is the selected app, the title/channel match, duration/time are reasonable, and playback state is correct. If absent/incorrect, record macOS version and observed behavior; a successful build/runtime getter is not success for this check.
4. Pause/resume from the system controls. Listen for the change and compare the bottom player. Confirm paused time stays fixed and resumes correctly; try a few rapid toggles.
5. Test the Mac keyboard media Play/Pause key. Depending on keyboard settings, Fn may be needed to send media rather than a standard function key. Record the actual keyboard/settings and result.
6. Explicitly add at least two songs to Up Next. Test keyboard/system Next and Previous if available. Only explicit queue entries may advance. Test Previous near the start and after several seconds, including while paused; the previous paused track should load silently until Play.
7. If compatible Bluetooth headphones are available, test their Play/Pause and Next/Previous gestures. Repeat with a wired/USB media controller if available. Record models/gestures; unavailable hardware remains unverified, not failed or universally supported.
8. Seek with the system scrubber/control **if macOS exposes one**. Compare actual sound/time, test while paused and near EOF. Unknown duration should disable position changes. If no system scrubber is shown, record that UI limitation; in-app seeking remains available when capable.
9. While music plays, close the main window. Use keyboard/headphone/system commands with the window closed. Audio should continue until a command pauses/stops it; no second handler or player should appear.
10. Click the Dock icon. Confirm the main window returns with synchronized song, queue, pause state, elapsed time, and controls. Switching focus to another app should not stop playback.
11. Let a song finish or seek near EOF, and confirm precisely the next manual item starts. An exhausted queue should stop and clear stale Now Playing metadata. Test Stop and error/Retry if practical; no failure may silently skip.
12. During Loading, press Pause/Toggle to cancel, then wait: a late resolver must not start audio. An explicit later Play can retry. During buffering, test Next to a manually queued track and confirm one transition.
13. Put the Mac to actual system sleep during playback, then wake. No audio should restart by itself. Press Play explicitly; it restarts with a fresh stream from the beginning. Verify History/remaining queue retain their defined semantics. Display-only sleep should not invoke the system-sleep stop policy.
14. Change the default output (for example disconnect active headphones or select another output). Active playback should stop with a notice, with no automatic loudspeaker playback. Press Play explicitly after choosing the desired route; record any device-specific issue.
15. Quit with Cmd+Q. Confirm audible playback stops, Mango Music's Now Playing metadata clears, and the owned mpv process disappears. In Activity Monitor inspect parent/owned PID rather than terminating unrelated mpv instances. IPC resource cleanup is automated-tested; inspect the owned private directory only if needed, without deleting unrelated paths.
16. Relaunch again without Play. Confirm Favorites/History/remaining queue/preferences and no autoplay. Report which Control Center, keyboard, headphone, seek, background, sleep/output and quit checks were actually performed; unsupported/unavailable controls remain explicitly unverified.

## Current limitations and scope

- Control Center visibility and Play/Pause/Next/Previous delivery are user-confirmed on this Mac, including with the window closed. Physical media keys/headphones and other devices/surfaces remain unverified or platform-dependent. macOS Now Playing arbitration, competing apps and hardware/firmware can affect routing; no private API, global key interception, or permission workaround was added.
- Only absolute position seek is registered, when actual duration is known. Continuous hold-to-seek/skip, rate, shuffle, repeat and feedback commands are disabled. Stop clears metadata, so an explicit restart may need the in-app Play button if macOS no longer routes Play to this app.
- The conservative sleep/default-output policy stops and restarts from the beginning only on explicit Play, not at a saved offset. It does not prevent sleep or auto-resume on wake. Physical interruption delivery remains manual.
- Media metadata uses system clock extrapolation between actual anchors. Native command success acknowledges dispatch; subsequent IPC/network errors remain recoverable through the normal UI.
- SQLite v2/schema, history retention of 100 distinct songs, pending-entry recovery, no startup autoplay, revision conflict safeguards, and multi-instance editing limitations remain. No production database/settings were modified by tests.
- Existing Debug/Release external-tool policy, icon/branding, layout/colors and system appearance remain; no packaging, signing, installers, updater, cloud/account, downloads/artwork, recommendations, AI, or Checkpoint 6 was started.

## Changed files and publication review

Added: `MangoMusic/Services/SystemMediaIntegration.swift`, `MangoMusic/Services/NativeSystemMediaAdapter.swift`, `MangoMusic/Services/NativePlaybackLifecycle.swift`, `Tests/MangoMusicTests/SystemMediaTests.swift`, and archived `VALIDATION_CHECKPOINT4.md`.

Modified: application delegate ownership; model intent/capabilities/interruption/notification paths; engine paused-load/clock-anchor/interruption handling; mpv startup arguments; player disabled/accessibility/notice states; Xcode source membership; local/fixture tests; README/ARCHITECTURE/VALIDATION. Prior HLS diagnosis and database schema documentation are preserved.

The final staged-content review must exclude credentials, cookies, signed streaming URLs, personal history, SQLite files, binaries/build output, caches, temporary logs, and unrelated files. The task authorizes commit `Integrate Mango Music with macOS media controls` and a normal push to existing `origin/main` after successful validation and no major unresolved implementation issue. Manual limits above remain disclosed. The final report records the resulting hash, live remote match, and clean working tree/index; no force-push or history rewrite is permitted.

## Documentation-only manual verification update

The follow-up report updates `VALIDATION.md`, `README.md`, and `ARCHITECTURE.md` only. Playback logic, tests, build configuration and archived prior reports are unchanged. Publication was explicitly requested with commit message `Document Checkpoint 5 manual macOS verification`, using a normal push to existing `origin/main`; the final response records the hash and remote/clean-tree checks. No Checkpoint 6 work is included.
