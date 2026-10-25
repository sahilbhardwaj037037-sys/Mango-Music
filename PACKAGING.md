# Mango Music local packaging — Checkpoint 6

The package bundles the native application, a source-built minimal mpv, and verified upstream standalone yt-dlp. The tested search/audio-only HLS path is self-contained apart from macOS system libraries/frameworks and network access: no installed Homebrew, Python, FFmpeg executable, Deno or external dylibs are required at runtime. This is a local-use build, not public distribution, Developer ID signing, notarization or App Store compatibility.

## Build requirements and acquisition

Use an Apple Silicon Mac with Xcode and its command-line tools, Python **3.14** for the pinned arm64 build-tool wheels, and internet access for the explicitly requested initial acquisition. The packaged app does not need installed Python. The validated host uses Xcode 27.1; builds target macOS 14.0. Actual testing on macOS 14 is still pending.

From the existing project directory:

```sh
cd ~/Developer/MangoMusic
python3 Scripts/Packaging/prepare.py --acquire
.build/packaging/tools/bin/python Scripts/Packaging/package.py
```

Only prepare.py with --acquire permits downloads. It uses HTTPS, fixed versions/commits and SHA-256 verification. Scripts/Packaging/dependencies.json records URLs, hashes and provenance. The standalone yt-dlp hash was checked against the GitHub release asset digest and upstream SHA2-256SUMS; source hashes pin the downloaded upstream release archives, and wheel hashes match PyPI metadata. No arbitrary unverified binary is executed by the normal build.

After acquisition, these commands work from the local cache without network downloads:

```sh
python3 Scripts/Packaging/prepare.py
.build/packaging/tools/bin/python Scripts/Packaging/package.py
```

All downloads, virtual environment, build-only tools, sources, prefix, compiler output, logs, and app outputs stay under ignored `.build/packaging`. No Homebrew/Python/system installation is modified. The recipe installs hash-pinned wheels offline in its own virtual environment. For fresh reproduction, move that project-specific staging directory aside, prepare/acquire again, and rebuild. Do not move it while its app is running. A clean source extraction/build from the verified cache was tested; compiler/SDK upgrades are not claimed bit-for-bit reproducible.

The script refuses to replace an existing `.build/packaging/output/Mango Music.app`. Quit that app, move the previous isolated output aside, then rebuild. It never writes into /Applications or automatically changes an installed copy. Rebuild the app after Swift code or dependency changes; rebuilding only in Xcode does not update the separately packaged copy.

## Pinned runtime components

| Component | Version | Role |
| --- | --- | --- |
| mpv | 0.41.0 | Persistent JSON IPC audio engine; upstream CoreAudio initialization fix c5d391adba7bd024954d0df1e0405f5749f4d4ca retained from development Homebrew recipe |
| FFmpeg | 8.0.1 | Static audio demux/decode/filter/resample plus system SecureTransport HTTPS |
| libass | 0.17.4 | Mandatory upstream mpv dependency, CoreText font provider |
| libplacebo | 7.349.0 | Mandatory upstream mpv dependency, no GPU backend |
| FreeType | 2.14.1 | Required font dependency |
| HarfBuzz | 12.2.0 | Required font shaping dependency |
| FriBidi | 1.0.16 | Required text dependency |
| fast_float | pinned libplacebo submodule commit | Static numeric parsing dependency |
| Vulkan-Headers | pinned libplacebo submodule commit | Build-only stub declarations; no Vulkan runtime |
| yt-dlp | 2026.10.21 official yt-dlp_macos | Search and HLS-first resolution, with embedded Python 3.14/TLS/certificates/native extensions |

Exact source commits, archive digests, build-only wheel versions and the CoreAudio patch before/after hashes are in the dependency manifest. No third-party binary is committed to Git.

FFmpeg enables audio-focused AAC/Opus/Vorbis/MP3/FLAC/PCM decoding, HLS/MOV-MP4/MPEG-TS/Matroska/Ogg/local-audio demuxing, HTTP/HTTPS/TCP/TLS/crypto and necessary audio filtering/resampling. Video decoders, unrelated codecs, external TLS libraries, FFmpeg command-line tools, and GPL/nonfree FFmpeg options are omitted. The exact flags are reviewable in build_helpers.py. mpv disables video outputs/GPU backends, Lua/JavaScript, its own YouTube integration, optional libraries and duplicate media integration. Its required libass/libplacebo are retained rather than patching out upstream architecture. Only system dynamic dependencies remain for mpv.

The verified yt-dlp executable remains universal (arm64 and x86_64) to retain its upstream PyInstaller archive. The app and mpv are arm64 only. The embedded 103 native files are audited for arm64, deployment minimum and relative/system linkage. Standalone yt-dlp does include a Python runtime and SSL libraries **inside its payload**; self-containment does not mean Python-free. Its extraction to a private temporary directory is normal PyInstaller behavior. No external JavaScript runtime is bundled. Some YouTube clients/formats/videos may require one; only the tested HLS/search path is established.

## Bundle and runtime discovery

```text
Mango Music.app/Contents/
  MacOS/MangoMusic
  MacOS/mpv
  MacOS/yt-dlp
  Resources/Assets.car
  Resources/AppIcon.icns
  Resources/ThirdPartyNotices/
  Info.plist
  _CodeSignature/
```

Static linking eliminates a separate Frameworks payload for mpv. yt-dlp's embedded libraries extract with their verified bundle-relative layouts. A generated Info.plist marker selects Bundle.main-relative helpers without shell PATH discovery or silent global fallback. Missing/non-executable/native-header-invalid/symlink helpers fail clearly. Packaging validates complete signatures and library layouts; lightweight runtime header checks are not complete tamper detection. Production executes argument arrays, retains HLS-first resolution and persistent JSON IPC, and logs no signed stream URLs.

Debug continues using installed development tools and the current Xcode workflow. The minimal mpv has no scripting options at all, so packaged launches omit --load-scripts/--ytdl flags; external development launches retain them. Packaging does not change the queue, persistence, native controls, app lifecycle, icon, branding or main UI.

## Release sandbox and signing

The checked-in Xcode project remains unchanged: Debug is unsandboxed and stock Release is sandboxed. Packaging explicitly builds Release with `ARCHS=arm64 MACOSX_DEPLOYMENT_TARGET=14.0 ENABLE_APP_SANDBOX=NO CODE_SIGNING_ALLOWED=NO`, then signs locally. The produced app has no App Sandbox entitlement. This preserves helper networking, Unix IPC and existing data paths without new sandbox inheritance architecture. It permits ordinary user filesystem/network access rather than App Sandbox confinement; it does not grant administrator rights or change SIP, Gatekeeper, Full Disk Access or Accessibility settings. This is not an App Store configuration.

No valid signing identity was available. The pipeline ad-hoc signs nested helper/main executables first, the final app last, then verifies the signatures. yt-dlp's embedded signed Mach-O files remain unchanged; the validator compares every embedded payload entry to the verified upstream executable. Ad-hoc signing supplies local integrity, not a trusted publisher identity or notarization. A copied/downloaded/quarantined build may receive macOS warnings; do not disable system protections or remove quarantine as a packaging shortcut. Use the locally built artifact; handle any new security prompt explicitly.

## Licenses and redistribution

Complete selected source license texts, the full upstream yt-dlp third-party notice, and the pinned manifest are placed in ThirdPartyNotices. See Scripts/Packaging/LICENSE-NOTES.md. mpv is GPL-enabled; FreeType uses its GPL-2.0-or-later alternative. FFmpeg/libplacebo/FriBidi carry LGPL terms, libass ISC, HarfBuzz MIT, and fast_float MIT. Portions of this software are copyright © the FreeType Project (www.freetype.org). All rights reserved.

The standalone yt-dlp aggregate is GPLv3+ according to upstream, with embedded Python and other independently licensed components; its source Unlicense does not replace those terms. The upstream full license aggregate and native archive audit are retained. Source archives/build options and the CoreAudio patch remain available in project staging plus pinned acquisition scripts. Local private use is the scope. Before conveying the app to anyone else, complete the exact corresponding-source/build/relinking and notice obligations for all selected GPL/LGPL and embedded components. URLs alone do not satisfy source obligations. Public redistribution compliance is not claimed complete, and no GitHub Release is authorized.

## Validation and limitations

```sh
.build/packaging/tools/bin/python Scripts/Packaging/validate.py '.build/packaging/output/Mango Music.app'
.build/packaging/tools/bin/python Scripts/Packaging/test_validation.py '.build/packaging/output/Mango Music.app'
python3 Scripts/Packaging/smoke.py '.build/packaging/output/Mango Music.app'
# Explicit opt-in: public YouTube stream and actual low-volume CoreAudio output:
python3 Scripts/Packaging/smoke.py '.build/packaging/output/Mango Music.app' --live --audio
# No-Xcode Launch Services launch, isolated data home, normal quit:
swiftc -parse-as-library Scripts/Packaging/LaunchProbe.swift -o .build/packaging/launch-probe
.build/packaging/launch-probe "$PWD/.build/packaging/output/Mango Music.app" "$PWD/.build/packaging/launch-home"
```

Run the Swift/Xcode regression commands in VALIDATION.md. Tests accept MANGO_PACKAGED_APP only in test code for explicit helper injection; the shipping app accepts no environment executable override. The validator checks architecture/minimums, dependencies/rpaths including embedded yt-dlp, app/icon metadata, executable permissions, signatures, sandbox absence, unchanged upstream payload and excluded personal/build data.

Launch Services and helper CoreAudio tests are automated evidence. Separately, the user has now manually confirmed the isolated standalone package on this Mac: Finder launch without Xcode, real YouTube search, audible playback, Play/Pause/Next/Previous/volume, manual queue playback, Control Center playback controls, background playback after closing the window and successful Dock reopening, Favorites/History/Queue/settings restoration after quit/relaunch, and Cmd+Q cleanly stopping playback. See VALIDATION.md for all nine reported passes and their limits. Seeking, icon appearance, automatic queue advancement, no autoplay and process/socket inspection were not separately confirmed in this follow-up. All hardware checks that were unverified in Checkpoint 5 remain unverified. macOS 14 declaration/linkage checks cannot replace running on macOS 14. Tests use isolated SQLite/settings and do not modify the user's library.

## Safe /Applications installation plan — approval pending

The isolated app has passed the user's nine reported manual checks. No installation has been performed. A read-only check found no matching immediate app bundle in `/Applications` or `~/Applications`, including both `Mango Music.app` and `MangoMusic.app` and bundles with identifier `com.localmusic.MangoMusic`. The verified source app and the user's existing SQLite database are present; source deep/strict signature verification passes. Recheck all destinations immediately before copying, including symlinks; these observations are not permission to install or replace anything.

Proposed source: `~/Developer/MangoMusic/.build/packaging/output/Mango Music.app`.
Proposed destination: `/Applications/Mango Music.app`.

The following steps are a plan only. Wait for separate user approval before executing installation:

1. Quit every Mango Music copy, including Xcode/debug and isolated/installed copies. Wait for normal persistence flush and playback shutdown. Verify the owned helpers have exited before backing up; do not kill unrelated media processes. Keep the source bundle and its current signature intact.
2. With the app fully closed, create a uniquely named private backup outside the repository, for example `~/Library/Application Support/MangoMusic-Backups/<timestamp>/`. Copy the **entire** `~/Library/Application Support/MangoMusic` folder, including any SQLite WAL/SHM sidecars, into that backup. Preserve `com.localmusic.MangoMusic` preferences with a defaults export if that domain exists. Check backup success before proceeding. Do not delete, move, recreate, migrate or restore over the live database; installation only copies the app. Do not back up a live database by copying just library.sqlite3.
3. Revalidate the isolated source with the commands below. Recheck `/Applications` for both known names, symlinks and any matching bundle identifier. If anything conflicts, stop, preserve it and request a separate replacement decision. Do not merge app bundles or accept Finder's Replace prompt. No replacement is authorized by an approval to install into an empty destination.
4. After approval and only while the destination remains absent, use Finder to copy the **whole** verified Mango Music.app into `/Applications`, or use a guarded Terminal copy of that same bundle with ditto. Recheck absence immediately before copying and stop if a conflict appears. Do not use sudo automatically; if the directory requires authorization, explain the permission requirement and obtain approval for that action. No Homebrew/Python install or security-setting change is needed.
5. Before launch, verify the copied bundle using the commands below, then compare source and destination regular-file hashes and symlink targets to ensure the copy is complete and unchanged. Confirm identifier `com.localmusic.MangoMusic`, bundled-tool marker, arm64 support and expected version. Keep the original isolated source available. If copying or validation fails, do not launch or overwrite another app; preserve the existing database and report the partial copy for review.
6. Open `/Applications/Mango Music.app` explicitly from Finder or the Terminal command below, with all other copies closed. Verify the running application's bundle path is actually under `/Applications`, and update any Dock shortcut that still targets the isolated output. Check the visible icon and Dock reopening from the installed location.
7. Verify real search/audible playback, Play/Pause/Next/Previous/volume, manual queue, Control Center and background playback. Confirm the **existing** Favorites/History/Queue/settings remain, quit/relaunch to check restoration and no autoplay separately, then verify Cmd+Q stops sound, owned helper processes exit and IPC sockets are removed. Earlier isolated-app passes do not establish installed-copy verification.
8. Keep the backup and isolated source until installed-copy verification succeeds. For a future upgrade, back up again and obtain explicit approval before replacing an installed copy; never delete Application Support to upgrade or uninstall an app bundle.

Read-only pre-copy validation, safe to run separately from installation:

```sh
cd ~/Developer/MangoMusic
codesign --verify --deep --strict '.build/packaging/output/Mango Music.app'
.build/packaging/tools/bin/python Scripts/Packaging/validate.py '.build/packaging/output/Mango Music.app'
```

After the separately approved copy, validate and launch the exact installed location:

```sh
cd ~/Developer/MangoMusic
codesign --verify --deep --strict '/Applications/Mango Music.app'
.build/packaging/tools/bin/python Scripts/Packaging/validate.py '/Applications/Mango Music.app'
open '/Applications/Mango Music.app'
```

The installed package needs no development tools at runtime; the optional full validator above uses the project-local build environment and pinned reference cache. Preserve the bundle identifier, preferences domain and `~/Library/Application Support/MangoMusic/library.sqlite3`. Both isolated and installed unsandboxed copies intentionally use the same user data; never run them concurrently against that library. Installation into a different directory does not require a database migration. The backup may contain private library data and must stay outside Git and public uploads.

Until approval, launch the already verified isolated source with:

```sh
open "$HOME/Developer/MangoMusic/.build/packaging/output/Mango Music.app"
```

## Troubleshooting

- Missing/damaged helper: rebuild from verified cached dependencies; do not repair by pointing the packaged app to arbitrary global tools.
- Hash mismatch: stop and investigate provenance; do not disable hash/TLS checks. Dependency updates require a reviewed manifest change.
- Existing output: quit it and move it aside; the build deliberately refuses replacement.
- Build bootstrap mismatch: use Python 3.14 with the pinned arm64 wheels, not a global pip upgrade.
- YouTube failure: Retry requests a fresh stream; service/client changes may require a reviewed yt-dlp update. Do not log URLs, introduce cookies/proxies, or claim universal playback.
- No audible sound: check device/volume and test manually. Null-output tests and a successful Release build are not audible proof.
- CoreAudio changes/sleep/media hardware: remain manual/platform-dependent; no global key tap or permission workaround is included.

## Comparison with the original audit

Installed Homebrew mpv required at least 49 Mach-O files across 42 formula families, 61.3 MiB, with one additional unresolved rpath and minimum macOS 26.0. The minimal mpv is approximately 7.7 MiB and uses only system dynamic libraries, targeting macOS 14. The complete app is approximately 47.37 MiB including the larger standalone yt-dlp runtime and notices. This is not a size comparison against a complete original app: the 61.3 MiB baseline excluded standalone yt-dlp/resources and was a lower bound. Build-only source/wheel caches are excluded from the app.
