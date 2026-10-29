# Mango Music local packaging — V2 test release 2.0.1 / Build 201

The V2 package bundles the native application, a source-built minimal mpv, verified upstream standalone yt-dlp, and separate static ffmpeg/ffprobe executables for audio conversion. The current successor test release is **2.0.1/build 201**, staged separately without installation; see [RELEASE_2.0.1.md](RELEASE_2.0.1.md) for implementation, validation and manual-retest boundaries. The original [Phase 4A](PHASE4A.md) **2.0/build 200** artifact is preserved. [UPGRADE.md](UPGRADE.md) remains a deferred upgrade/rollback plan. The tested search/audio-only HLS path is self-contained apart from macOS system libraries/frameworks and network access: no installed Homebrew, Python, FFmpeg executable, Deno or external dylibs are required at runtime. This is a local-use build, not public distribution, Developer ID signing, notarization or App Store compatibility.

## Build requirements and acquisition

Use an Apple Silicon Mac with Xcode and its command-line tools, Python **3.14** for the pinned arm64 build-tool wheels, and internet access for the explicitly requested initial acquisition. The packaged app does not need installed Python. The validated host uses Xcode 27.1; builds target macOS 14.0. Actual testing on macOS 14 is still pending.

From the existing project directory:

```sh
cd ~/Developer/MangoMusic
python3 Scripts/Packaging/prepare.py --acquire
.build/packaging/tools/bin/python Scripts/Packaging/package.py --work-dir .build/v2-2.0.1-201
```

Only prepare.py with --acquire permits downloads. It uses HTTPS, fixed versions/commits and SHA-256 verification. Scripts/Packaging/dependencies.json records URLs, hashes and provenance. The standalone yt-dlp hash was checked against the GitHub release asset digest and upstream SHA2-256SUMS; source hashes pin the downloaded upstream release archives, and wheel hashes match PyPI metadata. No arbitrary unverified binary is executed by the normal build.

After acquisition, these commands work from the local cache without network downloads:

```sh
python3 Scripts/Packaging/prepare.py
.build/packaging/tools/bin/python Scripts/Packaging/package.py --work-dir .build/v2-2.0.1-201
```

Downloads, virtual environment, build-only tools, sources, helper prefixes and helper logs stay under ignored `.build/packaging`. `--work-dir .build/v2-2.0.1-201` places the V2 app, Xcode DerivedData and release log under `.build/v2-2.0.1-201`, preserving previous outputs. The default without that option remains the historical `.build/packaging` location. Work directories must resolve under project `.build`. No Homebrew/Python/system installation is modified. The recipe installs hash-pinned wheels offline in its own virtual environment. For fresh reproduction, move that project-specific staging directory aside, prepare/acquire again, and rebuild. Do not move it while its app is running. A clean source extraction/build from the verified cache was tested; compiler/SDK upgrades are not claimed bit-for-bit reproducible.

The script refuses to replace an existing `.build/v2-2.0.1-201/output/Mango Music.app`. Quit that isolated app and explicitly preserve its output under a new name, or choose a fresh work directory, then rebuild. Never move an installed app as part of this recipe. It never writes into /Applications or automatically changes an installed copy. Rebuild the app after Swift code or dependency changes; rebuilding only in Xcode does not update the separately packaged copy.

## Pinned runtime components

| Component | Version | Role |
| --- | --- | --- |
| mpv | 0.41.0 | Persistent JSON IPC audio engine; upstream CoreAudio initialization fix c5d391adba7bd024954d0df1e0405f5749f4d4ca retained from development Homebrew recipe |
| FFmpeg / ffprobe | 8.0.1 | Static libraries inside mpv; separate bundled audio-focused CLI tools with native AAC encoding, selected muxers and system SecureTransport HTTPS |
| libass | 0.17.4 | Mandatory upstream mpv dependency, CoreText font provider |
| libplacebo | 7.349.0 | Mandatory upstream mpv dependency, no GPU backend |
| FreeType | 2.14.1 | Required font dependency |
| HarfBuzz | 12.2.0 | Required font shaping dependency |
| FriBidi | 1.0.16 | Required text dependency |
| fast_float | pinned libplacebo submodule commit | Static numeric parsing dependency |
| Vulkan-Headers | pinned libplacebo submodule commit | Build-only stub declarations; no Vulkan runtime |
| yt-dlp | 2026.10.21 official yt-dlp_macos | Search and HLS-first resolution, with embedded Python 3.14/TLS/certificates/native extensions |

Exact source commits, archive digests, build-only wheel versions and the CoreAudio patch before/after hashes are in the dependency manifest. No third-party binary is committed to Git.

FFmpeg enables audio-focused AAC/Opus/Vorbis/MP3/FLAC/PCM decoding, HLS/MOV-MP4/MPEG-TS/Matroska/Ogg/local-audio demuxing, HTTP/HTTPS/TCP/TLS/crypto and necessary audio filtering/resampling. The minimal mpv library build omits video decoders, unrelated codecs, external TLS libraries, FFmpeg command-line tools and GPL/nonfree FFmpeg options. A separate source/configuration from the same verified archive builds ffmpeg and ffprobe with static libraries, selected audio demuxers/decoders/muxers, AAC/PCM encoding and required audio filters. This adds conditional AAC/M4A conversion and yt-dlp fixup/extraction support without rebuilding mpv around a broader codec set. Unsupported inputs still fail cleanly; this is not a general-purpose FFmpeg codec build. The exact flags are reviewable in build_helpers.py. mpv disables video outputs/GPU backends, Lua/JavaScript, its own YouTube integration, optional libraries and duplicate media integration. Its required libass/libplacebo are retained rather than patching out upstream architecture. Only system dynamic dependencies remain for mpv.

The verified yt-dlp executable remains universal (arm64 and x86_64) to retain its upstream PyInstaller archive. The app and mpv are arm64 only. The embedded 103 native files are audited for arm64, deployment minimum and relative/system linkage. Standalone yt-dlp does include a Python runtime and SSL libraries **inside its payload**; self-containment does not mean Python-free. Its extraction to a private temporary directory is normal PyInstaller behavior. No external JavaScript runtime is bundled. Some YouTube clients/formats/videos may require one; only the tested HLS/search path is established.

## Bundle and runtime discovery

```text
Mango Music.app/Contents/
  MacOS/MangoMusic
  MacOS/mpv
  MacOS/yt-dlp
  MacOS/ffmpeg
  MacOS/ffprobe
  Resources/Assets.car
  Resources/AppIcon.icns
  Resources/ThirdPartyNotices/
  Info.plist
  _CodeSignature/
```

Static linking eliminates a separate Frameworks payload for mpv, ffmpeg and ffprobe. yt-dlp's embedded libraries extract with their verified bundle-relative layouts. A generated Info.plist marker selects Bundle.main-relative helpers without shell PATH discovery or silent global fallback. Missing/non-executable/native-header-invalid/symlink helpers fail clearly. Packaging validates complete signatures and library layouts; lightweight runtime header checks are not complete tamper detection. Production executes argument arrays, retains HLS-first resolution and persistent JSON IPC, and logs no signed stream URLs.

Debug continues using installed development tools and the current Xcode workflow. The minimal mpv has no scripting options at all, so packaged launches omit --load-scripts/--ytdl flags; external development launches retain them. Packaging does not change the queue, persistence, native controls, app lifecycle, icon, branding or main UI.

## Release sandbox and signing

The checked-in Xcode project remains unchanged: Debug is unsandboxed and stock Release is sandboxed. Packaging explicitly builds Release with `ARCHS=arm64 MACOSX_DEPLOYMENT_TARGET=14.0 ENABLE_APP_SANDBOX=NO CODE_SIGNING_ALLOWED=NO`, then signs locally. The produced app has no App Sandbox entitlement. This preserves helper networking, Unix IPC and existing data paths without new sandbox inheritance architecture. It permits ordinary user filesystem/network access rather than App Sandbox confinement; it does not grant administrator rights or change SIP, Gatekeeper, Full Disk Access or Accessibility settings. This is not an App Store configuration.

No valid signing identity was available. The pipeline ad-hoc signs nested helper/main executables first, the final app last, then verifies the signatures. yt-dlp's embedded signed Mach-O files remain unchanged; the validator compares every embedded payload entry to the verified upstream executable. Ad-hoc signing supplies local integrity, not a trusted publisher identity or notarization. A copied/downloaded/quarantined build may receive macOS warnings; do not disable system protections or remove quarantine as a packaging shortcut. Use the locally built artifact; handle any new security prompt explicitly.

## Licenses and redistribution

Complete selected source license texts, the full upstream yt-dlp third-party notice, and the pinned manifest are placed in ThirdPartyNotices. See Scripts/Packaging/LICENSE-NOTES.md. mpv is GPL-enabled; FreeType uses its GPL-2.0-or-later alternative. FFmpeg/libplacebo/FriBidi carry LGPL terms, libass ISC, HarfBuzz MIT, and fast_float MIT. Portions of this software are copyright © the FreeType Project (www.freetype.org). All rights reserved.

The standalone yt-dlp aggregate is GPLv3+ according to upstream, with embedded Python and other independently licensed components; its source Unlicense does not replace those terms. The upstream full license aggregate and native archive audit are retained. Source archives/build options and the CoreAudio patch remain available in project staging plus pinned acquisition scripts. Local private use is the scope. Before conveying the app to anyone else, complete the exact corresponding-source/build/relinking and notice obligations for all selected GPL/LGPL and embedded components. URLs alone do not satisfy source obligations. Public redistribution compliance is not claimed complete, and no GitHub Release is authorized.

## Validation and limitations

```sh
.build/packaging/tools/bin/python Scripts/Packaging/validate.py '.build/v2-2.0.1-201/output/Mango Music.app'
.build/packaging/tools/bin/python Scripts/Packaging/test_validation.py '.build/v2-2.0.1-201/output/Mango Music.app'
python3 Scripts/Packaging/smoke.py '.build/v2-2.0.1-201/output/Mango Music.app'
# Explicit opt-in: public YouTube stream and actual low-volume CoreAudio output:
python3 Scripts/Packaging/smoke.py '.build/v2-2.0.1-201/output/Mango Music.app' --live --audio
# No-Xcode executable launch with kernel-protected isolated data and normal quit:
swiftc -parse-as-library Scripts/Packaging/IsolatedLaunchProbe.swift -lsqlite3 \
  -o .build/v2-2.0.1-201/isolated-launch-probe
.build/v2-2.0.1-201/isolated-launch-probe \
  "$PWD/.build/v2-2.0.1-201/output/Mango Music.app" "$PWD/.build/v2-2.0.1-201/launch-home"
```

Run the Swift/Xcode regression commands in VALIDATION.md. Tests accept MANGO_PACKAGED_APP only in test code for explicit helper injection; the shipping app accepts no environment executable override. The validator checks architecture/minimums, dependencies/rpaths including embedded yt-dlp, app/icon metadata, executable permissions, signatures, sandbox absence, unchanged upstream payload and excluded personal/build data.

The following Launch Services, CoreAudio and user results are historical Checkpoint 6 evidence. The Build 200 evidence in PHASE4A.md records 30 user-reported manual passes, zero failures, one media-key skip and the repeat-transition visual defect. Build 201 implements a save-status fix and appearance preferences; both await manual verification as tracked in [GUI_FINDINGS.md](GUI_FINDINGS.md). Separately, the user previously manually confirmed the isolated standalone Checkpoint 6 package on this Mac: Finder launch without Xcode, real YouTube search, audible playback, Play/Pause/Next/Previous/volume, manual queue playback, Control Center playback controls, background playback after closing the window and successful Dock reopening, Favorites/History/Queue/settings restoration after quit/relaunch, and Cmd+Q cleanly stopping playback. See VALIDATION.md for all nine historical passes and their limits. Seeking, icon appearance, automatic queue advancement, no autoplay and process/socket inspection were not separately confirmed in that historical follow-up. Hardware/runtime checks are established only when explicitly reported; keyboard/headphone media keys remain skipped in V2. macOS 14 declaration/linkage checks cannot replace running on macOS 14. Tests use isolated SQLite/settings and do not modify the user's library.

## Isolated V2 validation and deferred installation

`/Applications/Mango Music.app` exists and remains V1. The historical Checkpoint 6 empty-destination installation procedure is superseded by [UPGRADE.md](UPGRADE.md). Do not copy, replace or launch V2 against the real home during Phase 4A. A future Phase 4B needs separate authorization, a complete app/data/preferences backup, and paired data restoration for rollback from schema 3 to V1.

The new protected launcher is compiled but was not run automatically. The app plist is the single source of version/build (2.0.1/201) for both Xcode and packaging. Build 200 remains at `.build/phase4a/output/Mango Music.app`; use the new isolated HOME below for Build 201. Run this yourself for GUI checks, after quitting other Mango Music instances:

```sh
swiftc -parse-as-library Scripts/Packaging/IsolatedLaunchProbe.swift -lsqlite3 \
  -o .build/v2-2.0.1-201/isolated-launch-probe
.build/v2-2.0.1-201/isolated-launch-probe \
  "$PWD/.build/v2-2.0.1-201/output/Mango Music.app" "$PWD/.build/v2-2.0.1-201/manual-home" --manual
```

Keep that terminal running and quit the test app with Cmd+Q afterward. The launcher requires project `.build` paths, sets both HOME and CFFIXED_USER_HOME, restricts PATH, denies writes to `/Applications` and the real home outside the isolated home, and denies reads of the real MangoMusic library/preferences file. Cocoa/system services remain macOS-managed; before/after protected-file hashes provide additional observed evidence. This temporary validation profile is separate from the shipping app's unsandboxed Release configuration.

Without `--manual`, the launcher checks two actual packaged-executable launches and normal quits, exact process/bundle paths and a schema-v3 database in the isolated home. It does not synthesize playback, Control Center commands, window reopening or audible human observations. The earlier `LaunchProbe.swift` Launch Services probe is historical; its old package results are not new V2 Finder/Dock evidence.

```sh
python3 Scripts/Packaging/conversion_smoke.py '.build/v2-2.0.1-201/output/Mango Music.app'
```

This generated-audio check invokes yt-dlp with `--ffmpeg-location` and system-only PATH, verifies both exact conversion executable paths, inspects AAC output with bundled ffprobe and decodes with bundled mpv after stopping localhost. Production performs conversion only for otherwise unsupported audio containers; the smoke test's forced extraction is an additional dependency check, not a change to production download policy.

## Troubleshooting

- Missing/damaged helper: rebuild from verified cached dependencies; do not repair by pointing the packaged app to arbitrary global tools.
- Hash mismatch: stop and investigate provenance; do not disable hash/TLS checks. Dependency updates require a reviewed manifest change.
- Existing output: quit it and move it aside; the build deliberately refuses replacement.
- Build bootstrap mismatch: use Python 3.14 with the pinned arm64 wheels, not a global pip upgrade.
- YouTube failure: Retry requests a fresh stream; service/client changes may require a reviewed yt-dlp update. Do not log URLs, introduce cookies/proxies, or claim universal playback.
- No audible sound: check device/volume and test manually. Null-output tests and a successful Release build are not audible proof.
- CoreAudio changes/sleep/media hardware: remain manual/platform-dependent; no global key tap or permission workaround is included.

## Comparison with the original audit

Installed Homebrew mpv required at least 49 Mach-O files across 42 formula families, 61.3 MiB, with one additional unresolved rpath and minimum macOS 26.0. The minimal mpv is approximately 7.7 MiB and uses only system dynamic libraries, targeting macOS 14. The historical Checkpoint 6 app was approximately 47.37 MiB. The preserved Phase 4A app is approximately 54.14 MiB; Build 201 is 54.23 MiB including separate conversion tools, standalone yt-dlp and notices. This is not a size comparison against a complete original app: the 61.3 MiB baseline excluded standalone yt-dlp/resources and was a lower bound. Build-only source/wheel caches are excluded from the app.
