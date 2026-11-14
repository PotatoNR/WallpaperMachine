import XCTest

@testable import WallpaperMachine

/// An engine that applies the settings the guide commits, records them in order and can refuse
/// the login item, so a commit's order and its stop at the first failure can be read off it.
@MainActor
final class FirstRunBridge: LayoutSnapshotBridge {
  /// What a launch-at-login change throws instead of answering.
  var launchAtLoginFailure: String?
  var launchAtLoginCalls: [Bool] = []

  /// Every committed setting in the order the engine received it.
  var committed: [String] = []

  override func setFrameRateCap(cap: UInt32?) async throws -> BridgeSnapshotBundle {
    try await apply({ $0.frameRateCapCalls.append(cap) }, "frameRateCap:\(cap.map(String.init) ?? "none")") {
      $0.frameRateCap = cap
    }
  }

  override func setRenderScale(scale: Float) async throws -> BridgeSnapshotBundle {
    try await apply({ $0.renderScaleCalls.append(scale) }, "renderScale:\(scale)") {
      $0.renderScale = scale
      $0.preferredRenderScale = scale
    }
  }

  override func setBatteryMode(mode: BridgeBatteryMode) async throws -> BridgeSnapshotBundle {
    try await apply({ $0.batteryModeCalls.append(mode) }, "batteryMode:\(mode)") {
      $0.batteryMode = mode
    }
  }

  override func setLaunchAtLogin(enabled: Bool) async throws -> BridgeDisplayMutationBundle {
    launchAtLoginCalls.append(enabled)
    committed.append("launchAtLogin:\(enabled)")
    throw WallpaperActionError(message: launchAtLoginFailure ?? "No login item in a test")
  }

  @MainActor private func apply(
    _ note: (FirstRunBridge) -> Void, _ name: String, _ change: (inout BridgeSettingsSnapshot) -> Void
  ) throws -> BridgeSnapshotBundle {
    note(self)
    committed.append(name)
    guard var bundle = bundleProvider?() else { throw CancellationError() }
    change(&bundle.settings)
    return bundle
  }
}

/// The first-run guide's state machine against the real stores: what applies at once, what is a
/// draft, what Skip puts back, what Skip setup and Escape do, and how the guide ends.
/// Replaces the model half of `testFirstRunGuideCoversTheWindowWalksSixPagesAndReturnsFromSettings`
/// and the four `testWelcome*` suites.
@MainActor
final class FirstRunModelTests: PanelTestCase {
  /// A started panel whose guide is unseen, over an engine that records and applies what the guide
  /// commits. `body` gets the open guide.
  private func withGuide(
    welcomeSeen: Bool = false,
    _ body: (PanelFixture, FirstRunModel, FirstRunBridge) async throws -> Void
  ) async throws {
    let bridge = FirstRunBridge(noPointer: .init())
    let store = BridgeStore(bridge: bridge)
    store.settingsSnapshot = BridgeSnapshotFixtures.settings(
      displays: [
        BridgeDisplaySettingsRow(
          displayId: "primary", title: "Studio Display", enabled: true, mode: .standalone,
          mirrorTargets: [], selectedMirrorTarget: nil, scalingMode: .fill, scalingFactor: 1,
          targetFps: 30, maxFps: 60, muted: false, volume: 1)
      ])
    bridge.bundleProvider = { [store] in
      BridgeSnapshotBundle(
        app: store.appSnapshot, library: store.librarySnapshot, wallpaperOptions: nil,
        monitorInformation: store.monitorInformationSnapshot, settings: store.settingsSnapshot)
    }
    let panel = try PanelFixture(
      store: store, bridge: bridge, displayTitles: .renderer, welcomeSeen: welcomeSeen)
    do {
      try await panel.start()
      let model = panel.controller.welcome
      model.open()
      try await body(panel, model, bridge)
      model.close()
    } catch {
      panel.controller.welcome.close()
      await panel.shutdown()
      throw error
    }
    await panel.shutdown()
  }

  // MARK: Lifecycle

  /// The guide is up until its flag is set, and ending it sets the flag once, in the shared key a
  /// relaunch and What's New read.
  func testTheGuideStaysUpUntilItEndsAndEndingItStoresTheFlag() async throws {
    try await withGuide { panel, model, _ in
      let controller = panel.controller
      XCTAssertFalse(controller.welcomeSeen)
      XCTAssertTrue(controller.shell.isWelcomeOpen, "A fresh install opens the guide by itself")
      XCTAssertEqual(model.step, .language)
      XCTAssertFalse(PanelPreferences.welcomeSeen(in: panel.defaults))

      model.go(to: .start)
      XCTAssertTrue(controller.shell.isWelcomeOpen, "Moving through the pages ends nothing")

      model.finish()
      XCTAssertTrue(controller.welcomeSeen)
      XCTAssertTrue(PanelPreferences.welcomeSeen(in: panel.defaults))
      XCTAssertFalse(controller.shell.isWelcomeOpen)
      XCTAssertFalse(model.isOpen)

      let reopened = panel.buildController()
      XCTAssertTrue(reopened.welcomeSeen, "A relaunch does not show the guide again")
      XCTAssertFalse(reopened.shell.isWelcomeOpen)
      reopened.stop()
    }
  }

  /// A guide replayed from Settings starts over at page one and ends without touching the flag.
  func testAReplayFromSettingsStartsAtPageOneAndLeavesTheFlagAlone() async throws {
    try await withGuide(welcomeSeen: true) { panel, model, _ in
      let controller = panel.controller
      model.close()
      XCTAssertFalse(controller.shell.isWelcomeOpen)

      model.go(to: .start)  // a previous run left the model there
      controller.shell.isWelcomeRequested = true
      XCTAssertTrue(controller.shell.isWelcomeOpen, "Show again opens it")
      model.open()
      XCTAssertEqual(model.step, .language)

      // The key is gone: a finish that wrote the flag would bring it back.
      panel.defaults.removeObject(forKey: PanelPreferences.welcomeSeenKey)
      model.go(to: .start)
      model.finish()
      XCTAssertFalse(controller.shell.isWelcomeOpen)
      XCTAssertTrue(controller.welcomeSeen)
      XCTAssertNil(
        panel.defaults.object(forKey: PanelPreferences.welcomeSeenKey),
        "A replayed guide never rewrites the first-run flag")
    }
  }

  /// A closed window releases the controller and its guide: the next one starts at page one with
  /// nothing drafted, while what was applied at once stays.
  func testAReopenedWindowRestartsTheGuideAndKeepsWhatWasApplied() async throws {
    try await withGuide { panel, model, bridge in
      model.go(to: .performance)
      model.choosePreset(.low)
      await model.chooseAppearance(.dark)
      XCTAssertEqual(panel.controller.themePreferences.mode, .dark)

      let reopened = panel.buildController()
      let next = reopened.welcome
      next.open()
      XCTAssertTrue(reopened.shell.isWelcomeOpen, "The flag was never set")
      XCTAssertEqual(next.step, .language)
      XCTAssertTrue(next.performance.isEmpty, "Drafts do not survive the window")
      XCTAssertEqual(reopened.themePreferences.mode, .dark, "Applied at once stays applied")
      XCTAssertTrue(bridge.renderScaleCalls.isEmpty)
      next.close()
      reopened.stop()
    }
  }

  func testMovingIsBlockedWhileAChoiceIsBeingCommittedAndAMoveClearsTheMessage() async throws {
    try await withGuide { _, model, _ in
      model.go(to: .preferences)
      XCTAssertEqual(model.step, .preferences)
      model.back()
      XCTAssertEqual(model.step, .performance)
      model.go(to: .language)
      model.back()
      XCTAssertEqual(model.step, .language, "There is nothing before the first page")
      model.go(to: .start)
      model.next()
      XCTAssertEqual(model.step, .start, "Nor after the last")

      // A failed lock-screen change leaves its reason on the page, and moving clears it.
      model.go(to: .preferences)
      await model.setLockScreen(true)
      XCTAssertNotNil(model.error)
      model.go(to: .tips)
      XCTAssertNil(model.error)
    }
  }

  // MARK: Page 1

  /// Language and appearance apply at once; Skip puts back what the guide opened with, appearance
  /// first and then the language, and moves on.
  func testLanguageAndAppearanceApplyAtOnceAndSkipRestoresThem() async throws {
    try await withGuide { panel, model, bridge in
      let controller = panel.controller
      XCTAssertEqual(model.appearance, .system)
      XCTAssertEqual(model.languageChoice, AppLanguageStore.systemChoice)

      await model.chooseAppearance(.dark)
      XCTAssertEqual(controller.themePreferences.mode, .dark, "Dark applies at once")
      await model.chooseLanguage("zh-Hans")
      XCTAssertEqual(model.languageChoice, "zh-Hans")
      XCTAssertEqual(controller.effectiveLanguage.tag, "zh-Hans")
      XCTAssertEqual(bridge.labelLanguageCalls.last, ["zh-chs", "en-us"], "Wallpaper labels follow too")

      await model.skipLanguage()
      XCTAssertEqual(controller.themePreferences.mode, .system, "Skip puts the appearance back")
      XCTAssertEqual(model.languageChoice, AppLanguageStore.systemChoice, "and the language")
      XCTAssertEqual(model.step, .performance)
    }
  }

  func testContinueKeepsTheChoicesAndAnUnshippedLanguageChangesNothing() async throws {
    try await withGuide { panel, model, _ in
      await model.chooseLanguage("ja")
      await model.chooseAppearance(.light)
      model.next()
      XCTAssertEqual(model.step, .performance)
      XCTAssertEqual(model.languageChoice, "ja")
      XCTAssertEqual(panel.controller.themePreferences.mode, .light)

      await model.chooseLanguage("fr")
      XCTAssertEqual(model.languageChoice, "ja", "A language the app does not ship is not applied")
      XCTAssertNil(model.error)
    }
  }

  // MARK: Page 2

  /// A preset or the slider is a draft: nothing reaches the engine until Continue, which sends the
  /// limit and then the scale of what changed, and the slider replaces the preset's limit.
  func testPerformanceDraftsSendNothingUntilContinueThenOnlyWhatChanged() async throws {
    try await withGuide { _, model, bridge in
      model.go(to: .performance)
      XCTAssertEqual(model.shownPreset, .high, "A fresh install is on High")
      XCTAssertEqual(model.frameRateSlider.maximum, 61)
      XCTAssertEqual(model.frameRatePosition, 61, "No limit is the top of the slider")

      model.choosePreset(.low)
      XCTAssertEqual(model.shownPreset, .low)
      XCTAssertEqual(model.frameRateSlider.readout(atPosition: model.frameRatePosition), "30 fps")

      model.setFrameRatePosition(60)
      XCTAssertEqual(
        model.frameRateSlider.readout(atPosition: model.frameRatePosition), "60 fps",
        "The display's full refresh is a limit of its own, below No limit")
      model.setFrameRatePosition(24)
      XCTAssertNil(model.shownPreset, "24 fps with the Low scale matches no preset: Custom")
      XCTAssertTrue(bridge.frameRateCapCalls.isEmpty && bridge.renderScaleCalls.isEmpty)
      XCTAssertEqual(model.unsavedPerformanceCount, 2)

      await model.continuePerformance()
      XCTAssertEqual(bridge.committed, ["frameRateCap:24", "renderScale:0.5"], "Limit first, then scale")
      XCTAssertEqual(model.step, .preferences)
      XCTAssertTrue(model.performance.isEmpty)
      XCTAssertEqual(model.savedFrameRateCap, 24)
    }
  }

  func testPerformanceContinueWithNothingChangedSendsNothingAndSkipDropsTheDrafts() async throws {
    try await withGuide { _, model, bridge in
      model.go(to: .performance)
      model.choosePreset(.high)  // the same as what is saved
      XCTAssertEqual(model.unsavedPerformanceCount, 0, "A draft equal to the saved value is no change")
      await model.continuePerformance()
      XCTAssertTrue(bridge.committed.isEmpty)
      XCTAssertEqual(model.step, .preferences)

      model.go(to: .performance)
      model.choosePreset(.medium)
      model.skipPerformance()
      XCTAssertTrue(model.performance.isEmpty, "Skip discards the drafts")
      XCTAssertTrue(bridge.committed.isEmpty)
      XCTAssertEqual(model.step, .preferences)
    }
  }

  /// Back and the dots keep the drafts, and the recap on the last page counts and offers to review
  /// them.
  func testDraftsSurviveMovingBetweenPagesAndTheRecapCountsThem() async throws {
    try await withGuide { _, model, _ in
      model.go(to: .performance)
      model.choosePreset(.medium)
      model.go(to: .preferences)
      model.preferences.set(.batteryMode(.pause))
      model.go(to: .start)

      XCTAssertFalse(model.performance.isEmpty)
      let recap = model.recap
      XCTAssertEqual(
        recap.unsaved, [.init(step: .performance, count: 2), .init(step: .preferences, count: 1)])
      model.go(to: recap.unsaved[0].step)
      XCTAssertEqual(model.step, .performance)
      XCTAssertEqual(model.shownPreset, .medium, "Review shows what was drafted")
    }
  }

  // MARK: Page 3

  /// The drafted preferences are committed in the order they were chosen, and a refusal stops the
  /// commit with its reason: what went before is saved, what comes after stays a draft.
  func testPreferencesCommitInOrderAndStopAtTheFirstRefusal() async throws {
    try await withGuide { panel, model, bridge in
      bridge.launchAtLoginFailure = "Move the app to Applications first."
      model.go(to: .preferences)
      model.preferences.set(.batteryMode(.pause))
      model.preferences.set(.launchAtLogin(true))
      XCTAssertEqual(model.shownPreferences.batteryMode, .pause)
      XCTAssertTrue(bridge.committed.isEmpty, "A draft is not sent")

      await model.continuePreferences()
      XCTAssertEqual(bridge.committed, ["batteryMode:pause", "launchAtLogin:true"])
      XCTAssertEqual(model.error, "Move the app to Applications first.")
      XCTAssertEqual(model.step, .preferences, "A refusal stays on the page")
      XCTAssertEqual(panel.store.settingsSnapshot.batteryMode, .pause, "The first was saved")
      XCTAssertEqual(model.unsavedPreferencesCount, 1, "Only the refused one is still a draft")

      model.preferences.set(.launchAtLogin(false))  // back to what is saved: no change
      await model.continuePreferences()
      XCTAssertEqual(bridge.committed.count, 2, "Nothing is sent again")
      XCTAssertEqual(model.step, .tips)
    }
  }

  /// The lock screen is not a draft: it applies at once, a refusal leaves the switch where the
  /// service says it is, and applying it commits nothing else.
  func testTheLockScreenAppliesAtOnceAndARefusalNeitherMovesItNorCommitsTheDrafts() async throws {
    try await withGuide { panel, model, bridge in
      model.go(to: .preferences)
      model.preferences.set(.batteryMode(.pause))
      XCTAssertFalse(panel.controller.lockScreenState.isAvailable, "No lock-screen service in the fixture")

      await model.setLockScreen(true)
      XCTAssertFalse(panel.controller.lockScreenState.isRequested, "The switch stays off")
      XCTAssertNotNil(model.error, "and the reason is on the page")
      XCTAssertTrue(bridge.committed.isEmpty, "Applying the lock screen commits no draft")
      XCTAssertFalse(model.preferences.isEmpty)
    }
  }

  /// Skip drops the preference drafts and puts back a lock screen the guide changed.
  func testSkippingPreferencesDropsTheDraftsAndMovesOn() async throws {
    try await withGuide { _, model, bridge in
      model.go(to: .preferences)
      model.preferences.set(.keepsWindows(true))
      await model.skipPreferences()
      XCTAssertTrue(model.preferences.isEmpty)
      XCTAssertTrue(bridge.committed.isEmpty)
      XCTAssertEqual(model.step, .tips)
    }
  }

  // MARK: Closing choices

  func testBrowsingEndsTheGuideThenOpensTheWorkshop() async throws {
    try await withGuide { panel, model, _ in
      model.go(to: .start)
      await model.browse().value
      XCTAssertTrue(panel.controller.welcomeSeen)
      XCTAssertTrue(PanelPreferences.welcomeSeen(in: panel.defaults))
      XCTAssertEqual(panel.navigation.selection, .workshop)
      XCTAssertNil(panel.controller.errors.message)
    }
  }

  /// Import wallpapers ends the guide, shows Installed and opens the library's Import popover (what
  /// an import does, what to do with a wallpaper already there), never the file picker directly.
  func testImportingEndsTheGuideShowsInstalledAndOpensTheImportPopover() async throws {
    try await withGuide { panel, model, _ in
      var asked = 0
      panel.controller.chooseImportFiles = { _, _ in
        asked += 1
        return nil
      }
      let library = panel.controller.library
      panel.navigation.selection = .settings
      model.go(to: .start)
      await model.importWallpapers().value
      XCTAssertTrue(panel.controller.welcomeSeen)
      XCTAssertFalse(panel.controller.shell.isWelcomeOpen)
      XCTAssertEqual(panel.navigation.selection, .wallpaper)
      XCTAssertNil(library.importAnchor, "The popover waits for the window to show Installed")

      model.openWaitingImportPopover()  // what the host does once it has
      XCTAssertEqual(library.importAnchor, .page, "The Import button's popover")
      XCTAssertTrue(panel.controller.shell.isPopoverOpen)
      XCTAssertEqual(asked, 0, "Nothing is picked until the popover's own button asks")

      library.closeImport()
      model.openWaitingImportPopover()
      XCTAssertNil(library.importAnchor, "One request opens it once")
    }
  }

  // MARK: Skip setup

  /// Skip setup ends the guide from every page but the last, as Start using the app does: what was
  /// applied at once stays, nothing is committed, and only a first run writes the flag. On the last
  /// page it is not offered and does nothing.
  func testSkipSetupEndsTheGuideFromEveryPageButTheLastAndKeepsWhatApplied() async throws {
    try await withGuide { panel, model, bridge in
      let controller = panel.controller
      await model.chooseAppearance(.dark)
      XCTAssertTrue(model.offersSkipSetup)
      model.skipSetup()
      XCTAssertTrue(controller.welcomeSeen, "A first run's flag is set")
      XCTAssertTrue(PanelPreferences.welcomeSeen(in: panel.defaults))
      XCTAssertFalse(controller.shell.isWelcomeOpen)
      XCTAssertFalse(model.isOpen)
      XCTAssertEqual(controller.themePreferences.mode, .dark, "What applied at once stays")

      // The key is gone: a replay that wrote the flag would bring it back.
      panel.defaults.removeObject(forKey: PanelPreferences.welcomeSeenKey)
      for step in WelcomeStep.allCases where !step.isLast {
        controller.shell.isWelcomeRequested = true
        model.open()
        model.go(to: step)
        XCTAssertTrue(model.offersSkipSetup, "\(step)")
        model.skipSetup()
        XCTAssertFalse(controller.shell.isWelcomeOpen, "\(step)")
        XCTAssertFalse(model.isOpen, "\(step)")
      }
      XCTAssertNil(panel.defaults.object(forKey: PanelPreferences.welcomeSeenKey), "Replays leave the flag alone")
      XCTAssertEqual(controller.themePreferences.mode, .dark)
      XCTAssertTrue(bridge.committed.isEmpty, "Skipping commits nothing")

      controller.shell.isWelcomeRequested = true
      model.open()
      model.go(to: .start)
      XCTAssertFalse(model.offersSkipSetup, "Start using the app ends the guide there")
      model.skipSetup()
      XCTAssertTrue(controller.shell.isWelcomeOpen, "Skip setup does nothing on the last page")
      XCTAssertEqual(model.step, .start)
    }
  }

  /// With drafts not saved, Skip setup shows them on the Start page instead of ending: nothing is
  /// dropped and nothing is saved, and ending the guide from there saves nothing either.
  func testSkipSetupShowsUnsavedDraftsOnTheStartPageAndSavesNothing() async throws {
    try await withGuide { panel, model, bridge in
      let controller = panel.controller
      model.go(to: .performance)
      model.choosePreset(.low)
      model.go(to: .language)
      let focus = model.titleFocusRequest
      model.skipSetup()
      XCTAssertEqual(model.step, .start, "The recap shows what is not saved")
      XCTAssertTrue(controller.shell.isWelcomeOpen)
      XCTAssertFalse(controller.welcomeSeen)
      XCTAssertEqual(model.recap.unsaved.map(\.step), [.performance])
      XCTAssertFalse(model.performance.isEmpty, "The drafts are kept for Review")
      XCTAssertEqual(model.titleFocusRequest, focus + 1, "VoiceOver hears where it landed")
      XCTAssertTrue(bridge.committed.isEmpty)

      model.skipSetup()
      XCTAssertEqual(model.step, .start, "Again on Start: nothing happens")
      XCTAssertTrue(controller.shell.isWelcomeOpen)

      model.finish()
      XCTAssertTrue(controller.welcomeSeen)
      XCTAssertTrue(bridge.committed.isEmpty, "Ending the guide saves no draft")
      XCTAssertTrue(bridge.renderScaleCalls.isEmpty && bridge.frameRateCapCalls.isEmpty)
    }
  }

  /// Escape is Skip setup while the guide is open, and is used up even where that does nothing (a
  /// second press on the Start page it led to); with the guide closed it is the shell's again.
  func testEscapeIsSkipSetupWhileTheGuideIsOpen() async throws {
    try await withGuide { panel, model, bridge in
      let shell = panel.controller.shell
      model.go(to: .performance)
      model.choosePreset(.low)
      XCTAssertTrue(shell.handleEscape())
      XCTAssertEqual(model.step, .start, "With a draft it lands on the recap")
      XCTAssertTrue(shell.handleEscape(), "On Start the key is used up")
      XCTAssertEqual(model.step, .start, "and does nothing")
      XCTAssertTrue(shell.isWelcomeOpen)

      model.go(to: .performance)
      model.skipPerformance()
      XCTAssertEqual(model.step, .preferences)
      XCTAssertTrue(shell.handleEscape())
      XCTAssertFalse(shell.isWelcomeOpen, "With nothing unsaved the guide ends")
      XCTAssertFalse(shell.handleEscape(), "With the guide closed Escape is the shell's again")
      XCTAssertTrue(bridge.committed.isEmpty)
    }
  }

  // MARK: Preferences rows

  /// The Launch at login switch stays usable while a login item the person switched off in System
  /// Settings waits for approval (the note says where to allow it), and is off outside
  /// Applications, where the note says to move the app.
  func testTheLoginItemRowExplainsApprovalAndStaysUsable() async throws {
    try pinPanelLanguageToEnglish()
    try await withGuide { panel, model, _ in
      let controller = panel.controller
      panel.store.settingsSnapshot.launchAtLoginAvailable = true
      panel.store.settingsSnapshot.launchAtLoginNeedsApproval = true
      XCTAssertEqual(
        controller.generalSettings.launchAtLogin.note,
        "Allow WallpaperMachine in System Settings → General → Login Items to launch it at login.")
      XCTAssertTrue(model.canChangeLaunchAtLogin, "The switch stays usable")

      panel.store.settingsSnapshot.launchAtLoginNeedsApproval = false
      XCTAssertNil(controller.generalSettings.launchAtLogin.note, "Nothing to explain")
      XCTAssertTrue(model.canChangeLaunchAtLogin)

      panel.store.settingsSnapshot.launchAtLoginAvailable = false
      XCTAssertEqual(
        controller.generalSettings.launchAtLogin.note, "Move the app to Applications to enable.")
      XCTAssertFalse(model.canChangeLaunchAtLogin, "Outside Applications it cannot be changed")
    }
  }

  func testTheLockScreenRowSaysWhyItWaitsAndWhenItCanBeUsed() throws {
    try pinPanelLanguageToEnglish()
    func state(available: Bool, busy: Bool = false, status: String = "Off") -> LockScreenState {
      LockScreenState(
        kind: .lockScreen, isRequested: false, isAvailable: available, isBusy: busy,
        status: status, error: nil)
    }
    let unavailable = LockScreenRow.make(
      state: state(available: false, status: "Requires macOS 26 or later"), requestIsRunning: false,
      isCommitting: false)
    XCTAssertEqual(unavailable.note, .unavailable("Requires macOS 26 or later"))
    XCTAssertFalse(unavailable.isSwitchEnabled)
    XCTAssertEqual(
      LockScreenRow.make(state: state(available: false, status: ""), requestIsRunning: false, isCommitting: false).note,
      .unavailable("Unavailable"))

    let idle = LockScreenRow.make(state: state(available: true), requestIsRunning: false, isCommitting: false)
    XCTAssertEqual(idle.note, .promise)
    XCTAssertTrue(idle.isSwitchEnabled)

    let committing = LockScreenRow.make(state: state(available: true), requestIsRunning: false, isCommitting: true)
    XCTAssertFalse(committing.isSwitchEnabled, "A commit of the drafts holds every control")

    let busy = LockScreenRow.make(
      state: state(available: true, busy: true, status: "Preparing"), requestIsRunning: false, isCommitting: false)
    XCTAssertEqual(busy.note, .working("Preparing…"), "An ellipsis is added to the service's words")
    XCTAssertFalse(busy.isSwitchEnabled)
    let alreadyEllipsis = LockScreenRow.make(
      state: state(available: true, busy: true, status: "Preparing…"), requestIsRunning: false, isCommitting: false)
    XCTAssertEqual(alreadyEllipsis.note, .working("Preparing…"), "never doubled")

    let requested = LockScreenRow.make(state: state(available: true), requestIsRunning: true, isCommitting: false)
    XCTAssertEqual(requested.note, .working("Updating…"))
    XCTAssertFalse(requested.isSwitchEnabled)
  }
}
