# V2 packaged GUI findings and appearance feasibility

## Current VIS-01 implementation status

**FIX IMPLEMENTED / AWAITING MANUAL VERIFICATION.** Ordinary library and Downloads save status now uses one permanently reserved 22-point line in `MainWindow`, including while idle. Toggling either/both writers no longer inserts/removes layout space. Restoring/error banners and their native Retry buttons remain visible; failed saves do not misleadingly display ordinary saving status. Idle status is hidden from accessibility, and the status line has no controls or hit testing. Persistence operations, MusicLibrary, mpv EOF handling and Repeat/Queue/Shuffle/Autoplay semantics are unchanged.

Focused offscreen native-hosting geometry/message tests and existing repeat, History and download-manager regressions passed: **34 tests in 4 suites**. These tests establish stable save-status layout, not the runtime cause of the original flicker or a successful visual fix. Repeat One/All still require manual retesting in the new packaged build; no GUI was launched.

## Current appearance implementation status

**IMPLEMENTED / AWAITING MANUAL VERIFICATION.** The native menu bar now contains **Appearance → System / Light / Dark** with the selected mode indicated by the native Picker. `AppearanceMode` defaults to System; `@AppStorage("appearanceMode")` persists the enum and falls back to System for unknown values. The window content applies native `.preferredColorScheme`: nil for System, `.light` or `.dark` for explicit modes. No manual system-notification observer, global AppKit appearance mutation, playback restart or library reconstruction was introduced. System changes and explicit→System return require GUI confirmation.

All seven audited brand/status hue occurrences now use `ThemePalette` roles. Dark retains the original `.pink`, `.green` and 0.12 repeat fill; Light uses darker pink/green variants. Native primary/secondary text, sidebar/List/search surfaces, playback-bar materials, dialogs and controls retain semantic styling. Automated contrast checks passed against native Aqua/Dark Aqua window, control and text backgrounds: at least **4.5:1 for highlighted text** and **3:1 for completion icons**. This is bounded color evidence, not a claim about every translucent, selected, disabled or high-contrast GUI state. Native selection, dialogs, materials and actual display appearance remain manual checks.

Four appearance tests cover System/Light/Dark mapping, isolated AppStorage persistence and invalid-value fallback, native-surface contrast, and preservation of the original dark accents. Together with the two save-status tests, **6 tests in 2 suites passed**. No GUI was launched and no appearance preference was written to the production domain. The historical feasibility discussion below describes the earlier Build 200 baseline, not the current implementation.

## Historical Build 200 investigation

29 October 2026, Asia/Kolkata. The following is the original investigation for isolated **2.0/build 200**, before implementation. Its source-line references describe that baseline. No app launch, code fix, theme implementation, build, installation, real-data access or migration was performed during that original audit. The pre-existing shared Xcode scheme modification remains preserved.

## User-reported manual evidence

| Report | Result |
| --- | --- |
| Manual checklist | **30 PASS, 0 FAIL, 1 SKIP** |
| Skipped check | Keyboard/headphone media keys |
| Functional areas reported passing | Playback, downloads, Offline Mode, persistence and macOS integration |
| Additional visual finding | Repeat One/All briefly shake/flicker/glitch near EOF restart/transition; stable again after playback resumes |

These are the user's observations of the isolated packaged app, separate from automated/fixture evidence and earlier Debug manual results. No individual 31-item transcript, exact source downloaded, OS version or device-specific details were supplied in this report; none are inferred. Successful download observations do not independently establish an actual YouTube recording download from a specified source. The existing actual-service-download limitation remains until that evidence is supplied.

**VIS-01 — original Build 200 defect; successor fix awaiting manual verification as recorded above.** The functional checklist's zero failures does not mean zero visual defects. Repeat behavior itself is reported correct. No visual retest is claimed, and the app must not be described as visually defect-free. Keyboard/headphone media keys remain skipped/unverified.

## EOF and presentation trace

| Code reference | Observed implementation and implication |
| --- | --- |
| `Services/PlaybackEngine.swift:85`, `MPVPlaybackEngine.receive` | EOF is guarded by request, playlist entry and `completed`; emits one `.ended`. `playback-restart` emits only `.clockAnchor`. There is no mpv loop setting here. |
| `Services/MPVConnection.swift:203`, `receive` | Parses newline IPC messages and tags events with generation. `MPVPlaybackEngine.load` at line 36 waits for stop acknowledgement before changing generation and reuses the connection. Static review does not establish a duplicate-EOF bug. |
| `ViewModels/MusicLibrary.swift:475`, `receive` | `.ended` calls `beginPlayback` for Repeat One; otherwise `next`. Position updates set progress; duration updates set duration and may update song metadata/save. |
| `ViewModels/MusicLibrary.swift:616`, `next`/`advance`; line 275, `nextPlaylistPosition` | Queue entries precede remaining Favorites; Repeat All wraps the Favorites snapshot; fallback goes through existing Autoplay policy. These semantics are not proposed for change. |
| `ViewModels/MusicLibrary.swift:422`, `beginPlayback` | Clears local-playing state, resets progress/duration to zero, sets loading, creates a new request, schedules persistence, then asynchronously stops/resolves/loads. Expected loading interval is observable by SwiftUI. Repeat One reloads through this path rather than invoking `seek(0)`. |
| `ViewModels/MusicLibrary.swift:748`, `recordStartedPlayback` | First positive clock updates History and schedules another save; History may reorder. |
| `ViewModels/MusicLibrary.swift:803`, `scheduleSave`/`startWriter` | Toggles observable `hasUnsavedChanges` true, then false when the asynchronous save finishes; more than one save interval can occur around a transition. Whether individual writes coalesce into one visible interval depends on scheduling. |
| `Views/MainWindow.swift:10` | Inserts/removes a padded, nonzero-height status row in the outer VStack when saving. This changes the height available to the entire library/sidebar region. This is the strongest concrete explanation for whole-interface shaking. The Downloads save banner at line 18 has the same structural pattern, though normal repeat does not itself imply a download-metadata save. |
| `Views/MainWindow.swift:48` | Toolbar status changes from empty to Loading/Buffering and back, changing intrinsic text width. Potential secondary horizontal movement. |
| `Views/PlaybackBar.swift:61`, line 81 | Local-playing icon is removed/reinserted while loading. Slider range changes from song duration to 0…1 and back, elapsed resets, duration text becomes “—”, and seek becomes disabled/re-enabled. These can explain localized player flicker; they do not prove the root cause of whole-window movement. |
| `Views/LibraryContent.swift:188`, `historyList` | History updates can reorder rows while the History screen is visible. An additional screen-specific effect, not sufficient to explain all Repeat One/All cases. |

All source references above are under `MangoMusic/`. Main actor state changes before the next suspension can be coalesced by SwiftUI; the analysis does not assume every individual assignment paints a separate frame. The asynchronous loading/save intervals are sufficient to expose different view structures across renders.

No explicit repeat/progress animation was found. The only explicit `withAnimation` is `MusicLibrary.toggleSidebar` (line 389), paired with the sidebar transition in `MainWindow` (line 29); EOF does not call it. No view `.id(...)` reset was found. Native control drawing and normal SwiftUI layout updates can still flicker without an explicit animation.

**Assessment:** persistence-banner insertion/removal is the leading static-code hypothesis, with playback-bar/toolbar changes as secondary contributors. Confidence is moderate; the reported glitch was not independently reproduced or frame-profiled. It is not proven to be an mpv playback or EOF-ordering defect.

## Smallest recommended fix — proposal only

First make ordinary save-status presentation independent of the main content's geometry in `MainWindow`: show it in a stable, reserved status location or a non-layout-affecting overlay. Keep genuine restoring/error states and persistence Retry visible and accessible, and preserve existing save scheduling, error handling and quit safeguards. Do not conceal unsaved data by changing `hasUnsavedChanges`, delaying writes or suppressing History updates.

Retest that single view change before broadening scope. If localized player jitter remains, stabilize the toolbar status slot and the local-source icon slot. Consider presentation-only duration/range handling scoped to the current playback request; never show the previous song's duration as authoritative for a different song, and keep seeking disabled until actual capability is available. Do not change engine generations, EOF delivery, queue selection, Repeat, Shuffle or Autoplay. Do not replace Repeat One reload with a seek-based implementation for this cosmetic issue.

For later authorized validation, observe save-banner visibility and layout bounds against EOF/loading/first-clock events using generated short local tracks in the isolated app. Compare Search/Favorites/History/Queue/Downloads screens, narrow and wide windows, Repeat One, multi/single-item Repeat All, queued detours, online/offline, and rapid Next/Stop. Verify save failures/Retry, History counts, persistence, no duplicate EOF and unchanged track-order behavior. Keep VIS-01 open until visual retest passes on the rebuilt package.

## Complete view hierarchy and color inventory

`MangoMusicApp` creates the native Window → `MusicRootWindow` → `MainWindow`. `MainWindow` owns the sidebar/List, persistence banners, toolbar, `LibraryContent` and `PlaybackBar`. `LibraryContent` contains Search/empty/error states, Favorites/History/Queue lists and `DownloadsView`. Rows use `SongRow`; it embeds `DownloadAction`. Confirmation dialogs belong to LibraryContent/DownloadsView. `PlaybackKeyboardHandler` is an NSViewRepresentable bridge with no custom drawing or colors.

This is **7 ordinary SwiftUI View structs across 6 source files**, plus the representable helper. No custom Settings/appearance view currently exists.

| View | Explicit named hue occurrences | Existing semantic styling |
| --- | --- | --- |
| `MusicRootWindow` (`App/MangoMusicApp.swift:42`) | 1 pink tint | Native window and controls |
| `SongRow` (`Views/SongRow.swift:14`, 19, 27) | 3 pink highlights | Primary/secondary text; primary-derived hover fill |
| `PlaybackBar` (`Views/PlaybackBar.swift:35`, 37) | 2 pink repeat styles | Secondary text, `.bar`, native sliders/toggles |
| `DownloadAction` (`Views/DownloadsView.swift:18`) | 1 green completion mark | Native buttons/progress |
| `MainWindow`, `LibraryContent`, `DownloadsView` | 0 | `.background`, `.bar`, primary/secondary/quaternary, native Lists/dialogs |

Counting explicit named brand/status hues, **4 of 7 views across 4 files use 7 hue occurrences** (three feature views plus the root tint). This count excludes semantic `primary`/`secondary`, transparent `clear`, and system materials. There are **no custom RGB/hex palettes or forced black/white text/background colors** in the inspected SwiftUI source. Fixed opacity choices also exist: hover 0.035, repeat fill 0.12, search surface 0.5; review their contrast in both schemes. There are no color-set assets; asset catalogs currently contain the icon and catalog metadata.

## System / Light / Dark feasibility — proposal only

1. **Current forcing:** no `.preferredColorScheme`, color-scheme environment override, `NSAppearance` assignment or appearance-forcing Info.plist key is present. The app currently inherits macOS appearance; pink tint does not force Dark Mode. The packaged plist likewise has no appearance-forcing key.
2. **Persistence:** introduce a small UI preference with raw values `system`, `light`, `dark`, default/fallback `system`, stored under a new UserDefaults key such as `appearanceMode`. `@AppStorage` at the app/root UI layer is sufficient; do not add it to SQLite, downloads metadata or the playback controller. Use a menu Picker or a small native Settings scene, with explicit labels for all three choices. No schema migration is needed. Test only in isolated preference storage.
3. **Application:** apply the optional color-scheme preference at the window/root boundary: System → no override (`nil`), Light → `.light`, Dark → `.dark`. Let SwiftUI/macOS update inherited appearance rather than observing system notifications manually. Use the effective `@Environment(\.colorScheme)` only where a custom token actually requires it; that value reflects the override when one is selected, not necessarily the system preference. Verify explicit→System resets and titlebar/dialog/Settings-window consistency on the supported macOS version.
4. **Tokens:** centralize brand accent, completion/success, repeat selection fill and hover/search fill roles. Retain native semantic foregrounds/materials. Pink and green are named system colors, not fixed RGB values; aliasing them to roles is small cleanup, with optional appearance-aware assets only if contrast testing requires variants. Avoid indiscriminate replacement of semantic styles with a custom palette.
5. **Dark preservation:** keep the existing materials, hierarchy, pink accent, spacing and native controls. Explicit Dark should reproduce the current dark-system presentation. Capture an isolated baseline before later edits; this audit did not generate screenshots. Avoid introducing global AppKit appearance mutations or recreating `MusicLibrary` when a setting changes.
6. **Light design:** a major redesign is not indicated by source inspection because most surfaces/text are already adaptive. Budget contrast tuning and visual verification for pink/green, hover/selection fills, search field, disabled/loading states, native List selection, confirmation dialogs and toolbar/window chrome. Source inspection alone cannot establish that all existing Light Mode states look correct.

Apple documents [AppStorage-backed settings](https://developer.apple.com/documentation/foundation/adding-a-settings-interface-to-your-app), [preferredColorScheme](https://developer.apple.com/documentation/swiftui/view/preferredcolorscheme(_:)), and automatically updated [environment values](https://developer.apple.com/documentation/swiftui/environment). The approach above is a project-specific recommendation based on those APIs, not implemented code.

## Complexity, sequencing and release readiness

Planning estimates, not measured implementation commitments: the first banner-layout fix is low complexity, roughly half a developer day including an isolated visual retest. Appearance preference/tokens are low-to-moderate complexity, roughly 1–2 developer days including System/Light/Dark GUI and contrast regression checks. A difficult-to-reproduce residual glitch or additional supported-device testing could extend either estimate.

Recommended order: (1) confirm VIS-01 against banner/layout changes in an isolated reproduction; (2) authorize and implement the minimal presentation fix; (3) rebuild/retest Repeat One/All and unchanged ordering/persistence, then close VIS-01 only with evidence; (4) add the appearance preference and minimal role tokens separately; (5) verify all three appearance choices, live system changes, explicit→System return, relaunch, dialogs, native controls, and that changing appearance does not restart audio or register duplicate media handlers.

**Remaining readiness items:** VIS-01 is an unresolved visual defect and should be resolved/retested before declaring final visual readiness. Keyboard/headphone media keys remain skipped. The requested appearance preference is not implemented; it is a requirement gap if included in the intended release scope. Existing actual-YouTube-download provenance, actual macOS 14 runtime, platform/device and private-signing/distribution limitations remain as documented; this aggregate report does not independently resolve them. No functional playback failure was reported. Installation and real-data migration remain separately authorized Phase 4B work, not part of this investigation.
