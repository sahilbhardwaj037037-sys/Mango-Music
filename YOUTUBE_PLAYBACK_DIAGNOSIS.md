# YouTube HTTP 403 diagnosis and fix

25 October 2026, Asia/Kolkata. The user manually verified Debug playback and approved normal commit/push after final validation. All original Checkpoint 3 work was preserved.

## Result

**Live YouTube streaming now passes on three public videos.** The smallest demonstrated fix is to prefer advertised audio-only HLS:

```text
--format bestaudio[protocol^=m3u8]/bestaudio
```

The previous `bestaudio` selector chose direct HTTPS Opus format 251, which returned HTTP 403 for the music samples. HLS format 234 played on all three, including through the unchanged production Swift playback pipeline. Both branches of the selector are audio-only; the fallback handles videos without an advertised HLS audio format. It is not an automatic retry or a client/access-control override.

## Installed tools and execution context

| Tool | Installed version | Path / role |
| --- | --- | --- |
| yt-dlp | 2026.10.21 | `/opt/homebrew/bin/yt-dlp`, selected by app |
| yt-dlp | 2026.08.19 | Python framework 3.14 installation, present but not selected |
| mpv | 0.41.0 | `/opt/homebrew/bin/mpv` |
| Deno | 2.9.8 | Already installed at `/opt/homebrew/bin/deno` |

The selected yt-dlp matches the [current stable release](https://github.com/yt-dlp/yt-dlp/releases/tag/2026.10.21). No tool was installed or updated. The app's bounded runner has Homebrew on PATH; no JavaScript runtime/challenge warning was observed in these extraction runs. An old yt-dlp executable or missing Deno is not supported as the cause of the reproduced failures.

## Comparison

All videos were public, accessed without credentials. mpv used null output and short observed playback rather than deliberate complete media-file downloads. Audio was buffered by the player; media was not saved to disk. Signed URLs and raw metadata/diagnostics were held in memory, passed over private IPC, and never printed. Reports contained fixed categories, format IDs, video IDs, and booleans only.

| Path | Rick Astley `dQw4w9WgXcQ` | PSY `9bZkp7q19f0` | Me at the zoo `jNQXAC9IVRw` |
| --- | --- | --- | --- |
| yt-dlp resolution, `bestaudio` | Success, format 251 | Success, format 251 | Success, format 251 |
| mpv built-in yt-dlp integration, `bestaudio` | HTTP 403 at media open | HTTP 403 at media open | Loaded and clock advanced |
| Fresh resolved URL → mpv | HTTP 403 | HTTP 403 | Loaded and clock advanced |
| Resolved URL + ordinary extractor headers → mpv | HTTP 403 | One success; repeat with same-URL headers/no-headers/headers failed | Loaded and clock advanced |
| Advertised audio-only HLS → mpv | Loaded and clock advanced | Loaded and clock advanced | Loaded and clock advanced |
| Fixed app pipeline, without extra headers | Controls passed | Controls passed | Controls passed |

The built-in hook used an explicit yt-dlp path, bestaudio selection, disabled user config/plugins/cache, and disabled subtitle/thumbnail output. The separately resolved path used the application's yt-dlp arguments and sanitized execution environment. Both used explicit Process argument arrays; no shell interpolation was involved.

The original app pipeline reproduced the Rick Astley and PSY media-open failures; the short clip loaded. An initial new test helper mixed direct engine volume commands with asynchronously queued UI commands and timed out. The helper was corrected to await the actual mpv volume event from the UI command before final validation; this did not require an application control change.

## Diagnosis by hypothesis

- **Resolution:** succeeds with exit zero and a single HTTPS audio-only URL. The 403 is later, when mpv's media backend opens that URL; it is not a search or JSON IPC failure.
- **Expiry:** freshly extracted direct URLs were opened immediately; their expiry timestamps were later than the test time. The HLS confirmation also checked expiry embedded in the URL path. Stale URL caching is not supported as the cause.
- **Headers/context:** yt-dlp exposes User-Agent, Accept, Accept-Language, and Sec-Fetch-Mode. Tests supplied ordinary User-Agent/Accept/Accept-Language to mpv, and the built-in ytdl hook also carries extractor context. Header changes did not reliably fix direct formats. HLS repeatedly played without extra headers. No header transport refactor was justified by these results.
- **Codec/direct format:** an explicit audio-only M4A format 140 also resolved but received 403 on Rick Astley. Changing only Opus to M4A did not solve it.
- **Client/extractor behavior:** latest stable yt-dlp selected the failing direct formats with its defaults. HLS was already advertised by those same default extraction runs. No forced client was needed. The strongest supported diagnosis is **format/transport-specific rejection by YouTube's media servers**; the exact internal policy/signature/client reason is not established. This is not evidence of a universal IP ban, since public HLS and the short direct clip worked.
- **mpv integration:** enabling the built-in hook with its usual bestaudio preference reproduced the failures. Moving extraction into mpv alone is not a demonstrated fix; it would also change ownership/cancellation behavior unnecessarily.

A supplemental Python HTTP probe could not produce an authoritative response in that Python network context; it was not used to infer status. The 403 classification came from mpv's own fixed diagnostic categories. No raw server responses or signed URLs were retained in project files.

## Production change and regressions

`MangoMusic/Services/AudioStreamResolver.swift` now uses a named format selector constant, with one argument replacement. Persistent mpv, JSON IPC, the bounded resolver, native SwiftUI, manual queue, errors/Retry, and process ownership are unchanged.

The syntax uses yt-dlp's [documented format filtering and slash fallback](https://github.com/yt-dlp/yt-dlp#format-selection). [mpv's hook implementation](https://github.com/mpv-player/mpv/blob/v0.41.0/player/lua/ytdl_hook.lua) also documents how it applies extraction metadata; it was inspected rather than assuming a missing User-Agent was the cause.

The existing resolver argument assertion now expects the new selector. A regression test asserts HLS preference, audio-only fallback, no-playlist/no-download/config behavior, and a canonical literal video URL. A new opt-in integration test uses three canonical IDs so search rankings do not decide its samples. Existing tests were retained.

## Final validation

From `~/Developer/MangoMusic`:

```sh
MANGO_MPV_INTEGRATION=1 MANGO_YOUTUBE_INTEGRATION=1 MANGO_YOUTUBE_DIAGNOSTICS=1 swift test
```

**42 test declarations across seven suites passed, with zero skips and zero failures (14.345 seconds in the final pre-publication rerun).** This includes all previous tests, real local mpv playback, the three live samples, and the original search-based two-entry streaming queue. The live samples check actual position/duration, pause/resume, observed volume, seek, and Stop. The queue test seeks near EOF to verify real streamed completion, manual advancement, and exhaustion without waiting through two full songs. The local test verifies process reuse/cleanup and queue behavior. Ordinary `swift test` still makes no network requests.

```sh
xcodebuild -project MangoMusic.xcodeproj -scheme MangoMusic \
  -configuration Debug -destination 'platform=macOS,arch=arm64' \
  -derivedDataPath /tmp/MangoMusic-Checkpoint3-Final CODE_SIGNING_ALLOWED=NO build
```

**BUILD SUCCEEDED.** No changes to Xcode configuration or Release sandbox settings were needed for this fix.

## User confirmation and remaining limits

The user personally tested Mango Music in Xcode Debug and confirmed audible YouTube playback, Play/Pause and volume, explicitly added songs appearing in the queue, Next playing the queued song, automatic advancement to the next explicitly queued song after completion, played songs appearing in History, uninterrupted playback after closing the window, Dock reopening restoring the window, and Cmd+Q quitting/stopping playback.

**Seeking and Previous were not separately confirmed manually.** Seeking has real local/live mpv automated coverage; Previous has model-level automated coverage. Automated playback uses null output, so the audible confirmation is attributed to the user's session. Queue exhaustion and owned process/socket cleanup are covered automatically, without claiming the user separately inspected them.

HLS can choose a different codec/bitrate than direct bestaudio and uses segmented buffering. Some videos may lack accessible HLS; fallback, unavailable/restricted media, future YouTube changes, or network failures can still yield an error and explicit Retry. No automatic retry or silent skip was added. Release remains sandboxed and unsupported for external-tool playback.

For later manual seeking/Previous checks, run the latest Debug source, play a public result, move the slider forward/backward, and compare sound/time. Press Previous after more than three seconds to restart, or near the start to return through selected-track history. These checks remain unconfirmed and are not prerequisites beyond the user's explicit approval of this publication.

The user authorized commit `Implement real audio playback with mpv and HLS streaming` and a normal push to existing `origin/main` after the final successful tests/build and staged-content inspection. The final report records the commit and remote verification. No original work was reset or discarded.

No browser automation, cookies, credentials, tokens, proxies, DRM/access bypass, system security changes, dependencies, media files, or sensitive diagnostics were added.
