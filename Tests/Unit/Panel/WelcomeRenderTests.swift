import AppKit
import SwiftUI
import XCTest

@testable import WallpaperMachine

/// The first-run guide and the support prompt drawn in a window that is never shown: each page lays
/// out in the smallest window and the default one, light and dark, in every shipped language,
/// without asking for more room and without an AppKit exception, and the host follows the guide's
/// flag. What an offscreen window cannot show (focus rings, hover, VoiceOver, the real dimming of
/// the title bar) is listed in the guide's contract.
@MainActor
final class WelcomeRenderTests: PanelTestCase {
  override func tearDown() async throws {
    // Each harness bound the shared panel language to its own store.
    PanelLocale.shared.bind(to: .testHost)
    try await super.tearDown()
  }

  private let sizes = [NSSize(width: 760, height: 560), NSSize(width: 1240, height: 800)]

  private func assertFits(
    _ harness: WelcomeRenderHarness, at size: NSSize, _ context: String,
    file: StaticString = #filePath, line: UInt = #line
  ) {
    let measured = harness.hosting.sizeThatFits(in: size)
    XCTAssertEqual(
      measured.width, size.width, accuracy: 1, "\(context): the root must accept the window width",
      file: file, line: line)
    XCTAssertLessThanOrEqual(
      measured.height, size.height + 1, "\(context): the guide must not force a taller window",
      file: file, line: line)
    XCTAssertLessThanOrEqual(
      harness.widestSplitView, size.width + 1, "\(context): the panel must fit the window",
      file: file, line: line)
    XCTAssertFalse(harness.window.isVisible, "\(context): layout must stay offscreen", file: file, line: line)
  }

  /// Every page, in the two sizes that matter, in every language: no page asks for a larger window
  /// (a page that is taller than its card scrolls), and the guide the host shows is the one asked for.
  func testEveryPageFitsTheSmallestAndTheDefaultWindowInEveryLanguage() async throws {
    try await withPanel(welcomeSeen: false) { panel in
      for language in AppLanguage.supported.map(\.tag) {
        let harness = try WelcomeRenderHarness(panel: panel, language: language)
        for size in sizes {
          try await harness.layout(at: size)
          XCTAssertTrue(panel.controller.welcome.isOpen, "The host opens the guide by itself")
          for step in WelcomeStep.allCases {
            panel.controller.welcome.go(to: step)
            try await harness.layout(at: size)
            XCTAssertEqual(panel.controller.welcome.step, step)
            assertFits(harness, at: size, "\(language) \(step) at \(Int(size.width))")
          }
          panel.controller.welcome.go(to: .language)
        }
        harness.close()
      }
    }
  }

  func testEveryPageFitsInDarkAppearanceToo() async throws {
    try await withPanel(welcomeSeen: false) { panel in
      let harness = try WelcomeRenderHarness(panel: panel, dark: true)
      for size in sizes {
        for step in WelcomeStep.allCases {
          panel.controller.welcome.go(to: step)
          try await harness.layout(at: size)
          assertFits(harness, at: size, "dark \(step) at \(Int(size.width))")
        }
      }
      harness.close()
    }
  }

  /// With drafts and a failure on the page the pages still fit.
  func testPagesWithDraftsAndMessagesStillFit() async throws {
    try await withPanel(welcomeSeen: false) { panel in
      let harness = try WelcomeRenderHarness(panel: panel)
      let model = panel.controller.welcome
      model.choosePreset(.low)
      model.setFrameRatePosition(24)
      model.preferences.set(.batteryMode(.pause))
      model.go(to: .preferences)
      await model.setLockScreen(true)  // refused: a message on the page
      XCTAssertNotNil(model.error)
      for size in sizes {
        for step in [WelcomeStep.performance, .preferences, .start] {
          model.go(to: step)
          if step == .preferences { await model.setLockScreen(true) }
          try await harness.layout(at: size)
          assertFits(harness, at: size, "drafts \(step) at \(Int(size.width))")
        }
      }
      harness.close()
    }
  }

  // MARK: The host

  /// The host opens the guide while the first-run flag is unset or Settings asked for it, starts it
  /// over each time, and closes it for good with the flag.
  func testTheHostFollowsTheFlagAndTheRequest() async throws {
    try await withPanel(welcomeSeen: true) { panel in
      let harness = try WelcomeRenderHarness(panel: panel)
      let controller = panel.controller
      try await harness.layout(at: sizes[1])
      XCTAssertFalse(controller.welcome.isOpen, "A returning user sees no guide")

      controller.shell.isWelcomeRequested = true
      try await harness.layout(at: sizes[1])
      XCTAssertTrue(controller.welcome.isOpen, "Show again opens it")
      XCTAssertEqual(controller.welcome.step, .language)

      controller.welcome.go(to: .start)
      controller.welcome.finish()
      try await harness.layout(at: sizes[1])
      XCTAssertFalse(controller.welcome.isOpen)
      XCTAssertFalse(controller.shell.isWelcomeOpen)
      XCTAssertTrue(controller.welcomeSeen)

      controller.shell.isWelcomeRequested = true
      try await harness.layout(at: sizes[1])
      XCTAssertEqual(controller.welcome.step, .language, "Each replay starts over")
      harness.close()
    }
  }

  func testAFirstRunGuideCoversTheWindowUntilItEnds() async throws {
    try await withPanel(welcomeSeen: false) { panel in
      let harness = try WelcomeRenderHarness(panel: panel)
      try await harness.layout(at: sizes[1])
      XCTAssertTrue(panel.controller.shell.isWelcomeOpen)
      XCTAssertTrue(panel.controller.welcome.isOpen)
      panel.controller.welcome.finish()
      try await harness.layout(at: sizes[1])
      XCTAssertFalse(panel.controller.shell.isWelcomeOpen)
      XCTAssertFalse(panel.controller.welcome.isOpen)
      harness.close()
    }
  }

  // MARK: The window under the guide

  /// While the guide is up nothing behind it looks usable or can be reached: the toolbar with the
  /// tabs is hidden (not emptied, so its items are never inserted again), the title bar names
  /// nothing, and the panel is out of the accessibility tree. Finishing brings all of it back.
  func testTheGuideHidesTheToolbarAndLocksThePanelBehindItUntilItEnds() async throws {
    try await withPanel(welcomeSeen: false) { panel in
      let harness = try WelcomeRenderHarness(panel: panel)
      try await harness.layout(at: sizes[1])
      let window = harness.window
      let library = panel.controller.library
      let toolbar = try XCTUnwrap(window.toolbar, "The panel's toolbar is bridged into the window")
      let items = toolbar.items.map(\.itemIdentifier)
      XCTAssertFalse(toolbar.isVisible, "No toolbar control shows above the scrim")
      XCTAssertNotEqual(window.title, "All wallpapers", "The title bar does not name the page behind")
      let content = AccessibilityElement(object: try XCTUnwrap(window.contentView))
      XCTAssertNil(content.first(identifier: "scope-all"), "The library's views are hidden from VoiceOver")

      panel.controller.welcome.finish()
      try await harness.layout(at: sizes[1])
      XCTAssertTrue(window.toolbar === toolbar, "The same toolbar")
      XCTAssertTrue(toolbar.isVisible, "The toolbar shows again")
      XCTAssertEqual(toolbar.items.map(\.itemIdentifier), items, "with the same items, never re-inserted")
      XCTAssertEqual(window.title, "All wallpapers")
      XCTAssertNotNil(content.first(identifier: "scope-all"), "The library's views are back")
      library.show(.favorites)
      try await harness.layout(at: sizes[1])
      XCTAssertEqual(window.title, "Favorites")

      // Moving between two pages that share the search bar still works (PageSearchBar).
      panel.navigation.selection = .pixiv
      try await harness.layout(at: sizes[1])
      panel.navigation.selection = .wallpaper
      try await harness.layout(at: sizes[1])
      XCTAssertEqual(window.title, "Favorites")
      harness.close()
    }
  }

  /// A guide replayed from Settings leaves the Settings behind it alone: the search field is
  /// disabled and the section list ignores the arrow keys, until the guide ends.
  func testTheSettingsBehindAReplayedGuideCanBeNeitherSearchedNorChosen() async throws {
    try await withPanel(welcomeSeen: true) { panel in
      panel.navigation.selection = .settings
      let settings = panel.controller.settings
      let harness = try WelcomeRenderHarness(panel: panel)
      try await harness.layout(at: sizes[1])
      panel.controller.shell.isWelcomeRequested = true
      try await harness.layout(at: sizes[1])
      let search = try XCTUnwrap(harness.searchFields().first)
      XCTAssertFalse(search.isEnabled, "The Settings search waits behind the guide")
      let section = settings.selectedSection
      let list = try XCTUnwrap(harness.lists().first)
      harness.pressDownArrow(in: list)
      try await harness.layout(at: sizes[1])
      XCTAssertEqual(settings.selectedSection, section, "and no section is chosen")

      panel.controller.welcome.finish()
      try await harness.layout(at: sizes[1])
      XCTAssertTrue(try XCTUnwrap(harness.searchFields().first).isEnabled)
      harness.pressDownArrow(in: try XCTUnwrap(harness.lists().first))
      try await harness.layout(at: sizes[1])
      XCTAssertNotEqual(settings.selectedSection, section, "The sections work again")
      harness.close()
    }
  }

  /// Import wallpapers from a guide replayed on Settings shows Installed with the Import popover
  /// open, and the window knows it is open: the popover opens after the page change has closed the
  /// popovers of the page that was left, as the root does.
  func testImportFromAReplayedGuideOpensTheImportPopoverAfterThePageChange() async throws {
    try await withPanel(welcomeSeen: true) { panel in
      let controller = panel.controller
      panel.navigation.selection = .settings
      // The root's rule, without the library page itself (whose popover a test never presents):
      // a change of page closes the popover that was open.
      let harness = try WelcomeRenderHarness(panel: panel) { controller in
        AnyView(WelcomePageChangeHost().panelTheme(theme: controller.theme, locale: PanelLocale.shared))
      }
      try await harness.layout(at: sizes[1])
      controller.shell.isWelcomeRequested = true
      try await harness.layout(at: sizes[1])
      XCTAssertTrue(controller.welcome.isOpen)

      controller.welcome.go(to: .start)
      await controller.welcome.importWallpapers().value
      try await harness.layout(at: sizes[1])
      XCTAssertFalse(controller.shell.isWelcomeOpen)
      XCTAssertEqual(panel.navigation.selection, .wallpaper)
      XCTAssertEqual(controller.library.importAnchor, .page, "The Import button's popover is open")
      XCTAssertTrue(controller.shell.isPopoverOpen, "and the window knows a popover is open")
      harness.close()
    }
  }

  // MARK: Steam

  /// The Tips page offers where to get a Steam account and Wallpaper Engine by the download
  /// dialog's rule: only while no Steam account is signed in on this Mac, so a guide replayed by
  /// someone signed in does not offer them. The page is hosted on its own: inside the guide's
  /// scroll view its own elements are not in the accessibility tree.
  func testTheTipsPageOffersTheSteamLinksOnlyUntilASteamAccountIsSaved() async throws {
    try await withPanel(welcomeSeen: false) { panel in
      let harness = try WelcomeRenderHarness(panel: panel) { controller in
        AnyView(WelcomeTipsPage().environment(controller.welcome))
      }
      @MainActor func links() -> AccessibilityElement? {
        AccessibilityElement(object: harness.hosting.view).first(identifier: "welcome-steam-join")
      }
      try await harness.layout(at: sizes[1])
      XCTAssertNotNil(links(), "No account yet: the page says where to get one")

      try await panel.saveSteamAccount()
      try await harness.layout(at: sizes[1])
      XCTAssertNotNil(panel.controller.steamAccount.saved)
      XCTAssertNil(links(), "Signed in: nothing to get")
      harness.close()
    }
  }

  // MARK: Skip setup

  /// Skip setup sits at the card's top right on every page but Start, clear of the progress dots,
  /// in the smallest window and in every language; Start, where Start using the app ends the
  /// guide, has none.
  func testSkipSetupSitsBesideTheProgressOnEveryPageButStart() async throws {
    try await withPanel(welcomeSeen: false) { panel in
      let model = panel.controller.welcome
      for language in AppLanguage.supported.map(\.tag) {
        let harness = try WelcomeRenderHarness(panel: panel, language: language)
        try await harness.layout(at: sizes[0])
        let dotNames = Set(WelcomeStep.allCases.map(\.name))
        for step in WelcomeStep.allCases {
          model.go(to: step)
          try await harness.layout(at: sizes[0])
          let tree = AccessibilityElement(object: harness.hosting.view).all()
          let skip = tree.first { $0.identifier == "welcome-skip-setup" }
          if step.isLast {
            XCTAssertNil(skip, "\(language): no Skip setup on Start")
            continue
          }
          let button = try XCTUnwrap(skip, "\(language) \(step): Skip setup is drawn")
          XCTAssertEqual(button.role, NSAccessibility.Role.button.rawValue, "\(language) \(step)")
          let dots = tree.filter { dotNames.contains($0.label) && $0.role == NSAccessibility.Role.button.rawValue }
          XCTAssertEqual(dots.count, WelcomeStep.allCases.count, "\(language) \(step): every dot is reachable")
          for dot in dots {
            XCTAssertFalse(
              button.frame.intersects(dot.frame), "\(language) \(step): Skip setup covers the \(dot.label) dot")
          }
        }
        model.go(to: .language)
        harness.close()
      }
    }
  }

  /// Escape presses Skip setup, the button's cancel shortcut: it ends a guide with nothing unsaved,
  /// and on Start, where there is no Skip setup, it does nothing.
  func testEscapeInTheWindowIsSkipSetup() async throws {
    try await withPanel(welcomeSeen: false) { panel in
      let harness = try WelcomeRenderHarness(panel: panel)
      let model = panel.controller.welcome
      let escape = try XCTUnwrap(
        NSEvent.keyEvent(
          with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0,
          windowNumber: harness.window.windowNumber, context: nil, characters: "\u{1B}",
          charactersIgnoringModifiers: "\u{1B}", isARepeat: false, keyCode: 53))
      model.go(to: .start)
      try await harness.layout(at: sizes[1])
      _ = harness.window.performKeyEquivalent(with: escape)
      try await harness.layout(at: sizes[1])
      XCTAssertTrue(panel.controller.shell.isWelcomeOpen, "Start has no Skip setup")

      model.go(to: .tips)
      try await harness.layout(at: sizes[1])
      XCTAssertTrue(harness.window.performKeyEquivalent(with: escape), "Escape is the button's shortcut")
      try await harness.layout(at: sizes[1])
      XCTAssertFalse(panel.controller.shell.isWelcomeOpen, "and ends the guide")
      XCTAssertTrue(panel.controller.welcomeSeen)
      harness.close()
    }
  }

  /// The Start page's lead changes when drafts are not saved, which Skip setup with drafts lands
  /// on: VoiceOver starts at the title, and the rows listing the drafts come later.
  func testTheStartLeadSaysWhenChangesAreNotSaved() async throws {
    try await withPanel(welcomeSeen: false) { panel in
      let model = panel.controller.welcome
      let harness = try WelcomeRenderHarness(panel: panel) { controller in
        AnyView(WelcomeStartPage().environment(controller.welcome))
      }
      @MainActor func texts() -> Set<String> {
        Set(AccessibilityElement(object: harness.hosting.view).all().map(\.text).filter { !$0.isEmpty })
      }
      try await harness.layout(at: sizes[1])
      let saved = texts()
      XCTAssertFalse(saved.isEmpty, "The hosted page must expose its accessible text")
      model.choosePreset(.low)
      XCTAssertGreaterThan(model.unsavedPerformanceCount, 0)
      try await harness.layout(at: sizes[1])
      let unsaved = texts()
      XCTAssertFalse(
        saved.subtracting(unsaved).isEmpty, "With drafts, the lead for a guide with nothing unsaved is gone")
      XCTAssertFalse(model.recap.unsaved.isEmpty)
      model.skipPerformance()
      try await harness.layout(at: sizes[1])
      XCTAssertTrue(model.recap.unsaved.isEmpty)
      XCTAssertEqual(texts(), saved, "Discarding the drafts must also remove the unsaved lead")
      XCTAssertFalse(harness.window.isVisible)
      harness.close()
    }
  }

  // MARK: The support prompt

  /// The sheet keeps to its width and a sensible height in every language, with and without the
  /// error line.
  func testTheSupportSheetFitsItsWidthInEveryLanguage() async throws {
    try await withPanel { panel in
      let controller = panel.controller
      for language in AppLanguage.supported.map(\.tag) {
        for failing in [false, true] {
          try controller.appLanguage.set(language)
          PanelLocale.shared.bind(to: controller.appLanguage)
          if failing {
            controller.openSupportURL = { _ in false }
            await controller.supportPrompt.choose(.star)
          }
          assertSheetFits(controller, language)
        }
      }
    }
  }

  /// The Discord invitation too, in every language, Chinese included, with and without the error
  /// line of a link that could not be opened.
  func testTheDiscordInvitationFitsItsWidthInEveryLanguage() async throws {
    let defaults = try TemporaryDefaults.make(for: self).defaults
    let prompt = SupportPromptStore(defaults: defaults)
    prompt.qualifyForDiscordInvitation()
    try await withPanel(supportPrompt: prompt) { panel in
      let controller = panel.controller
      panel.show()
      XCTAssertEqual(controller.supportPrompt.prompt, .discord)
      for failing in [false, true] {
        if failing {
          controller.openSupportURL = { _ in false }
          await controller.supportPrompt.choose(.joinDiscord)
          XCTAssertNotNil(controller.supportPrompt.error)
        }
        for language in AppLanguage.supported.map(\.tag) {
          try controller.appLanguage.set(language)
          PanelLocale.shared.bind(to: controller.appLanguage)
          assertSheetFits(controller, language)
        }
      }
    }
  }

  /// The battery question too, with its three choices and the playing wallpaper's measured share of
  /// a charge, in every language, with and without the error line of a refused setting.
  func testTheBatteryQuestionFitsItsWidthInEveryLanguage() async throws {
    let defaults = try TemporaryDefaults.make(for: self).defaults
    let prompt = SupportPromptStore(defaults: defaults)
    prompt.recordTelemetryAsked()
    try await withPanel(supportPrompt: prompt) { panel in
      let controller = panel.controller
      controller.batteryPercent = 54
      panel.store.settingsSnapshot.onBatteryPower = true
      panel.store.settingsSnapshot.batteryTargetFps = 30
      panel.store.settingsSnapshot.batteryRenderScale = 0.75
      panel.store.librarySnapshot.wallpapers = [
        BridgeWallpaperEntry(
          id: "scene", title: "Scene", kind: .projectScene, supported: true, active: true,
          selected: false, previewPath: nil)
      ]
      panel.store.appSnapshot.activeWallpaperIds = ["scene"]
      panel.store.appSnapshot.playbackState = .playing
      let ratings = WallpaperEnergyRatings(
        file: panel.root.appendingPathComponent("energy-ratings.json"), batteryWattHours: { 50 })
      ratings.record(
        WallpaperEnergyContext(
          wallpaperID: "scene",
          conditions: WallpaperEnergyConditions(displays: 1, frameRateCap: nil, renderScale: 1)),
        milliwatts: 4_600, seconds: 150)
      panel.store.wallpaperEnergyRatings = ratings
      panel.show()
      XCTAssertEqual(controller.supportPrompt.prompt, .battery)
      for failing in [false, true] {
        if failing {
          // No engine answer: the choice is refused and the sheet says why.
          await controller.supportPrompt.choose(.alwaysPauseOnBattery)
          XCTAssertNotNil(controller.supportPrompt.error)
        }
        for language in AppLanguage.supported.map(\.tag) {
          try controller.appLanguage.set(language)
          PanelLocale.shared.bind(to: controller.appLanguage)
          assertSheetFits(controller, language)
        }
      }
    }
  }

  private func assertSheetFits(
    _ controller: PanelController, _ language: String, file: StaticString = #filePath, line: UInt = #line
  ) {
    let hosting = NSHostingView(
      rootView: SupportPromptSheet(presenter: controller.supportPrompt)
        .panelTheme(theme: controller.theme, locale: PanelLocale.shared))
    hosting.layoutSubtreeIfNeeded()
    let size = hosting.fittingSize
    XCTAssertEqual(size.width, 440, accuracy: 1, "\(language): the sheet keeps its width", file: file, line: line)
    XCTAssertLessThan(size.height, 480, "\(language): the sheet stays small", file: file, line: line)
    XCTAssertGreaterThan(size.height, 200, "\(language): and shows its content", file: file, line: line)
  }
}
