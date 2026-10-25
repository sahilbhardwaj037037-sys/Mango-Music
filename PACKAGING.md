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

Launch Services and helper CoreAudio tests are automated evidence, not manual audible/Finder/Dock/Control Center confirmation. All hardware checks that were unverified in Checkpoint 5 remain unverified. macOS 14 declaration/linkage checks cannot replace running on macOS 14. Tests use isolated SQLite/settings and do not modify the user's library.

## Safe local installation and upgrade

No installation is performed by this checkpoint. First test the isolated output: in Finder press Cmd+Shift+G and enter `~/Developer/MangoMusic/.build/packaging/output`, then double-click Mango Music.app. Terminal equivalent:

```sh
open "$HOME/Developer/MangoMusic/.build/packaging/output/Mango Music.app"
```

Confirm audible search/playback, controls/queue, Control Center, background window behavior, Dock reopening, preferences and library restoration without autoplay, and Cmd+Q process/audio cleanup. See VALIDATION.md for the full remaining list. Keep other copies quit so Dock and media routing identify the correct build.

After separate installation approval, quit every Mango Music copy. Check `/Applications/Mango Music.app` and `/Applications/MangoMusic.app`; if either exists, preserve it and obtain explicit approval before replacing it. A user-owned `~/Applications` installation avoids unnecessary administrator permissions; do not silently overwrite there either. Finder installation is a copy of the verified bundle into the approved directory, keeping the prior app as a backup.

For an approved new per-user destination only, this Terminal example refuses overwrite:

```sh
mkdir -p "$HOME/Applications"
if test -e "$HOME/Applications/Mango Music.app"; then
  echo 'Existing app found; preserve it and approve a replacement first.'
else
  ditto "$HOME/Developer/MangoMusic/.build/packaging/output/Mango Music.app" "$HOME/Applications/Mango Music.app"
fi
```

Do not execute installation as part of automated packaging. Verify the copied bundle again before launch. Retain bundle identifier com.localmusic.MangoMusic, `~/Library/Application Support/MangoMusic/library.sqlite3` and the existing preferences domain; do not delete the Application Support directory when upgrading. The same identifier/data path intentionally shares the library with the development app, so do not run multiple copies against it concurrently.

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
