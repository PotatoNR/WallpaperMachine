# Verification log archive — 2026-11 and earlier

Retired entries from [../verification-log.md](../verification-log.md), moved
here when that log was capped at its ten newest entries. No recorded result was
rewritten: each entry is reproduced verbatim, and the only edit is that
relative Markdown links gained one `../` for this file's extra directory
level.

These are historical results about the trees they were taken on. They are not
evidence about the current tree and must never be cited as such.

## 2026-11-12 — Mute or Reduce volume when windows cover the desktop (#192)

Written on a Linux host without Xcode or Swift: nothing native was compiled or run.

- `python3 scripts/test.py --python-only` — exit 0; 34 script test files OK, including `test_localization_catalogs.py` and `test_panel_localization.py` for the three new catalog keys in pt-BR, ko, ja, zh-Hans and zh-Hant
- `python3 scripts/test.py` (XcodeGen and the native unit tests) — not run: no macOS host. New and changed tests in `PlaybackPolicyCompositionTests`, `PlaybackPreferencesTests`, `WallpaperBackupTests`, `OtherAudioVolumeSettingsTests` and `SettingsSectionsLocalizationTests` have not been compiled
- Release build — not run
- Gaps: real coverage-probe occlusion and audible output not checked; the four-segment Quick Settings module not checked visually in any language; translations are machine-written and want a native review

## 2026-11-12 — Desktop widgets workspace: canvas, tabbed inspector, handles, ready-made widgets

- Settings › Desktop Widgets without a search is now a workspace (large canvas, layers, inspector with Content/Text/Style/Position tabs); search still lists every row.
- Canvas: corner handles resize, a knob turns (15° snap, Command free, double click upright), arrow keys nudge, context menu; preview frame raised to 2048 px.
- Ready-made widgets (11 presets, groups laid out by measured size) via a popover and the empty inspector; style swatches replace the Apply Style menu.
- python3 scripts/test.py --only WidgetsSettingsTests: 16 passed (new: handles/nudge, presets layout and limit, inspector tabs, workspace layout at 460/980/1400 in en and ja for every tab).
- python3 scripts/test.py: 4924 passed, 0 failed, 70 skipped.
- Offscreen renders (testSnapshotsOnRequest with TEST_RUNNER_WALLPAPER_MACHINE_WIDGET_SNAPSHOTS) checked by eye in English, dark: empty, each tab, turning, narrow, search.
- Not checked: the live app (no Release build, no desktop run); pointer cursors, real drags and the popover on screen; other languages' renders; light appearance.

## 2026-11-12 — Desktop widgets introduction after an update

A window that introduces desktop widgets once to people updating from 1.10.0 or older, opening Settings › Desktop Widgets.

- `python3 scripts/test.py --only FeatureIntroductionTests --only FeatureIntroWindowTests --only ActivationPolicyRuleTests` — passed
- `python3 scripts/test.py` — exit 0; 4990 tests: 4921 passed, 69 skipped
- Offscreen renders of the window (`FeatureIntroWindowTests.testSnapshotsOnRequest`, `WALLPAPER_MACHINE_FEATURE_INTRO_SNAPSHOTS`) checked by eye in en, zh-Hans, zh-Hant, ja, ko and pt-BR, light and dark
- Gap: not opened on the desktop; the launch path (window over the panel, Set Up opening Settings › Desktop Widgets, the Dock icon) was not exercised in a running app

## 2026-11-12 — Desktop widget fonts, effects and clock options

Installed font families, italic, letter spacing, line height and case; gradient fill, accent colour, outline, glow, a configurable shadow, a background plate and rotation; style presets; clock leading zero, AM/PM and stacked layout; clock-face dial marks, numbers and ring. Rebased onto the layers and snapping change (05e13ded); the preview's frame, snapping and the Center buttons use the turned box of a rotated widget.

- `python3 scripts/test.py` on the rebased tree — exit 0; 4979 tests: 4911 passed, 68 skipped
- Offscreen renders of each style preset, a stacked clock, an italic installed family, a turned outlined date, numbered and ticked clock faces, an accented calendar and a gradient with glow, drawn by DesktopWidgetView into PNGs by a throwaway test (not committed) and inspected
- Not checked: widgets on a real desktop, over moving wallpapers and across Spaces; snapping a rotated widget by hand

## 2026-11-12 — Desktop widgets: layers list, snapping guides, Center buttons

- python3 scripts/test.py: Python stage passed; native 4906 passed, 0 failed, 68 skipped.
- Targeted: WidgetsSettingsTests, DesktopWidgetSnappingTests, DesktopWidgetTests, DesktopWidgetControllerTests, SettingsSectionsLocalizationTests passed.
- Covered: layer order (add in front, move, refused stale drop, duplicate), window stacking, preview stacking, snap lines and guides, drag snap on the display and Command bypass, Center buttons for a left-aligned text.
- Gap: the panel and the desktop windows were not looked at; drag-and-drop of list rows, the guides' look over real wallpapers and window stacking on a real desktop are unchecked by hand.
- App not rebuilt.

## 2026-11-12 — Menu bar energy use (issue 188)

- Added Settings → General → Show energy use in the menu bar (off by default) and an Energy use row in the menu bar panel, both from one MenuBarEnergyMeter (5 s for the figure, 2 s with the panel open, nothing while unattended).
- Targeted: python3 scripts/test.py --only MenuBarEnergyMeterTests --only EnergyReadoutTests --only StatusPanelControllerTests --only StatusPanelRenderTests --only WallpaperPresentationPolicyTests --only SettingsSectionsRenderTests --only EnergyUsageMonitorTests --only WallpaperBackupTests: 155 passed.
- Gate: python3 scripts/test.py: 4897 passed, 0 failed, 68 skipped.
- Not checked: the status item drawn in the real menu bar (no desktop run, no Release build); the figure's width beside other menu bar items.

## 2026-11-12 — Integrate Steam sign-in retry recovery

- Integrated the fix from fix/steam-sign-in-retry-186 onto current main; removed an obsolete sign-in-only assertion and documentation after that API was removed.
- `python3 scripts/test.py --only PanelDownloadActionsTests --only DownloadDialogResolutionTests --only DownloaderFailureOutputTests`: 42 passed, 0 failed, 0 skipped.
- Initial full gate: 4888 passed, 1 failed, 68 skipped; the welcome accessibility regression also failed on unchanged main. Fixed separately in a1f9824.
- `python3 scripts/test.py --only WelcomeRenderTests --only FirstRunModelTests --only PanelDownloadActionsTests`: 59 passed, 0 failed, 0 skipped.
- `python3 scripts/test.py` after the welcome fix: Python checks passed; 4889 native tests passed, 0 failed, 68 opt-in media/network/reference checks skipped.
- Steam timeout/password rejection, corrected-account retry, QR recovery through import, an existing QR session, and normal transfer retries were exercised with offline fakes.
- Live Steam sign-in, the reporter’s network/account, desktop interaction and VoiceOver remain unverified. No Release build or renderer changes.

## 2026-11-12 — Control panel UI critique fixes (ws1-ws7) on claude/ui-critique-fixes

- Scope: 34 local commits over main 54227ed3: Apply/Play symbols and wording, Workshop inspector Apply and Command-Return, staged-edit footer and Not applied marks (Rust bridge staged flags), collapsible display cards, welcome Skip setup and the delayed support prompt, P3 polish, and the panel type scale, shared buttons, scrims, tile marks and design-token lint.
- python3 scripts/test.py on the final tree: 4887 passed, 0 failed, 68 skipped; script tests incl. test_panel_design_tokens, catalogs and doc links OK. Each workstream also passed the full gate before its commits.
- Known flake seen once under full-gate load: WebWallpaperPageTests.testRefusedOrReplacedNavigationDoesNotFailTheWallpaper (10 s WebKit deadline) in ws3's first run; the rerun passed. Not caused by this branch.
- python3 scripts/check_rust.py after the bridge change: core 429, bridge 961, shader 958 and core-integration passed, 0 failed; desktop-window tests excluded (need an authorized desktop run). No Rust or bridge change since.
- python3 scripts/check_renderer.py on the final tree: exit 0; 12 generated scenes pixel-equal pooled vs isolated, 0 reload cycles; 19 local-corpus and energy checks skipped (no corpus or opt-ins), so asset coverage is skipped, not passed.
- Not rendered: no Release build, no app launch, no screenshots. Unverified by eye: paused vs waiting rings, scrim strengths, the new markHeart pink and the library mark's contrast, the translucent secondary fill in dark mode, the View menu titles, the welcome Skip setup and Escape routing.
- Not covered by tests: whether a click (not a key) focuses a tile and makes its ring show the cancel mark instead of the percentage; pixiv Command-Return wiring (manual smoke only); the scope bar's middle tier; translations without native-speaker review.

## 2026-11-11 — Feeling good? offers Sponsor on Open Collective; README lists Open Collective sponsors

The support prompt's second choice opens MMFoundation's Open Collective (approved by Open Source Collective on 2026-11-11) instead of the website's pricing page, with new strings in every shipped language; the four READMEs gain a sponsors block drawn by Open Collective.

- `python3 scripts/build.py --renderer-only` — OK; the checkout's `libwallpaper_bridge.a` predated main's Steam QR sign-in bridge, so the first targeted build failed to link
- `xattr -cr build/Build/Products/Debug` — cleared after the extension's CodeSign refused Finder/File Provider attributes (docs/build.md)
- `python3 scripts/test.py --only SupportPromptPresenterTests --only PanelSupportPromptTests --only PanelPerformanceDataTests --only ExternalLinkTests` — 32 passed; `--only PanelSharingTests` — 5 passed
- `python3 scripts/test.py` — exit 0: every Python suite, XcodeGen, and 4,843 native tests passed, 0 failed, 68 skipped of 4,911 (two main-thread API runtime warnings)
- Not checked: the sheet's longer row in six languages on screen (no desktop run, no Release build); the README block through GitHub's image proxy (rendered with GitHub's Markdown API, images loaded from Open Collective directly)

## 2026-11-11 — Wallpaper-switch teardown and lock-screen recovery (issue 184)

- `python3 scripts/test.py` in an isolated HEAD checkout plus this patch: 687 Python tests passed; native gate 4,741 passed, 66 skipped, zero failures. The shared checkout was blocked by its pre-existing missing `CLAUDE.md`; an earlier targeted build also encountered concurrent desktop-widget API edits.
- Native result: one main-thread runtime warning, attributed by the detailed xcresult issue to `AppUpdateTests.testSignatureCheckRefusesAnUnsignedOrAlteredCopy()`; no source location.
- `scripts/check_renderer.py` entry point with its output redirected to the task directory: 3,520 passed, seven local-asset/opt-in tests skipped; all 12 generated image comparisons and eight projects with two reload cycles passed. GPU and cadence checks ran; timer diagnostics were collected.
- `python3 scripts/check_rust.py`: all four groups passed (2,499 tests); five desktop-window cases were explicitly excluded, and desktop/media/network opt-ins remained disabled.
- The retiring-renderer acknowledgement regression and the pending-Metal-command release regression failed before their respective fixes and passed afterwards. Interrupted refreshes and genuine repeated renderer exits remain covered.
- No live desktop run, Wallpaper Engine comparison, or Release app build. The exact Apple Metal HUD crash on the reported macOS build remains unverified; tests cover the identified teardown and acknowledgement races.

## 2026-11-11 — Review fixes for the Steam QR sign-in and native downloads

Addresses the PR review: CM logon cleanup, endpoint fallback and cancellation; HTTPS-only content servers with failover promotion; Workshop app check; free-space check from the manifest size; QR actions through PanelController and cancelled when the dialog closes; localized native failure messages.

- `python3 scripts/test.py` — 4839 tests: 4767 passed, 70 skipped, 2 failed: WebWallpaperErrorStackTests/testStacksReadAsV8WritesThem and WebWallpaperWindowCompositionTests/testPreservingLiveSurfacesLeavesOtherWindowPoliciesIntact, both failing the same way on main on this Mac
- `python3 scripts/test.py --only SteamCMConnectionTests SteamContentClientTests NativeWorkshopDownloadTests SteamQRSignInTests SteamKeyValuesTests WorkshopStoreTests DownloadQueueTests` — 58 passed, including 10 new tests (logon cleanup, endpoint fallback, cancellation, wrong app, free space, server promotion, HTTPS-only servers, joined logon failure, message mapping)
- `python3 -m unittest scripts.tests.test_localization_catalogs scripts.tests.test_panel_localization` — 17 passed
- Not covered: live Steam and the UI were not rerun after these fixes

## 2026-11-11 — Desktop widgets: seven more kinds

- Added Text, Countdown, Greeting, Battery, Sunrise and sunset, Analog clock and Month calendar widgets; clocks and dates gained Time zone and Label, dates gained month-year, week and day-of-year styles and other calendars.
- python3 scripts/test.py --only DesktopWidgetTests --only DesktopWidgetControllerTests --only WidgetsSettingsTests --only LowBatteryTests --only SettingsSectionsLocalizationTests: 49 passed.
- python3 scripts/test.py: 4779 passed, 66 skipped, 0 failed (run with CLAUDE.md restored temporarily; the working tree has it deleted, which fails test_doc_links).
- Not checked: how the clock face, month grid and multi-line text look on a real desktop; no Release build.

## 2026-11-11 — Desktop widgets

Clocks and dates drawn on the desktop over any wallpaper (Settings › Desktop Widgets); see [desktop widgets](../../features/desktop-widgets.md).

- `python3 scripts/build.py --renderer-only` — OK; the renderer library was stale against the committed bindings (`set_audio_gain`), rebuilt so the app links
- `python3 scripts/test.py --only DesktopWidgetTests --only DesktopWidgetControllerTests --only WidgetsSettingsTests` (plus the Settings search, localization and window render classes) — 45 passed
- `python3 scripts/test.py` — exit 0; Python stage OK; 4831 native tests: 4765 passed, 66 skipped, 0 failed
- The Settings page was drawn off screen in light and dark and checked by eye; the Arrange picture matches the desktop geometry
- Not checked: widget windows on a real desktop (over scene, video and web wallpapers, across Spaces, with the notch strip, after sleep); no desktop run was authorized. No Release build

## 2026-11-11 — Reduce volume while another app plays sound (issue 182)

Adds Reduce volume beside Mute under When another app plays sound, with a Reduce volume to slider (0% to 100%, default 30%). The bridge gains a transient audio gain (set_audio_gain) multiplied into each saved volume for scenes, web pages and native video; no saved volume is rewritten.

- `python3 scripts/build.py --renderer-only` — exit 0; renderer built and Swift bindings regenerated (one added call, `setAudioGain`).
- `python3 scripts/check_rust.py` — exit 0; 2,499 passing tests (core 429, bridge 956, core-integration 20, shader 1,094), 0 failed. Five desktop-window tests explicitly excluded; desktop/media/network opt-ins disabled.
- New bridge tests: the gain scales an open scene's volume live and restores the saved one, a volume or a mirror's volume changed meanwhile is saved whole and played reduced, a wallpaper applied meanwhile starts reduced, web and native-video descriptors carry the product, a display refresh does not reload a turned-down scene, and a gain outside 0 to 1 is refused.
- `python3 scripts/check_renderer.py` — exit 0; all 12 generated scenes matched between pooled and isolated runs; seven local-asset-dependent cases skipped.
- `python3 scripts/test.py` — exit 0: all 32 Python suites, XcodeGen, and 4,739 native tests passed, 0 failed, 66 skipped of 4,805, the skip count of the gate runs logged before it (opt-in media, live Steam and reference jobs). An earlier targeted run failed in CodeSign on build-product extended attributes; `xattr -cr build/Build/Products/Debug`, as [build](../../build.md#troubleshooting) says, cleared it.
- Three runtime warnings, all the known main-thread one (a method that should not be called on the main thread); none was traced to this change.
- New native tests cover the level preference (default, range, corrupt values, reset, one change posted), its backup validation, the policy's gain channel (only while other sound plays and Reduce volume is chosen, a new level delivered while the rule holds, mute still silences, refused delivery retried, teardown restores) and the panel row (offered beside Mute, shown only while chosen, out-of-range refused).
- Not checked: the lower volume was not heard on a real output, and the slider was not operated in the running app; no desktop automation and no Release build. A [manual smoke](../manual-smoke.md#audio-responsiveness) item covers both.

## 2026-11-11 — Workshop inspector removal (#183)

- Added Move to Trash for installed Workshop items using the existing confirmed library removal action; collections remain open-only.
- Reused the existing label and translations in all shipped app languages; documented removal in workshop-downloads.md.
- python3 scripts/test.py --only WorkshopInspectorTests: 13 passed.
- Initial full gate blocked by the pre-existing deleted CLAUDE.md documentation link; temporarily restored its relative symlink for validation.
- Parallel full gate: 4722 passed, 5 timing/session failures, 66 skipped.
- python3 scripts/test.py --serial: 4727 passed, 0 failed, 66 skipped; one runtime warning.
- Opt-in media/network and desktop UI checks were not run; visual behavior was not manually checked.

## 2026-11-10 — Steam QR-code sign-in and native Workshop downloads

Downloads signed in with a QR code run through the app's own Steam client (App/Services/Steam/) instead of SteamCMD; the Rust bridge unpacks depot content (decompress_steam_content).

- `python3 scripts/test.py` — 4830 tests: 4759 passed, 70 skipped, 1 failed: WebWallpaperErrorStackTests/testStacksReadAsV8WritesThem, which fails the same way on main without this change
- `python3 scripts/check_rust.py` — passed; `cargo test -p wallpaper-bridge steam_content` — 3 passed (zstd, VZip LZMA, zip stored/deflated, CRC and truncation)
- `python3 scripts/test.py --only Steam…Tests NativeWorkshopDownloadTests` — 23 passed against a scripted Steam: QR flow, logon, Multi routing, manifests, chunks, unsafe paths, PICS, queue import, shared connection, refused token
- `WALLPAPER_MACHINE_NETWORK_TESTS=1 WALLPAPER_MACHINE_STEAM_TOKEN_FILE=… python3 scripts/test.py --only SteamNativeLiveTests` — 2 passed against live Steam (QR session; logon with a QR token and download of Workshop item 3521337568); the later depot-431961 chunk check was not run live
- Manual Debug-build run: QR sign-in from the panel, 8 Workshop items and the shared scene assets downloaded and imported natively; the log shows no SteamCMD run and no staging left behind
- Not covered: welcome guide has no QR option yet; no free-space check before the ~800 MB scene depot; native jobs restart from zero after a pause

## 2026-11-10 — Library tile menu, drop to import, keyboard and batch favorites; service fixes

Installed gains a right-click menu on tiles (the inspector's More actions list, shared as WallpaperActionItems), files dropped on the page import, Command-Delete and Command-Return on the grid, File › Import… and Refresh Library, and a favorite tool for the ticked selection. The same change fixes six service defects (unreadable saved entries no longer erase their neighbours; an automatic command replacing a queued rule or Focus change no longer marks it handled; a day and night display keeps a manual choice across a relaunch; a shuffle round ends without a wallpaper that keeps failing; a stale Steam request no longer signs out a newer session; equal day and night start times are refused), adds feedback where actions were silent, and gathers the renderer's leftover material constants into one log line per scene.

- `python3 scripts/test.py` — exit 0; 4789 tests: 4723 passed, 0 failed, 66 skipped (the first run failed two tests that asserted the old batch-limit error; both were updated and the gate rerun)
- `python3 scripts/check_renderer.py` — exit 0; generated scenes pixel-equal pooled and isolated, 0 reload-cycle diagnostics; the local-corpus tests (particle corpus, local projects through the native backend, poster pictures, energy, corpus stamps, a local clip) skipped: no corpus configured
- New unit tests: PreservedJSONTests; unreadable entries in WallpaperAutomationStoreTests, PlaylistStoreTests, WallpaperCollectionStoreTests and PlaybackPreferencesTests; queue outcomes in UserCommandQueueTests; a Focus change replaced by a reload in WallpaperAutomationSchedulerTests; relaunch and shuffle rounds in PlaylistSchedulerTests; the Steam session in WorkshopSourceTests
- New panel tests: add-to-playlist and refresh notices, the unreadable-library state, the failed-still mark (offscreen render), drop import, the favorite tool, Command-Delete and Command-Return on the hosted grid, equal start times, preset and batch-limit refusals
- Renderer: two gtest cases for UnmatchedConstantTally in material_constant_behavior_test; no frame output changed, so no Wallpaper Engine reference comparison was made
- Not exercised: the tile's context menu, the drop outline and a real Finder drag, and the File menu items with their shortcuts in a real window. They need desktop control, which was not authorized; the menu's item rules are InspectorPolicy's existing tests, and the drop and menu actions are covered through the model
- Not rebuilt: no Release build was made, so the delivered app does not contain these changes
- Runtime warnings in the result bundle (2, main-thread call) come from AppUpdateTests and WebMOpeningTests, which this change does not touch

## 2026-11-09 — Web wallpaper submitted background for Stage Manager

- The desktop web container now submits one opaque black 1×1 Metal frame per backing layer and retains it through resize and page suspension, with no recurring GPU submission or rendering loop. The bounded allocation trade-off was approved; battery impact was not measured.
- On the Dell display, the user reported that a submitted surface kept Belle smooth, removing it or replacing it with an empty Metal queue brought the freeze back, and using the submitted surface as the existing black background looked normal and stayed smooth.
- The earlier tag-only Release candidate and native backing-flattening override failed the visible Stage Manager check. The override is removed; the existing transition tag remains alongside the submitted background.
- `python3 scripts/test.py --only WebWallpaperWindowCompositionTests` — before the Metal implementation, 3 passed and 2 new regressions failed; final run: 7 passed, 0 failed, 0 skipped. Coverage includes a real submitted frame, resize, suspension/resume and the no-Metal fallback.
- `python3 scripts/test.py` — passed: Python checks and XcodeGen succeeded; native suite: 4,698 passed, 0 failed, 66 skipped. Three unrelated runtime warnings concerned main-thread use in video and app-update tests.
- `python3 scripts/build.py --renderer-only` rebuilt current upstream dependencies; `python3 scripts/build.py --swift-only --configuration Release` passed. No renderer source changes were made by this fix.
- The clean Release app was restarted with the original covered-desktop preference restored. Runtime inspection confirmed attached web views and submitted 1×1 Metal backgrounds on both the Dell and built-in displays, with no diagnostic layer or runtime patch.
- The additional clean-build Stage Manager and Mission Control visual check was requested but remains unconfirmed. The accepted smoothness result above is from the working prototype, not a claimed final-build visual observation.
- Wallpaper Engine reference-frame comparison and measured power consumption were not performed; this change addresses host-window presentation rather than wallpaper content rendering.

## 2026-11-09 — Issue #177 rebuilt candidate rejected

- The user tested the Release app from local commit 5cb12719 and reported that the issue was not fixed. Its prior passing gate and manual flag-toggle trials do not establish a fix.
- Read-only process inspection confirmed the running executable was build/Build/Products/Release/WallpaperMachine.app/Contents/MacOS/WallpaperMachine.
- WindowServer readback acknowledged tag 55 on both the Built-in Retina Display and DELL U2725QE web windows. The debugger detached after inspection; no window policy was changed.
- The built-in window contained its live web view. The Dell window contained an NSImageView suspension poster; session logs recorded repeated presentation suspend/resume decisions for display 3.
- The foreground-app rule was Keep running, covered-desktop behavior was the default Pause, and the power source was External. The relationship between this pause and the reported stutter remains unconfirmed; a controlled manual retest with the coverage rule disabled is pending authorization.
- No new fix, desktop automation, app restart or settings mutation was performed. The candidate remains local and must not be treated as resolving #177.

## 2026-11-09 — Web transition composition final review (#177)

- Reviewed the web-window transition policy and live-resize restoration against current main; retained the general fix without wallpaper-specific behavior or per-frame work.
- python3 scripts/test.py --only WebWallpaperWindowCompositionTests: 3 passed, 0 failed, 0 skipped; reads WindowServer policy on unordered windows and exercises an AppKit live-resize cycle.
- python3 scripts/test.py: all 32 Python suites passed; 4,667 native passed, 0 failed, 66 skipped. The skipped asset, media, network and desktop-dependent checks are not passing coverage.
- One runtime warning in AppUpdateTests.testSignatureCheckRefusesAnUnsignedOrAlteredCopy: a method called on the main thread may cause unresponsiveness; unrelated to web transition composition.
- python3 scripts/build.py --swift-only --configuration Release: passed; built build/Build/Products/Release/WallpaperMachine.app. Existing linker deployment-target warnings remain.
- Prior same-window Belle manual trials recorded smooth playback with tag 55 set, stutter after clearing it, and smooth playback after setting it again; the prior rebuilt app readback also showed the flag set automatically.
- Final rebuilt-app visual acceptance remains unconfirmed. No desktop automation, wallpaper changes or app restart were performed during this final review. No valid Wallpaper Engine frame comparison is available.

## 2026-11-09 — Preload desktop wallpapers and preserve their uncleared frames

- Scope: serial preparation of inactive desktop scene, video and web wallpapers, parked-instance reuse and bounded shared still windows for repeated assignments.
- python3 scripts/build.py --renderer-only passed and regenerated Swift bridge bindings; XcodeGen regenerated the project for the source and test additions.
- Targeted scripts/test.py run passed: 240 native tests across parking, pinning, replicas, switch holds and video/web host lifecycles.
- Full scripts/test.py gate passed with local-only XCODE_XCCONFIG_FILE bundle identities: 4,686 native tests passed, 66 skipped; all 32 Python test modules passed.
- scripts/check_rust.py passed in an isolated child-process home with serial tests: core 428, bridge 941, all selected integration and shader suites passed; five desktop-window cases were excluded.
- Five targeted Metal regressions passed three consecutive rounds (15/15); all 77 render graph contract tests passed.
- python3 scripts/check_renderer.py passed: all registered binaries succeeded, 12 generated pooled/isolated frame comparisons matched and eight generated projects reloaded twice successfully.
- Uncleared output preserves prior pixels before partial writes; overflow coverage asserts draw admission without an Inf/NaN pixel-equivalence claim, while finite inputs retain exact frame comparisons.
- Asset-dependent renderer cases were skipped; desktop/media/network opt-ins, real Space animations, WindowServer stacking and Wallpaper Engine reference comparisons were not checked. No Release app was built or installed.
- Gitleaks scans of 1,278 existing commits, candidate staged differences and full staged files found no leaks; agent paths, private assets and build output are excluded.

## 2026-11-08 — Issue 177: rejected candidates and visible-frame regression

Issue #177 remains unresolved. The user rejected the delivered candidate after repeating the Stage Manager desktop transition; passing callback timing and unit checks did not establish smooth visible playback.

- The `isVisible` override and its offscreen-only regression were removed; they did not fix the reported desktop behavior.
- A Release candidate adding `canJoinAllApplications` also still froze with original Belle. That source change was reverted.
- That candidate's checks passed: `python3 scripts/test.py --only WebWallpaperSuspensionTests` (24 passed), `python3 scripts/test.py` (32 Python suites; 4,658 native passed, 66 skipped, 0 failed; 3 runtime warnings), and `python3 scripts/build.py --swift-only --configuration Release`. These results are not a fix verification.
- During a user-confirmed 90-second freeze reproduction, animation callbacks continued with no visibility changes; after startup, the largest recorded callback gap was 29 ms. Callback timing does not measure screen presentation.
- The asset-free WebGL, Canvas 2D and CSS [continuity fixture](../../../Tests/UI/Fixtures/WebFrameContinuity/project.json) also froze, including with the control panel closed. A one-tile library did not prevent the freeze. The [manual regression](../manual-smoke.md#native-desktop-posters-and-mission-control) requires repeated visible transitions because the failure is intermittent.
- Raising the web window one level, with coverage probes moved above it, failed a controlled repeat: the same window retained its raised level while the user observed freezes. An earlier smooth run was inconclusive because wallpapers changed during it. Original levels were restored.
- Wallpaper Engine comparison was **not done**: the available VM's captures did not show Belle, so they cannot serve as reference frames. The VM was suspended again.
- `python3 scripts/tests/test_doc_links.py` passed 11 tests. No fix was committed.

## 2026-11-08 — Belle Release build and Stage Manager retest

Requested Release build and repeat desktop test for [issue #177](https://github.com/MMFoundation/WallpaperMachine/issues/177). The candidate visibility change remains uncommitted; the reported Stage Manager stutter is **not verified as resolved**.

- `python3 scripts/build.py --swift-only --configuration Release` — exit 0; built and ran `build/Build/Products/Release/WallpaperMachine.app`, binary UUID `C60DA559-5CD2-3C21-BE10-2ED77F3A5D02`. The installed app was not overwritten.
- Five automated panel-focus / Show Desktop cycles in installed 1.9.3 and five in the updated build on macOS 27.0.1, external 3840×2160 @2x / 120 Hz, wallpaper 60 fps / scale 1.0. A disposable copy measured animation callbacks and calls into the wallpaper's drawing function; production code contains no wallpaper detection.
- Longest measured draw gap during the automated cycle intervals: baseline 95 ms, updated 113 ms. Neither reproduced the reported approximately 600 ms hold. No page visibility changes or forwarded desktop clicks were recorded in those intervals; these cycles are not the exact mouse-click reproduction.
- The user reported visible stuttering in reply to the baseline question after the updated app had started. That observation lacks a timestamp identifying the binary/transition, and no separate updated-build manual verdict was received. Page callback timing cannot exclude a compositor-held frame. Current main also includes earlier changes absent from installed 1.9.3, so this is not an isolated patch A/B.
- The unchanged candidate code previously passed the full routine gate: 32 Python suites, XcodeGen, 4,659 native passed, zero failed, 66 skipped. The gate was not repeated for this build/test-only follow-up. Wallpaper Engine comparison remains **not done**: the available VM's captures did not contain Belle; no pixel metrics are claimed.
- Restored Lost Tower on the primary display and Stage Manager off, retained the internal display wallpaper, moved the temporary import to Trash and cleared the search. The updated Release build remains running. No commit, push or issue closure.

## 2026-11-08 — Desktop web scheduling during window visibility changes

Investigation of [issue #177](https://github.com/MMFoundation/WallpaperMachine/issues/177). The change repairs an independently reproduced window-visibility scheduling gap; its connection to the reporter's exact Stage Manager transition remains unconfirmed.

- The attached video holds different last frames for roughly 0.6 s on repeated returns to the desktop. The attached logs show no matching host presentation suspension; the CPU sample was taken later with another wallpaper active.
- WebKit checks window visibility separately from occlusion. An attached desktop page now remains schedulable until the host suspends it; no wallpaper identification, timer, polling loop or extra render pass was added.
- Before the fix, `python3 scripts/test.py --only WebWallpaperSuspensionTests/testDesktopPageSchedulingFollowsHostSuspensionWithoutAnOrderedWindow` failed: zero animation frames while the host permitted playback.
- After the fix, `python3 scripts/test.py --only WebWallpaperSuspensionTests --only WebWallpaperHostLifecycleTests --only WebWallpaperFramePacingTests` passed: 74 tests, no failures or skips. The regression also measures stopped frames during explicit suspension and resumed frames without reloading.
- `python3 scripts/test.py` passed: all 32 Python suites, XcodeGen, and 4,659 native tests; zero failures, 66 skipped of 4,725. Skips: 62 opt-in video/media asset cases, one live Steam install, two Workshop cases and the opt-in web reference renderer.
- One runtime warning came from `AppUpdateTests.testSignatureCheckRefusesAnUnsignedOrAlteredCopy()`: a method called on the main thread may cause UI unresponsiveness. No warning was attributed to the new scheduling regression.
- Wallpaper Engine comparison **not done**. The Windows VM was available, but two muted `scripts/we_reference.py capture` attempts produced a black desktop with the Start menu, not Belle. The attempted native reference render also failed with `DecodingError.typeMismatch`; no valid before/after pixel metrics are claimed.
- Authorized desktop probing of installed 1.9.3 on macOS 27.0.1 did not reproduce the reporter's repeatable macOS 27.2 stall. This is not confirmation of the changed app's visual behavior. The previous wallpaper and Stage Manager setting were restored, the temporary import was removed, and the VM was suspended again.
- Updated the [web runtime description](../../features/web-wallpapers.md#runtime-shape) and [test coverage](../coverage.md#webwallpaper). No renderer/Rust changes or corresponding gates; no Release build, installation, commit or push.

## 2026-11-07 — Mission Control composition and desktop poster refresh

PR #175, including author updates 070caaa7 and 2ce3da8d, capture-cancellation fixes and native exported-web scheduling.

- `python3 scripts/build.py --renderer-only` — exit 0; renderer built and Swift bindings regenerated. The later author commits leave Renderer sources unchanged.
- `python3 scripts/test.py` — exit 0 on the final integrated tree: 687 Python tests passed; 4,648 native tests passed, 0 failed, 66 skipped (4,714 total).
- Native skips cover opt-in live Steam, media/device integration and Wallpaper Engine web-reference jobs. One runtime warning remains: a method called on the main thread may cause UI unresponsiveness.
- `python3 scripts/check_rust.py` — exit 0; 2,476 passing tests. Five desktop-window tests explicitly excluded; desktop/media/network opt-ins disabled.
- `cmake --build artifacts/renderer/bin --parallel 6` — exit 0; completed the cold build separately after the renderer check hit its 600-second build limit.
- `python3 scripts/check_renderer.py --skip-build` — exit 0; all 109 registered binaries succeeded, with seven local-asset-dependent cases skipped. All 12 generated scenes matched between pooled and isolated rendering; eight projects completed two reload cycles.
- Regression coverage checks final-settle publication over a black startup picture, intermediate-frame retention, appearance refresh precedence, cancellation of replaced timers, and cache reuse. Native exported web layers retain the existing 10/20 FPS and pause/resume assertions.
- Live Mission Control transitions, cancelled swipes and multiple displays were not exercised. No desktop automation or Release app build.

## 2026-11-07 — Update cache ownership — final follow-up

Final updater inspection added a cache-directory symlink guard and an explicit byte-count bound while rehashing a recovered package. The routine gate had already passed and was not repeated.

- python3 scripts/test.py --only AppUpdatePolicyTests --only AppUpdatePersistenceTests --only AppUpdateTests — passed: 83 passed, 0 failed, 0 skipped; covers the final code including preservation of files behind a linked cache directory.
- Earlier feature gate: python3 scripts/test.py — 4,642 native tests passed, 66 skipped, all Python modules passed. Targeted follow-up is additional evidence, not a replacement full-gate claim.
- Live desktop update, real release migration/signing/publication and Release delivery build remain unrun. No installed app or user wallpaper data changed.

## 2026-11-07 — Persistent, nonintrusive app updates

Existing updater retained: three modes, conservative migration, per-version postponement, verified complete-package recovery, passive update surfaces and artifact-derived publish metadata.

- python3 -m unittest scripts.tests.test_update_manifest scripts.tests.test_publish_release scripts.tests.test_dmg scripts.tests.test_package scripts.tests.test_localization_catalogs — passed, 76 tests; real synthetic signed DMG metadata round trip included.
- python3 scripts/test.py --only AppUpdatePolicyTests --only AppUpdatePersistenceTests --only AppUpdateTests --only AppReleaseHistoryTests --only UpdateWindowTests --only UpdatePresentationTests --only AboutSettingsTests --only StatusPanelModelTests --only StatusPanelControllerTests --only StatusPanelRenderTests --only FirstRunModelTests --only WelcomeRenderTests --only SettingsSectionsLocalizationTests — passed, 199 tests at the targeted checkpoint; final additional coordinator coverage included in the full gate.
- python3 scripts/test.py — passed once at completion: all 32 Python modules passed; native 4,642 passed, 0 failed, 66 skipped of 4,708. One runtime warning reported by the runner; skips are not passing evidence.
- Cache and installer tests use isolated temporary paths/defaults and fake restart/open actions; they do not replace the installed app.
- git diff --check and introduced documentation-link targets — passed. CLAUDE.md remains a relative symlink to AGENTS.md.
- Not run: authorized desktop/UI session, live old-to-new release update, production signing/notarization/publishing, or a Release delivery build. No app launch/restart, release or push performed.
- Rust/C++ renderer checks not applicable: no renderer changes. Task-owned transient test artifacts removed after recording the results.

## 2026-11-07 — Preserve saved sign-ins when keychain updates fail

- pixiv and Steam Community now share generic-password storage; refused updates preserve the saved item and the original keychain status.
- `python3 scripts/test.py --only KeychainGenericPasswordTests --only PixivStoreTests --only SteamWebSessionTests --only WorkshopStoreTests` — exit 0; 34 passed, 0 failed, 0 skipped.
- `python3 scripts/test.py` — exit 0; 682 Python tests across 32 modules passed; native: 4,641 passed, 0 failed, 66 skipped of 4,707.
- The first targeted build failed because Debug products carried Finder extended attributes; the documented `xattr -cr build/Build/Products/Debug` recovery cleared the signing failure before the passing runs.
- The full gate reported two main-thread runtime warnings, attributed to AppUpdateTests.testSignatureCheckRefusesAnUnsignedOrAlteredCopy and VideoFormatSupportTests.testTheOpenedFilesAreKeyedByTheFileAndForgetAChangedOne; both tests passed.
- Keychain regressions use injected in-memory calls. Real keychain authorization prompts and signed-release upgrades remain unverified; no desktop/UI, live Steam or opt-in media run was requested.
- No Rust or renderer changes; their additional gates were not run. No Release build or version release was requested.

## 2026-11-07 — Fullscreen Space presentation guard (#173)

- Four focused regressions failed before the fix: early preview resume, cancelled swipes, hidden-display classification and Space-monitor arrival.
- python3 scripts/test.py --only WallpaperPresentationPolicyTests --only WallpaperSpaceMonitorTests --only PlaybackPolicyCompositionTests --only ActiveDisplayTrackerTests: 101 passed, 0 failed, 0 skipped.
- python3 scripts/test.py: Python checks passed; 4638 native tests passed, 0 failed, 66 skipped (opt-in media, live Steam and web reference rendering).
- The full gate reported one main-thread runtime warning in AppUpdateTests.testSignatureCheckRefusesAnUnsignedOrAlteredCopy, outside the changed presentation code.
- Restored the installed Xcode Metal Toolchain after the first test build could not find it.
- Live Mission Control transitions and the reported foreground-window trails were not checked. No Release build or desktop run; no wallpaper-specific rendering changes.

## 2026-11-06 — Reduce redundant lighting, video and idle media work

- Changed light packing to reuse exact per-draw arrays, preserving reflection camera ordering and rebuilding after simulation; no quality or cadence settings changed.
- Shader updater regression suite: 32 passed; 20 passes plus 20 reuse-key reads pack each light family 40 times without a draw scope and once within it, with identical bytes and hashes.
- AppleScript fallback has no timer while Music and Spotify are absent; launch/exit observation preserves immediate recovery and the existing 1 Hz live cadence.
- Filtered WebM reuses one compatible output format description; regression checks cover timing, pixels and changed dimensions.
- Targeted native tests: AppleScriptMediaProviderTests, FallbackSystemMediaProviderTests and WebMFilteredVideoSinkTests; 23 passed, none skipped.
- python3 scripts/test.py passed: Python checks plus 4622 native tests passed, 66 skipped, no failures; one main-thread runtime warning was reported.
- python3 scripts/check_rust.py --output artifacts/power-efficiency/rust-unsandboxed passed; desktop/media/network opt-ins remained disabled. Initial sandbox run could not access cache and IOSurface services.
- python3 scripts/check_renderer.py passed: 12 generated pooled/isolated pixel comparisons equal, zero diagnostic errors, reload cycles passed; local asset-dependent checks explicitly skipped.
- Missing Xcode Metal Toolchain component installed before native verification; no desktop run, Wallpaper Engine comparison or hardware battery/power measurement. No Release build or commit.

## 2026-11-05 — Nine features adopted from rival Mac wallpaper apps

Menu bar Now Playing panel, inactivity pause, playlist wait for a clip's end, hev1 HEVC from a retagged copy, broader Installed search and Last used, library-drive follow, Workshop search translation, Hide Desktop Icons and the notch strip, and the stalled audio-tap rebuild. Each was reviewed independently, plus once across all nine, and fixed in two verified rounds.

- `python3 scripts/test.py` — exit 0; 4653 tests: 4587 passed, 66 skipped
- `python3 scripts/check_rust.py` — exit 0; desktop/media/network opt-ins off
- `python3 scripts/check_renderer.py` — exit 0; generated probes pixel-equal, corpus and local-energy cases skipped
- `python3 scripts/build.py --configuration Release` — exit 0
- Offscreen captures (light and dark) of the menu bar panel and of Settings › General, Playback & Power and Desktop & Lock Screen; hover, popover attachment and active control colours unverified
- Not run on the desktop: status-item click routing, real idle detection, Finder restart and the notch strip's look, a real drive eject and remount, the Translation framework with real language packs (macOS 15 hand-off untested), a real hev1 Workshop clip, a real stalled audio tap
- Not compared with Wallpaper Engine: no change to how a scene is drawn

## 2026-11-05 — Battery: scene pass merge and opt-in battery choices

Scene draws that only their object order or depth attachment kept apart share one render pass (WALLPAPER_MACHINE_SCENE_PASS_MERGE); When another app is in front gains Pause on battery, the menu bar an On Battery submenu, and the panel a one-time battery question. M5 Pro, macOS 27.

- `python3 scripts/test.py` — exit 0; 4396 passed, 0 failed, 61 skipped
- `python3 scripts/check_renderer.py` — exit 0; generated cases pixels_equal=True, reload cycles 0; local-corpus tests skipped (no environment)
- Sweep of 91 installed scenes (metal_scene_draw_smoke, WE_TEST_METAL_TIMING, 3456x2234@2): every scene draws; 11 change structurally, e.g. 3808922316 32 → 11 scene render passes, 958 → 213 MB loaded a frame
- `perf_bench.py identity` base vs merge — identical on every compared frame of 7 changed scenes; 3 not comparable (base differs from itself)
- `perf_bench.py cost` base vs merge, 60 fps, 3456x2234@2, 5 ABBA pairs — GPU 4.36 → 3.84 W on 3808922316 (saving, CI −0.56 to −0.50 W); 3226487183 −0.71 W and 3662790108 −0.82 W in every pair taken but short of a verdict (thermal rejections); 2 scenes within spread
- `perf_bench.py cost` Reduced quality (30 fps, 75 %) vs full, 3 pairs — GPU 1.60 → 0.41 W (3802900973), 2.27 → 0.56 W (3413921910)
- `python3 scripts/build.py --configuration Release` — OK
- Not verified: a real unplug or plug-in, WindowServer and whole-desktop power (need an authorized desktop run), native review of the new translations

## 2026-11-05 — Faster, rehearsable release pipeline

Build reuses the cached renderer build through scripts/source_times.py, compiles beside the app-icon job instead of after it, checks the signing secrets before building, and gains a rehearsal mode (rehearsal.yml); CodeQL stops saving C++ object caches, and Warm caches becomes the daily writer of the caches a release restores. CI behaviour is not yet observed: nothing was pushed.

- Local clone, cargo after a fresh checkout over a cached Renderer/target: 4 crates in 17.7 s today; with source_times.py restore: 0 crates (0.09 s) for the same commit, wallpaper-bridge only (9.2 s) for a Swift-only commit, core + bridge (11.0 s) for a Core change, one C++ compile for an engine change; an added and a removed msdfgen source both reran CMake and the archive followed
- Local clone, `scripts/build.py --configuration Release --no-app-icon` then `--install-app-icon`: AppIcon.icns, CFBundleIconName and the compiled Assets.car present; `codesign --verify --deep --strict` passed
- Icon wait loop against a fake gh: artifact after polls exit 0; failed API calls retried; failed icon job exit 1
- `actionlint` with shellcheck on every workflow: no findings besides the existing `queue` key it does not know
- `python3 scripts/test.py` — exit 0; Python script tests all OK (test_source_times 9, test_build new cases); native 4424: 4363 passed, 0 failed, 61 skipped
- Not run: any GitHub Actions run (Rehearsal, Warm caches, a release); Developer ID signing and notarization unchanged and unexercised locally

## 2026-11-04 — Library previews play on every tile on screen; hover-only is a setting

- Change: Installed tiles on screen all play their animated preview through LivePreviewScheduler (six loading at once, grid order); Settings › General › Play Library previews only on hover (off by default, WallpaperMachine.libraryPreviewsOnHover) restores the one hovered/focused tile.
- python3 scripts/test.py --only InstalledBrowserModelTests --only PanelPreferencesTests --only PanelSettingsResetTests --only SettingsEditingModelTests --only LivePreviewSchedulerTests --only LibraryTileRulesTests: 99 passed.
- python3 scripts/test.py: 4357 passed, 0 failed, 61 skipped of 4418; 2 runtime warnings in the result bundle, not examined.
- Catalog: two new strings translated into pt-BR, ko, ja, zh-Hans, zh-Hant; localization catalog and panel localization checks pass.
- Not checked: the grid playing in a real window (scrolling, many GIF tiles at once, Reduce Motion) and its CPU/energy cost; no desktop run, no Release build.

## 2026-11-04 — Developer ID signing and Apple notarization for releases

- Change: package.py signs every library, framework, the extension and the app with the hardened runtime and a secure timestamp for a Developer ID, has Apple notarize and staple the app and then the signed disk image, and writes the checksum last; build.yml imports the Developer ID certificate and an App Store Connect API key (five secrets, all present in the repository). The bundle contract enforces host entitlements, the runtime flag, no get-task-allow and one signing team.
- Certificate: G2 Developer ID Application (SHA-1 2076E28E…2E62, expires 2027-12-02); its signature meets the requirement 1.8.0 shipped (codesign -R).
- `python3 scripts/test.py` after rebasing onto main c32fb8d4: 4355 passed, 0 failed, 61 skipped. Upstream's scripts/tests/test_power_ab.py crashes on import on this Mac (dataclass in a module loaded without sys.modules; Python 3.13 and 3.14), though main's Checks pass it on Linux; the gate ran with a local, uncommitted `sys.modules` line in that test, restored afterwards. The Debug app carried a com.apple.FinderInfo attribute that made CodeSign refuse it; cleared.
- Real artifact (Release build of 1.8.2 contents, signed with the G2 certificate): Apple's notary service held the app submission 575b4e21 for about 18 hours (2026-11-03 01:50Z to 19:57Z, new-team hold, as were the team's earlier submissions); then Accepted. `stapler staple` and `stapler validate` passed; `spctl --assess --type execute` reports source=Notarized Developer ID.
- A fresh disk image of that app, signed with the Developer ID, was Accepted in about 2 minutes (a69de3ee, 20:02Z), so the 50-minute CI wait is enough again.
- Local `notarytool submit --wait` lost its connection through this Mac's system proxy (TLS -1200); submitting without waiting and polling `notarytool info` worked. CI has no proxy.
- Gap: this Mac has SIP and Gatekeeper assessments disabled, so library validation and first-launch behavior were not enforced here; the hardened runtime (Apple Events, system audio tap, lock screen including web wallpapers, SteamCMD) needs the 1.9.0 manual smoke on a Mac with both on. The full CI pipeline (package.py --notarize with the DMG step) runs for the first time on the 1.9.0 release.

## 2026-11-03 — Web wallpapers laid out in device pixels and fed silence, compared with Wallpaper Engine

Read off Wallpaper Engine 2.8.42's webwallpaper64.exe (CEF 146) in IDA: force-device-scale-factor=1, disable-web-security, autoplay without a gesture, CefSettings background black, the listener contract. Applied the two differences the local Workshop pages showed: the layout in device pixels and the audio listener called through silence.

- `python3 scripts/we_reference.py capture` of 9 local Workshop web wallpapers in the Parallels VM (Wallpaper Engine 2.8.0.42), then `render --label before/after` and `compare`: mean difference to Wallpaper Engine's frame 3.6 → 0.9 (RE4 case), 2.7 → 0.0 (Audio Visualizer), 3.6 → 1.0 (a visualiser that stayed dark), 19.1 → 15.6 (ZZZ capsules); the others unchanged within noise
- Performance A/B, same jobs back to back, 30 s per page on this Mac: WebContent CPU unchanged on all 9; frame rate unchanged on 7, Rhine Lab 60 → 52 (its renderer supersamples 1.8x at the device-pixel layout, as under Wallpaper Engine), ZZZ capsules 38 → 33 (GPU-bound before); pages that size a canvas from innerWidth draw 4x the pixels (Audio Visualizer GPU 9 → 19 %). WebKit's zoom itself costs no more memory than a native scale of 1 (probe: 69 vs 70 MB)
- `python3 scripts/test.py` after the rebase — 4335 passed, 1 failed (AppUpdateTests installer test over its 2-minute allowance under load; passes alone), 61 skipped; `--only WebWallpaperDeviceLayoutTests --only ScreenSaverWebSurfaceTests` — 22 passed
- Not checked: the desktop app on a real display (offscreen pages only), how a page reads matchMedia resolution queries, the GPU figures are the whole Mac's

## 2026-11-03 — Moving-layer effect reuse on by default

Developer decision: accept rare one-level texel differences from joined render passes for the GPU time layer-local reuse saves (WALLPAPER_MACHINE_LAYER_LOCAL_SIGNATURES, now on unless =0). Supersedes the opt-in line of the power and performance entry.

- `python3 scripts/check_renderer.py` — exit 0, including MetalSceneDraw.AMovingLayerBetweenTwoCardsIsReusedAndJoinsTheCardsRenderPasses
- `python3 scripts/perf_bench.py identity` =0 against the default, 240 draws hashed every 30, both surfaces — identical on 3796026374 and 3624257712; 3808922316 at 3456x2234@2 differs in frame 149 (2 pixels, max channel 1), identical at 3840x2160@2
- Saving (earlier Metal System Trace, 3808922316 at 3840x2160@2): 17 passes a frame left out, about 0.4 ms or 8 % of its GPU time

## 2026-11-03 — Experimental switch: draw only the visible part of cropped scenes

SDR display framing behind `scene_display_framing` under `[experimental]`, off by default; `WALLPAPER_MACHINE_SDR_FRAMING=1`/`=0` overrides it. Measured on an M5 Pro.

- `python3 -m unittest scripts/tests/test_localization_catalogs.py scripts/tests/test_panel_localization.py scripts/tests/test_doc_links.py scripts/tests/test_perf_bench.py` — OK, 56 tests
- `python3 scripts/check_rust.py` — exit 0 (core 419, bridge 935, shader 954 passed); AppKit window cases excluded without an authorized desktop run
- `python3 scripts/check_renderer.py` — exit 0; `RasterWindow.*` (10) and `SdrDisplayFraming.*` (6) pass; local-project and corpus cases skipped (no corpus named)
- `python3 scripts/test.py --only` PanelPerformanceSettingsTests, PanelSettingsResetTests, PanelEnergyRestartTests, DesktopSettledPosterStoreTests and the settings search, localization and render classes — 59 passed
- `perf_bench.py identity` setting off against the branch point (3784370784, 3796026374, 3626305963, 3808922316 at 3840x2160@2 and 3456x2234@2): identical on comparable frames; the remaining verdicts repeat in base-against-base runs (3784370784 is nondeterministic in the base itself)
- With `WALLPAPER_MACHINE_SDR_FRAMING=1` a cropped scene's frames change as stated (3808922316 at 3456x2234@2) and an uncropped one stays identical (3808922316 at 3840x2160@2)
- Cost figures (Miyabi 3784370784 at 3840x2160@2: render targets 508.5 → 437 MB, GPU about −6 to −16%; 16:9 scenes on 3456x2234@2: −3 to −5.5% memory, GPU within noise) come from the framing experiment, not rerun on this branch
- Not run: full `python3 scripts/test.py`, a desktop run, a power measurement and a Release build

## 2026-11-03 — Power and performance: byte-identical renderer savings, host idle work, frame pacing

Branch t3/optimize-power-usage (PR #156) against the v1.8.2 renderer on an M5 Pro (macOS 27), on the local library's heaviest scenes at the developer's settings (render scale 0.75, 60 fps, display resolution, fill), surfaces 3840x2160@2 and 3456x2234@2.

- `python3 scripts/check_rust.py`, `python3 scripts/check_renderer.py`, `python3 scripts/test.py` on the final tree — exit 0; test.py 4320 passed, 0 failed, 60 skipped
- `python3 scripts/perf_bench.py identity` base vs final, 240 draws hashed every 30, both surfaces — 128/128 comparable frames identical on 3808922316, 3796026374, 3626305963, 3624257712, 3669681034, 3537671609, 3441873795, 3013702957; 3784370784 differs between two baseline runs (wall-clock text), covered by masked comparison and equal pass plans
- Layer-local reuse signatures (`WALLPAPER_MACHINE_LAYER_LOCAL_SIGNATURES`) changed 2 pixels by one level on 3808922316 at 3456x2234 (merged render passes blend differently on Apple GPUs) — made opt-in; with it off the scene is identical
- Deterministic counters, all optimisation switches off vs on, 3840x2160@2: memory read by loading render passes 3,187 → 1,543 MB per frame over seven scenes; 3808922316 blits 14 → 0, copies 17.1 → 0 MB per frame
- Metal System Trace with `WALLPAPER_MACHINE_GPU_LABELS=1`: 3784370784 audio visualizer passes 0.81 → 0.01 ms per frame while silent
- Back-to-back GPU ms per draw, off vs on, 3 rounds on battery with other GPU load — indicative only: -7 to -10 % on four scenes, within noise on three
- Not run: `scripts/power_ab.py` desktop windows and the paired `perf_bench.py cost` energy run (machine on battery at 21–26 % and in use); frame pacing's on-screen gap distribution unverified on a real display
- SDR display framing measured and not merged (interior not byte-identical); Wallpaper Engine reference frames captured for 3784370784, 3796026374, 3626305963, 3808922316

## 2026-11-03 — Web lock screen: silence for audio listeners, wallpaper switches no longer count as renderer exits (issue 155)

- Cause 1: the lock-screen page never called the audio listener; 音域回响 starts its idle animation only after the first call, so it held its first frame. ScreenSaverWebSurface now feeds a subscribed, playing page 128 zeros once a second (the desktop's quiet-stretch spacing).
- Cause 2: applying a wallpaper reloads WallpaperAgent, which ends the old renderer while its exit watch was still armed; four switches in ten minutes restored the system wallpaper (seen with ZZZ at 15:58:05). LockScreenWallpaperService now cancels renderer watches before publishing a new revision.
- New tests testASubscribedPageHearsSilenceWhilePlayingAndAgainAfterAResume and testSwitchingWallpapersIsNotCountedAsTheRendererFailing fail with the fixes removed and pass with them.
- python3 scripts/test.py: 4298 passed, 0 failed, 53 skipped. Release build OK.
- Gap: real lock behaviour not checked by the agent; ZZZ's earlier memory-limit stall is unchanged.

## 2026-11-03 — Web lock screen: page paused state follows the surface (issue 155)

- Cause: the extension created a web page paused before its first frame while WallpaperSurface tracked it as playing; applyPolicy never resumed it, so the settling desktop and any lock within ~15 s kept the readiness frame (black/grey for 音域回响 and 阿洛娜指纹识别2.0). Evidence: unified log showed WebPageProxy::suspend 60 ms after load and no resume at the following lock.
- Fix: Extension/WallpaperSurface.swift creates and updates the page with rendererPaused, like scenes and clips; docs/features/lock-screen.md updated.
- python3 scripts/test.py: 4296 passed, 0 failed, 53 skipped.
- python3 scripts/build.py --swift-only --configuration Release: OK.
- Gap: WallpaperSurface is extension-only and has no unit-test harness, so no regression test; real lock behaviour not checked by the agent.

## 2026-11-03 — Web lock screen: a busy page no longer fails its pause or resume

- Symptom: a 3D web wallpaper sometimes held a still frame on lock; the app log showed 'The web wallpaper did not produce a frame in time.' at unlock and the lock screen was handed back to macOS.
- Unified log: on resume the extension's WebKit GPU process got a process-limit-critical memory event (32) and WebKit's display link reported the main thread stuck; the page's property delivery ran only after the 5 s transition deadline had closed the page.
- Fix: ScreenSaverWebSurface bounds waits on the page (properties, media, held frame) at 5 s and goes on without them; only WebKit's suspend/resume not answering within 15 s fails the surface.
- New test ScreenSaverWebSurfaceTests/testABusyPageIsStillResumedAndPausedWithoutFailingTheSurface fails on the old reconcile with timedOut, passes with the fix.
- python3 scripts/test.py: 4291 passed, 0 failed, 53 skipped. Release build OK.
- Not verified: repeated real locks with the user's wallpaper; why the GPU process reaches its limit on resume (two copies of a heavy page: desktop and lock screen) is not addressed.

## 2026-11-03 — Web lock screen and screen saver: export the live page, not only its snapshot

- Symptom after the issue 155 change: a web wallpaper on the lock screen showed a still frame; extension.log showed it was not paused while locked.
- Cause: ScreenSaverWebSurface.attach added the content view's backing layer to the exported root; AppKit kept it in the window's tree, so the CAContext held only the readiness snapshot beneath it (screen saver too).
- Headless probe (never-ordered window, CARenderer over the root): old attach left the root empty; exporting the frame view layer rendered the page's canvas alternating red/blue.
- New test ScreenSaverWebSurfaceTests/testTheLivePageStaysInTheLayerTreeItWasAttachedTo fails on the old attach, passes with the fix.
- python3 scripts/test.py: 4290 passed, 0 failed, 53 skipped. Release build: python3 scripts/build.py --swift-only --configuration Release, OK.
- Not verified: a real lock with the web wallpaper (the user's next run), and the screen saver on a real idle.

## 2026-11-03 — Web and still wallpapers animate the lock screen (issue 155)

- Change: web projects (and still images, which are web projects) are published for Animate lock screen, take the Desktop selection and follow the lock-screen settle/pause policy in the extension; the 'not applicable' status and compatibility verdict are gone.
- python3 scripts/test.py --only LockScreenWallpaperServiceTests --only WallpaperCompatibilityTests --only ScreenSaverWebSurfaceTests --only WallpaperPresentationAuthorityTests: 108 passed.
- python3 scripts/test.py: 4289 passed, 0 failed, 53 skipped; Python stage (localization catalogs, panel localization, doc links) OK.
- New test: a web wallpaper takes the lock screen and keeps it when the screen saver turns off.
- Catalogs: five web-surface errors reworded from 'web screen saver' to 'web wallpaper' in both catalogs; compatibility and Settings copy updated; three unused keys removed; all six languages.
- Not verified: a real lock/unlock with a web wallpaper on the desktop, extension WebKit memory while held, no Release build.

## 2026-11-02 — When another app is in front (discussion #91)

- Feature: Settings → Playback & Power gains When another app is in front (Keep running / Mute / Pause), default Keep running.
- AppRuleMonitor adds the chosen action while the frontmost app is not Finder or this app; no app in front counts as the desktop.
- python3 scripts/test.py --only AppRuleMonitorTests, PlaybackPreferencesTests, PanelSettingsResetTests, ConditionOverrideTests and six more Panel/Backup classes: 120 passed.
- python3 scripts/test.py: Python stage OK; native 4287 passed, 0 failed, 53 skipped.
- Localization catalog and panel localization checks pass; five languages added for title, note and prose.
- Not checked: the setting on a real desktop (no desktop run requested); the app was not rebuilt.

## 2026-11-01 — Discord invitation, About entry and Help menu item

A fifth one-time prompt, Join us on Discord?, invites once to MMFoundation's Discord through https://mmfoundation.dev/discord (ExternalLink.discord, allowlisted; never the invite itself), last in priority, after 21 days and 7 days of panel use on the star prompt's clock. Settings › About gains Join Discord beside MMFoundation and the Help menu gains Join Discord; either spends the invitation. Strings in all six languages.

- `python3 scripts/test.py --only SupportPromptStoreTests --only PanelSupportPromptTests --only SupportPromptPresenterTests --only WelcomeRenderTests --only SettingsSectionsLocalizationTests --only ExternalLinkTests` — 62 passed (after `xattr -cr build/Build/Products/Debug`, docs/build.md)
- `python3 scripts/test.py` — 4268 passed, 0 failed, 52 skipped
- `python3 scripts/build.py --swift-only --configuration Release` — OK
- Sheet (en, zh-Hans) and Settings › About (en, zh-Hans) rendered offscreen from a never-shown window to check the layout; the app was not launched and the Help menu item was not opened by hand

## 2026-11-01 — MMFoundation link in Settings › About

Settings › About gains an MMFoundation button beside the GPL link, opening https://mmfoundation.dev/ through ExternalLink's allowlist (mmfoundation.dev added); READMEs in all four languages name MMFoundation with a link. Run while another task's uncommitted Spaces/desktop-picture edits were in the same checkout.

- `python3 scripts/test.py --only ExternalLinkTests` — 5 passed (after `xattr -cr build/Build/Products/Debug`, docs/build.md)
- `python3 scripts/test.py --only SettingsSectionsLocalizationTests` — 2 passed; MMFoundation added to its same-everywhere names
- `python3 scripts/test.py` — first run 2 failed: the localization test above (fixed) and EnergyUsageMonitorTests.testKernelCountersForThisProcessAdvanceWithGPUWork (3.4 mW, hardware counter); rerun 4258 passed, 0 failed, 52 skipped
- Not checked: the button on screen (no desktop run requested); no Release build

