# Verification log

Append-only history of what was actually verified, when, and with what result.
The newest entry goes on top; never rewrite an older entry to match today's
tree. Every entry is evidence about the tree it was taken on, not about the
current one — re-run the relevant checks after integration and add a new entry
instead of reusing an old result. Durable guidance belongs in the sibling docs:
test layers and policy in [README.md](README.md), renderer commands and
regression areas in [renderer.md](renderer.md), manual checks in
[manual-smoke.md](manual-smoke.md). Result bundles and probe output are local
and disposable, so entries state counts and commands rather than artifact
paths.

Entry format, so the log stays skimmable: a one-line summary heading, one short
paragraph of context only when the result needs it, then a bullet per command
with its exit status, counts and any skip. Keep an entry around ten lines. A
fact that will still matter next week is not an entry — promote it to the doc
that owns it (renderer behaviour and known-failing tests to
[renderer.md](renderer.md), build and signing traps to
[../build.md](../build.md)) and cite it from there.

Retention: this file keeps the ten newest entries. Add an entry with
`python3 scripts/log_verification.py --title "…" --line "…"`, which prepends it
and moves whatever falls past ten verbatim into a monthly file under
[archive/](archive/); promote anything durable before it goes. Editing an
entry's recorded result is not allowed.

## 2026-11-14 — Compact pixiv pages after filtering

- Matching works are deduplicated and paginated after filtering; rankings report exact matching totals and searches refill on demand with lookahead.
- Targeted pixiv store and panel regression run: 84 passed, 0 failed, 0 skipped.
- `python3 scripts/test.py`: exit 0; all Python script modules passed; native tests: 4,933 passed, 0 failed, 70 skipped.
- Seven new pagination cases cover cross-page refill, cached refiltering, search lookahead, retry, duplicates, empty ratings, in-flight filter changes and a fully filtered tail.
- Opt-in media, live-network and snapshot checks remained skipped. Two runtime main-thread warnings were reported by the full suite.
- Live pixiv and desktop presentation were not checked; no desktop control, Release build, installation or restart was performed.

## 2026-11-14 — Shared wallpaper-store coordination (issue 199)

- Implemented a shared FIFO transaction queue for native selection and desktop posters, with bounded verified WallpaperAgent turnover and selection readback.
- Recovery retries preserve unrelated fields and reject foreign selections; cancelled writes and restarts remain admission barriers; both journals survive unconfirmed restoration.
- Poster acknowledgements drain as a batch; native takeover and quit cancel and drain queued poster work before changing ownership.
- python3 scripts/build.py --renderer-only — passed; prepared the missing test-link dependency and regenerated bindings; no renderer source changes.
- Targeted native run across coordinator, lock-screen, desktop, panel-settings and native-video host tests — 436 passed, 0 failed, 0 skipped.
- python3 scripts/test.py — passed all Python modules; native gate: 5017 passed, 0 failed, 70 skipped of 5087.
- Three runtime main-thread warnings came from VideoFormatSupportTests, AppUpdateTests and WebMFilteredVideoSinkTests; compiler warnings remain in existing code.
- Documentation links and git diff --check passed. Live desktop/WallpaperAgent behavior was not exercised; no desktop authorization, Release build, install, commit or push.
- Removed this task’s disposable test result bundles and renderer-build logs after recording the verdicts; retained compiled build outputs.

## 2026-11-13 — Sign-in window hosts and sign-outs the keychain resists

Security report on the Steam/pixiv sign-in (allowlist for the Steam sign-in window; Steam Community and pixiv sign-out emptying a keychain item another build saved, failing only when the session stays). The report's third finding, memory corruption in `SteamCMDRuntimeService.fingerprint` `readlinkat`, was not reproduced: SIL shows `&link` passing the element buffer (`_convertMutableArrayToPointerArgument<UInt8, UnsafeMutablePointer<Int8>>`), and the same pattern ran clean under AddressSanitizer with a 1022-byte target; the code is unchanged.

- `python3 scripts/test.py --only` WebSignInPolicyTests, KeychainGenericPasswordTests, SteamWebSessionTests, WorkshopSourceTests, PixivStoreTests, PanelWorkshopSubscriptionsTests, NativeWorkshopDownloadTests, PanelPixivActionsTests, PanelDownloadActionsTests — 143 passed
- `python3 scripts/test.py` — first run 4980 passed, 1 failed (`ScreenSaverWebSurfaceTests` frame rate 8.7 < 14 under load; 16/16 alone); rerun 4981 passed, 0 failed, 70 skipped
- Not checked: a live Steam or pixiv sign-in and sign-out against the allowlist, and macOS's real answer to emptying another build's item (modelled by `MemoryKeychain`)

## 2026-11-13 — Keep scenes through empty active-display reports

- Issue #196: build each refresh plan from one CoreGraphics report and its captured main-display flag. An empty active list skips reconciliation, retains scenes/assignments/handles and logs once; actual read errors still propagate.
- Two new empty-report regressions failed before the fix, including loss of the secondary scene. Five added regressions cover empty reports, return/disconnect behavior, preserved paused state and renderer identity, coherent primary selection, bounded diagnostics and error propagation.
- Targeted wallpaper-core display tests: 138 passed. `python3 scripts/check_rust.py --output artifacts/issue-196/rust`: all checks passed; Core 436 and Bridge 962 library tests passed, as did all six integration targets and Shader checks. Five real-desktop cases were explicitly excluded and the opt-in window gate remained disabled.
- `python3 scripts/check_renderer.py`: exit 0; 110 executable/probe statuses succeeded, 12 synthetic pooled/isolated comparisons passed and reload cycles passed. GPU and realtime checks ran; the timer diagnostic was collected.
- Renderer coverage gaps: seven optional local video, particle, wallpaper, energy and corpus cases skipped; four pre-existing corpus/benchmark/worker cases remained disabled.
- `python3 scripts/test.py --only DisplayRefreshCoalescerTests --only SystemWakeRevalidatorTests --only WallpaperPresentationPolicyTests`: 96 passed, 0 failed, 0 skipped.
- `python3 scripts/test.py`: all 35 Python modules passed; 4,971 native tests passed, 0 failed, 70 skipped of 5,041. Skips require opt-in media, live Steam/network, reference jobs or snapshots.
- The full native run reported main-thread warnings in unchanged VideoFormatSupportTests.testTheOpenedFilesAreKeyedByTheFileAndForgetAChangedOne and AppUpdateTests.testSignatureCheckRefusesAnUnsignedOrAlteredCopy; both passed. Documentation links and git diff --check passed.
- No real lock/sleep/multi-display wake cycle or wallpaper reference comparison was performed. No Release app was built, installed or restarted.

## 2026-11-13 — Keep settings searches responsive

- Issue #201: retain the settings result view while typing, build result sections lazily, and reset scrolling explicitly; entering/leaving search resets only the list layout.
- Baseline production source d82c4249: refining wallp through wallpaper and back caused 32 additional system-reading refreshes across eight edits. The regression now passes with no additional refreshes.
- Same offscreen Debug fixture, 760 x 560 points, eight query edits: mean update time 315.52 ms before, 45.75 ms after; maximum 341.32 ms before, 47.01 ms after. Each sample includes a fixed 30 ms settle wait; this is not a live keyboard-latency or Release benchmark. Search calculation remained about 3.1 ms.
- `python3 scripts/test.py --only SettingsSearchRenderingTests --only SettingsSearchTests --only SettingsSearchOfferTests --only DisplaysSettingsSearchTests --only SettingsSectionsRenderTests/testSearchResultsOfTheSixPagesLayOutInTheNarrowColumn --only SettingsWindowRenderTests/testEverySectionFitsTheSmallestWindowAtEveryHeightWhileMovingBetweenSections`: 30 passed, 0 failed, 0 skipped.
- `python3 scripts/test.py`: all 35 Python modules passed; 4,971 native tests passed, 0 failed, 70 skipped of 5,041.
- Skipped checks require opt-in media, live Steam/network, web reference jobs or panel snapshot output. Two main-thread runtime warnings came from unchanged LockScreenWebMPlayerTests.testAFailureTheClipHadBeforeAHandlerWasSetIsHeldAndDeliveredOnce and AppUpdateTests.testSignatureCheckRefusesAnUnsignedOrAlteredCopy; both passed.
- `git diff --check`, `python3 scripts/tests/test_doc_links.py`, and `python3 scripts/tests/test_panel_lazy_lists.py`: passed. XcodeGen registered the new render-test file.
- No real desktop interaction or screenshots; windows stayed unordered. No Release app was built, installed or restarted.

## 2026-11-13 — Preserve desktop originals after native restoration failures

- Issue #197: keep poster synchronization suspended until native restoration succeeds; reject native desktop selections when recording poster originals and preserve the existing recovery journal.
- Regression run on the previous implementation: 4 expected failures and 1 passing control across the five selected desktop/lock-screen tests.
- `python3 scripts/test.py --only DesktopWallpaperTests --only LockScreenWallpaperServiceTests --only LockScreenWallpaperTests`: 252 passed, 0 failed, 0 skipped.
- `python3 scripts/test.py`: all 35 Python modules passed; 4,967 native tests passed, 0 failed, 70 skipped of 5,037.
- Skipped checks require opt-in media, live Steam/network, web reference jobs or panel snapshot output.
- The full native run reported main-thread warnings in unchanged AppUpdateTests.testSignatureCheckRefusesAnUnsignedOrAlteredCopy and WebMOpeningTests.testAVp9FileOpensWithItsFormatSizeAndLength; both passed. The targeted run reported no runtime warnings.
- `git diff --check` and `python3 scripts/tests/test_doc_links.py`: passed.
- No live desktop/lock-screen/quit cycle was performed; no Release app was built, installed or restarted. Existing incorrectly recorded still-image originals are not migrated from the lock-screen journal; shared WallpaperAgent write/reload coordination remains #199.

## 2026-11-13 — Covered-desktop sound: PR 194 review and reconnect fix

- Four reconnect regressions failed before the fix, covering retained pauses and refused resumes for Mute and Reduce volume.
- Targeted playback, preference, backup and panel checks: 169 passed, 0 failed, 0 skipped; no runtime warnings.
- python3 scripts/test.py on main ef6c85c5 plus the final PR source: all 35 Python modules passed; 4,963 native passed, 0 failed, 70 skipped of 5,033 (Xcode 27.2).
- The integration run used temporary test-home and path-backed preference-suite overrides to isolate the installed app.
- Skipped: opt-in media, live Steam, reference rendering and panel snapshots. Two main-thread warnings came from unchanged VideoFormatSupportTests and AppUpdateTests cases.
- Real coverage probes, audible output and narrow-window presentation were not exercised. No Release build, installation or desktop run.

## 2026-11-13 — Project triage and grouped GitHub Actions updates

- Project triage maintains area and lifecycle labels from GitHub closing links, current-head reviews, CI, mergeability and DCO trailers; Dependabot groups weekly GitHub Actions updates.
- `python3 scripts/tests/test_project_triage.py` — 24 behavior tests passed; no network or writes in tests.
- `actionlint .github/workflows/project-triage.yml`, Dependabot YAML parse and Markdown link checks — passed.
- `python3 scripts/project_triage.py --repo MMFoundation/WallpaperMachine --apply` — reconciled 11 live items; DCO statuses and PR area labels read back. PR #194 has five unsigned commits; PR #195 has eight signed-off commits.
- `python3 scripts/test.py` — exit 0 after documented Debug-product xattr cleanup; 35 Python modules passed; native 4,926 passed, 0 failed, 70 skipped, two runtime warnings.
- The native gate used an isolated app home and preferences. Opt-in tests remained skipped; no Release build or interactive desktop validation was performed.
- The workflows are not deployed yet: continuous triage and Dependabot require the configuration on the default branch. No commit, push, workflow installation or required-check rule was performed.

## 2026-11-13 — Audio capture startup timeout recovery

Core Audio start receive timeouts now stop and release the uncertain session before one fresh attempt; cleanup failures block replacement. Native status stays typed, and permission advice is limited to authorization errors.

- Injected AudioDeviceStart status 268451843: the new recovery regression failed before the fix (one attempt instead of two). After the fix, targeted cargo tests passed: 60 core audio and 32 audio-worker tests.
- `python3 scripts/check_rust.py --output artifacts/audio-startup/rust` — exit 0 across core, bridge, integration and shader checks; five desktop-window tests excluded, desktop/media/network opt-ins disabled, primary-display probe skipped without an active display.
- `python3 scripts/build.py --renderer-only` — exit 0; renderer library rebuilt and Swift bindings regenerated. No Release app build.
- `python3 scripts/test.py` — exit 65: Python checks passed; native results were 4,925 passed, 1 failed, 70 skipped. InspectorRenderTests/testTheFooterNeverCoversTheRowWhoseEditBringsItIn failed because the footer covered Show the clock; the same targeted test also failed alone. Its fixture uses a test bridge, not native audio capture.
- `python3 scripts/check_renderer.py` — initial build interrupted by a killed backdrop_geometry_test discovery process; rebuilding that target succeeded. The subsequent full run and a final --skip-build run both exited 1 because backdrop_scene_test was killed (signal 9); all other registered binaries returned 0.
- Renderer runs exercised GPU and realtime checks, twelve generated pooled/isolated image comparisons and eight reload projects twice, all successful. Seven local asset/corpus cases were skipped; authored wallpaper compatibility remains unverified.
- Live system audio capture, permission prompts, device changes and desktop behavior were not exercised. No app was installed, launched or restarted. Full native and renderer gates remain blocked by the failures above.

## 2026-11-12 — Gate run on a Mac for the covered-desktop sound choices (#192)

Run on an M4 Mac mini with macOS 27.2 and Xcode 27.2 (27B52) through DEVELOPER_DIR; build.md asks for Xcode 26 and the Test workflow uses macos-26 runners, which this run did not use. Commit d1d5d4e2, with no changes needed.

- `python3 scripts/build.py` (full, Debug) — exit 0
- `python3 scripts/test.py --only` PlaybackPolicyCompositionTests, WallpaperPresentationPolicyTests, PlaybackPreferencesTests, WallpaperBackupTests, OtherAudioVolumeSettingsTests, SettingsSectionsLocalizationTests, PanelSettingsValuesTests, SettingsSectionsRenderTests, SettingsWindowRenderTests — exit 0; 175 passed, 0 failed, 0 skipped
- `python3 scripts/test.py` — exit 0; 34 script test modules OK; 4936 passed, 0 failed, 70 skipped of 5006; 2 runtime warnings in the result bundle not examined
- Not checked: a Release build, the four-segment Quick Settings module in each language, real coverage-probe occlusion and audible output; the five translations are machine-written
- Found in passing, not caused by this change: `AppUpdateTests` builds `AppUpdateStore` without `defaults:`, and the gate wrote `WallpaperMachine.updates.lastAttempt` into the installed app's preferences
