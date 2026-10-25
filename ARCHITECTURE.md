# Playback architecture

## Resolution

`AudioStreamResolver` accepts a Song with a raw eleven-character YouTube ID or `youtube:` ID. It constructs a canonical YouTube URL and invokes the runtime-located yt-dlp through the existing bounded `FoundationProcessRunner`. It prefers advertised audio-only HLS with `bestaudio[protocol^=m3u8]/bestaudio` (audio-only fallback if no HLS is available), returns one validated HTTPS URL, and performs no media download. Config files, plugins, disk cache, and playlists are disabled. The process runner drains both pipes off the main actor, limits output, times out after 45 seconds, and terminates cancelled children with a bounded SIGKILL fallback. Error text is mapped to fixed messages so extractor diagnostics cannot expose signed URLs or credentials. Unavailable, restricted, geo-blocked, and network failures produce a recoverable resolution error, without attempts to defeat access controls.

URLs are ephemeral: no URL cache, history serialization, logs, cookies, or permanent audio storage. Each direct play, queue transition, restart, or explicit Retry resolves again. An expired/rejected stream stops with Retry; no automatic retry loop.

## Persistent player and IPC

`MPVConnection` is an actor. `MPVPlaybackEngine` translates events on the main actor; `MusicLibrary` exposes observable UI state. Process launch, socket startup, writes, and parsing run on the connection actor, away from SwiftUI. The app launches one idle mpv child on demand with video/windows, configuration, user scripts, and ytdl hook disabled. mpv receives media URLs over IPC rather than on its process command line.

`mkdtemp` atomically creates a unique short `/tmp/mango-mpv-XXXXXX` directory with mode 0700; its `ipc` socket fits Darwin's Unix socket path limit. Startup waits asynchronously at 30 ms intervals for at most three seconds. This bounded startup check is the only application polling; playback uses observed properties. Socket reads use a single ordered AsyncStream consumer, newline framing, and a 1 MiB buffer cap. JSON requests have unique request IDs; continuations receive acknowledgements/errors, and unacknowledged commands fail and close the connection after five seconds. Socket writes have a one-second timeout, and SIGPIPE is disabled on the socket.

Observed properties: `time-pos`, `duration`, `pause`, `paused-for-cache`, and `volume`. `start-file` captures mpv's playlist entry ID; `file-loaded` enables controls/history; `end-file` advances only on EOF for that entry, once. Error/stop/quit events never advance the manual queue. A 45-second file-load watchdog stops a stalled load. Playback and IPC errors are sanitized and surfaced with Retry.

Transitions serialize cancelled playback/control tasks. A stop acknowledgement separates track generations; UUIDs reject stale events/resolutions. EOF is guarded in both engine and model. User controls update from mpv observations, and seeking clamps to the actual reported duration. Volume clamps to 0–100 in mpv, 0–1 in UI.

`OwnedMPVProcess` protects child ownership with a lock. Shutdown terminates only its owned child, waits at most 200 ms, then sends SIGKILL if needed. Cleanup removes only its unique private directory. Cmd+Q permanently seals the owner so a pending startup cannot launch a child after shutdown. An application delegate retains the library across window closure and uses SwiftUI's openWindow action for Dock reopening. Search/resolution children are cancelled on quit.

## Queue policy

Up Next is the upcoming manual queue; the current song lives separately. Direct play never populates the queue. Play Next prepends; Add appends. Playing a queue entry consumes only that entry. Next consumes the first item or stops if empty. EOF consumes the first item or stops; duplicate/stale EOF cannot consume two. Playback failure retains the failed current song and upcoming queue, with explicit Retry. Previous restarts after three seconds or pops navigation history without adding anything to Up Next. Visible History begins on successful file load, capped at 100 entries. Queue/favorites/history remain in memory.

## YouTube format selection

The 403 occurred when mpv opened fresh direct audio URLs, after yt-dlp successfully resolved them. Direct mpv/yt-dlp integration reproduced the same failures. Adding ordinary extractor headers did not reliably fix the problem, and the installed Homebrew yt-dlp matches the current stable release. No missing-runtime warning was observed. The strongest supported diagnosis is format/transport-specific rejection by YouTube's media servers; their internal rejection policy is unknown.

The resolver now prefers public audio-only HLS streams already advertised by yt-dlp. This worked on Rick Astley, PSY, and “Me at the zoo,” with no extra headers or client overrides. Both sides of the selector remain audio-only. HLS may select a different codec/bitrate and has segment-based buffering/seek characteristics. If no HLS is advertised the resolver falls back to bestaudio; an inaccessible fallback still stops with Retry. This is format selection, not a retry loop.

The production change is limited to the resolver's format argument. Persistent mpv/IPC, process ownership, native UI, and queue semantics are unchanged. No cookies, tokens, authentication, impersonation, proxies, security changes, or new dependencies were introduced. Since mpv's default ytdl hook also failed on the direct formats and HLS already works through the existing bounded resolver, moving extraction into mpv would add lifecycle changes without an established benefit. See [YOUTUBE_PLAYBACK_DIAGNOSIS.md](YOUTUBE_PLAYBACK_DIAGNOSIS.md) for comparisons and limitations.

Protocol behavior follows the [mpv manual](https://mpv.io/manual/stable/) and its [JSON IPC specification](https://github.com/mpv-player/mpv/blob/master/DOCS/man/ipc.rst).

## Verification status

The final Debug build and all 42 automated tests, including actual local mpv and live YouTube/HLS playback, pass. Automated tests cover seeking and Previous semantics; the user has not separately confirmed either manually. The user personally verified audible YouTube audio, Play/Pause, volume, explicit queue additions and Next, automatic advancement after completion, History, uninterrupted playback after window closure, Dock reopening, and Cmd+Q stopping playback in Xcode Debug. Manual confirmation of Cmd+Q stopping audio does not imply separate inspection of process IDs or socket removal; owned process/resource cleanup has automated coverage. See [VALIDATION.md](VALIDATION.md) for exact evidence and remaining checks. The user authorized normal commit/push after successful final validation. Release sandbox limitations and Checkpoint 4 exclusions remain unchanged.
