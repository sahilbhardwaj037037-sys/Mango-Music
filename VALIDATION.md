# Mango Music — Checkpoint 3 validation

Date: 25 October 2026 (Asia/Kolkata).

**Status: Checkpoint 3 validated in Xcode Debug. The final rerun passed all 42 automated tests (including local mpv and live YouTube integrations) and the native Debug build. The user personally confirmed audible playback and the specific manual checks recorded below, and authorized commit/push after successful final validation. Seeking and Previous are not manually verified.** See [YOUTUBE_PLAYBACK_DIAGNOSIS.md](YOUTUBE_PLAYBACK_DIAGNOSIS.md) for the HLS fix.

## Initial Git safety checkpoint

The supplied workspace (`~/Developer/LocalMusic`) contains an old workspace stub; the existing project is `~/Developer/MangoMusic`. Before changing application code:

- Working tree clean, branch `main`.
- Existing origin: `https://github.com/sahilbhardwaj037037-sys/Mango-Music.git`.
- `git fetch origin` succeeded; `git rev-list --left-right --count main...origin/main` returned `0 0`.
- Local and remote HEAD: `5f1ef7d117eb8daeabaf09e0e35f2b9e5e0a2c08` (`Implement real YouTube search with yt-dlp`). No preliminary push necessary.
- No unrelated work was committed/discarded, no repository was created, and no history was rewritten.

Changes were compiled initially in a temporary staging copy, then applied to the existing project. Final build/tests ran from the existing project. All original uncommitted Checkpoint 3 work was preserved. The user subsequently verified Debug playback and explicitly authorized normal publication after final review, successful test/build reruns, and staged-content inspection. A fresh pre-publication fetch again returned `0 0` for `main...origin/main`.

## Environment

- Swift 6.4, Xcode 27.1; My Mac arm64.
- mpv 0.41.0 at `/opt/homebrew/bin/mpv`.
- Homebrew yt-dlp 2026.10.21; Python-framework yt-dlp 2026.08.19 also present at the previous 3.14 hint.
- Runtime lookup validates executable candidates rather than relying exclusively on those machine paths.
- Debug sandbox remains disabled; Release sandbox remains enabled and unchanged. Release external-tool playback is unsupported and not distribution-ready.

## Implemented

Dedicated asynchronous audio-only resolution with bounded Process execution, strict IDs, validated HTTPS output, cancellation, sanitized errors, fresh streams per attempt, and no downloads/cookies. Persistent audio-only mpv, private Unix socket, request/response IDs, ordered event delivery, startup/command/load deadlines, pause/resume/stop/seek/volume, actual position/duration, buffering, EOF, explicit Retry, and owned process cleanup.

Search selection and existing layout/branding/icon remain. Search stays explicit and limited to ten. Context actions include Play, Play Next, Add to Queue. The timer and mock labels were removed. The bottom bar uses real player state, shows errors/Retry, and adds Stop. Queue ordering/removal/clear remain; EOF consumes only manual entries and errors never skip. Dock reopening and quit cleanup are implemented in an application delegate. [ARCHITECTURE.md](ARCHITECTURE.md) specifies exact queue and process behavior.

## Automated results

Final command, from `~/Developer/MangoMusic`:

```sh
MANGO_MPV_INTEGRATION=1 MANGO_YOUTUBE_INTEGRATION=1 MANGO_YOUTUBE_DIAGNOSTICS=1 swift test
```

**42 test declarations passed across seven suites in 14.345 seconds; zero failures and zero skips.** All previous 39 passing tests are retained, along with the previously failing live queue test, a new format-selection regression, and a new live test parameterized over three public IDs. Parameterized tests include additional cases. The new live test asserts actual mpv volume events, pause/resume, duration/position, seeking, and stop. Ordinary `swift test` remains offline; integration tests require explicit opt-in.

Coverage includes valid/invalid IDs; valid/malformed URL output; missing tools; resolution success/nonzero/timeout; malformed IPC; startup/connection failure; process termination and repeated cleanup; sealed ownership preventing post-quit launch; loading/pause/resume/seek/volume/buffering; EOF/empty queue; manual ordering/duplicates/removal; Next/Previous; failure/Retry without skip; cancellation and a resolver deliberately returning a stale result after cancellation. Existing search/runner tests cover metadata handling, ten-result limits, literal arguments, pipe bounds, real subprocess timeout/cancellation, and stale search results.

The optional real-mpv test generates temporary PCM audio, sends it through the production engine with null output, and verifies load, clock/duration, pause/resume, seek, volume, EOF once, process reuse, explicit stop, and a two-entry queue that stops at exhaustion. The fixture and private socket resources are cleaned up. This verifies decoding/IPC/state/queue behavior, **not audible sound**.

## Xcode results

```sh
xcodebuild -project MangoMusic.xcodeproj -scheme MangoMusic \
  -configuration Debug -destination 'platform=macOS,arch=arm64' \
  -derivedDataPath /tmp/MangoMusic-Checkpoint3-Final CODE_SIGNING_ALLOWED=NO build
```

**BUILD SUCCEEDED** from the final existing project. This is a native Debug build; it does not validate distribution signing. Xcode's project test action was attempted and reports: `Scheme MangoMusic is not currently configured for the test action.` The repository's tests are SwiftPM tests; no separate Xcode test target exists.

Build/IPC operations needed execution outside the agent's restricted tool sandbox. This did not change the app's sandbox settings, Gatekeeper, SIP, or system security configuration.

A separate newly launched instance of the final Debug app remained running after launch and exited after a graceful NSRunningApplication termination request. The already-running user instance was preserved. This is a launch/quit smoke check without active playback; it does not verify close-window/Dock behavior or Cmd+Q during streaming.

## Real YouTube integration — now passing

The initial direct-audio pipeline failed with HTTP 403 after successful resolution. The supported selector `bestaudio[protocol^=m3u8]/bestaudio` now prefers advertised audio-only HLS; the production resolver still uses one temporary HTTPS URL, the same bounded Process runner, and the same persistent mpv/IPC engine. No headers, client overrides, credentials, extra retry attempts, or dependencies were needed.

Before the fix, direct mpv/yt-dlp and separately resolved direct URLs failed on Rick Astley and PSY; the short public clip loaded. Headers did not reliably resolve music-video failures. Fresh URL expiry was checked. HLS then played all three; repeated HLS checks on both music videos worked without extra headers. Full comparisons, installed versions, and remaining uncertainty about YouTube's internal rejection policy are in [YOUTUBE_PLAYBACK_DIAGNOSIS.md](YOUTUBE_PLAYBACK_DIAGNOSIS.md).

The final live tests pass through the actual MusicLibrary → AudioStreamResolver → persistent MPVPlaybackEngine pipeline. They verify Rick Astley (`dQw4w9WgXcQ`), PSY (`9bZkp7q19f0`), and Me at the zoo (`jNQXAC9IVRw`) load, advance the playback clock, report duration, pause/resume, acknowledge volume, seek, and stop. The original search-based two-entry queue test also passes: it seeks near EOF to exercise real streamed completion, automatic manual-queue advancement, and stopping at exhaustion. It does not wait through two full songs from beginning to end.

Automated playback uses null audio output; audible verification comes from the user’s personal Xcode Debug test, not those automated events. HLS-less or restricted videos can still fail and show Retry. Debug sandbox is unchanged; Release remains unsupported for external-tool playback.

## User-reported manual verification

On 25 October 2026, the user personally tested Mango Music in Xcode Debug and reported these checks successful:

| Check | Manual result |
| --- | --- |
| Real YouTube audio | Plays audibly |
| Play/Pause | Works |
| Volume | Works |
| Explicitly added songs | Appear in the queue |
| Next | Plays the queued song |
| Track completion | Starts the next explicitly queued song automatically |
| Closing the main window | Does not interrupt music |
| Reopening from the Dock | Restores the window |
| History | Played songs appear |
| Cmd+Q | Quits the app and stops playback |
| Seeking | **Not separately confirmed manually**; automated local/live tests pass |
| Previous | **Not separately confirmed manually**; automated model tests pass |

These are the user's reported results, not an independently performed audible check by the agent. No specific video IDs, additional keyboard/accessibility checks, or process/socket inspection were reported in the manual session. Queue exhaustion is covered by automated tests, not separately claimed as manually verified. Cmd+Q stopping sound is confirmed; separate inspection of the owned mpv PID and socket directory is not claimed as a manual check.

## Remaining manual checks

Seeking and Previous remain optional follow-up acceptance checks; their absence does not override the user's explicit authorization to publish this checkpoint. To check seeking, play a song, move the slider forward/backward, and compare audible position with elapsed time. To check Previous, press after more than three seconds to restart, then near the start to navigate to the prior selected track. Broader accessibility/keyboard review, queue reorder/remove/clear, error/Retry interactions, and an Activity Monitor/socket inspection were not included in the user's reported session.

## Final review and publication

The final review covered the entire Checkpoint 3 diff and new files: bounded async resolution and strict IDs, HLS preference/audio-only fallback, persistent mpv/private IPC, request/event correlation, cancellation and stale requests, manual queue/history/control behavior, process shutdown, native window lifecycle, Xcode source membership, and tests/documentation. No blocking issue was found. The Release sandbox configuration and branding/icon remain unchanged.

The user approved a normal commit with message `Implement real audio playback with mpv and HLS streaming` and push to the existing `origin/main`, conditional on passing validation and staged-content inspection. No force-push or history rewrite is authorized. The staged-content check includes every staged file and searches for secrets, signed media URLs, cookies/credentials, binaries, generated build/cache/user state, and unrelated files. Only the reviewed source, project configuration, tests, and four documents belong to this checkpoint. The final response records the resulting commit hash and remote/clean-tree verification, avoiding a self-referential commit hash in this file.

No SQLite/Checkpoint 4, AI service, artwork, Mini Player, media keys, new repository, or system security change was introduced. Release is not distribution-ready.

## Files added or modified

- `ARCHITECTURE.md`
- `MangoMusic.xcodeproj/project.pbxproj`
- `MangoMusic/App/MangoMusicApp.swift`
- `MangoMusic/Models/Song.swift`
- `MangoMusic/Services/AudioStreamResolver.swift`
- `MangoMusic/Services/MPVConnection.swift`
- `MangoMusic/Services/PlaybackEngine.swift`
- `MangoMusic/Services/YouTubeSearchService.swift`
- `MangoMusic/ViewModels/MusicLibrary.swift`
- `MangoMusic/Views/LibraryContent.swift`
- `MangoMusic/Views/MainWindow.swift`
- `MangoMusic/Views/PlaybackBar.swift`
- `MangoMusic/Views/SongRow.swift`
- `README.md`
- `Tests/MangoMusicTests/MPVIntegrationTests.swift`
- `Tests/MangoMusicTests/MusicLibraryTests.swift`
- `Tests/MangoMusicTests/PlaybackTests.swift`
- `Tests/MangoMusicTests/YouTubeSearchTests.swift`
- `VALIDATION.md`

Additional files for the 403 diagnosis/fix: `Tests/MangoMusicTests/YouTubePlaybackIntegrationTests.swift` and `YOUTUBE_PLAYBACK_DIAGNOSIS.md`. The production 403 fix only changes the resolver format selector; the rest of the Checkpoint 3 implementation is preserved.
