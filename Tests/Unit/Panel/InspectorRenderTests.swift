import AppKit
import SwiftUI
import XCTest

@testable import WallpaperMachine

/// The inspector drawn offscreen in windows that are never shown: it takes the size it is given in
/// every shipped language and both appearances, never makes the panel's split view wider than its
/// window, and the controls it draws reach the controller (sliders by key, VoiceOver and pointer).
@MainActor
final class InspectorRenderTests: InspectorTestCase {
  override func tearDown() async throws {
    PanelLocale.shared.bind(to: .testHost)
    try await super.tearDown()
  }

  private func settle(_ milliseconds: Int = 300) async throws {
    try await Task.sleep(for: .milliseconds(milliseconds))
  }

  private func prepare(_ fixture: InspectorRenderFixture) async throws {
    try await fixture.panel.start()
    fixture.panel.show()
    _ = fixture.controller.libraryRows
    try await fixture.panel.waitUntil(timeout: 10) { fixture.controller.libraryMetrics.measured.count == 4 }
    _ = fixture.controller.libraryRows
  }

  /// Every view of a type below `root`.
  private func views<T: NSView>(_ type: T.Type, in root: NSView) -> [T] {
    var found: [T] = []
    func walk(_ view: NSView) {
      if let match = view as? T { found.append(match) }
      view.subviews.forEach(walk)
    }
    walk(root)
    return found
  }

  /// The inspector as the panel's window content, in a window made the way the app makes it.
  private func windowHosting(
    _ fixture: InspectorRenderFixture, size: NSSize, dark: Bool
  ) -> (window: NSWindow, hosting: NSHostingController<AnyView>) {
    let controller = fixture.controller
    let hosting = NSHostingController(
      rootView: AnyView(
        InstalledInspector()
          .environment(controller)
          .environment(\.panelImages, controller.images)
          .environment(\.panelIsVisible, true)
          .panelTheme(theme: controller.theme, locale: PanelLocale.shared)))
    hosting.sizingOptions = []
    let window = ControlPanelWindow.make(contentViewController: hosting, delegate: nil)
    window.setContentSize(size)
    hosting.view.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
    window.layoutIfNeeded()
    hosting.view.layoutSubtreeIfNeeded()
    return (window, hosting)
  }

  // MARK: Layout

  func testTheInspectorAcceptsTheWindowItIsGivenInEveryLanguageAndAppearance() async throws {
    let fixture = try InspectorRenderFixture()
    try await prepare(fixture)
    for language in AppLanguage.supported.map(\.tag) {
      let languages = AppLanguageStore(
        defaults: TemporaryDefaults.makeForCurrentTest().defaults, systemLanguages: [language])
      PanelLocale.shared.bind(to: languages)
      for dark in [false, true] {
        for size in [NSSize(width: 760, height: 560), NSSize(width: 1240, height: 800)] {
          let (window, hosting) = windowHosting(fixture, size: size, dark: dark)
          try await settle()
          hosting.view.layoutSubtreeIfNeeded()
          let measured = hosting.sizeThatFits(in: size)
          XCTAssertLessThanOrEqual(
            measured.width, size.width + 1,
            "\(language) \(dark ? "dark" : "light"): the inspector must not ask for more width")
          XCTAssertLessThanOrEqual(
            measured.height, size.height + 1, "\(language): and it scrolls, so no more height")
          XCTAssertFalse(window.isVisible, "layout stays offscreen")
          XCTAssertFalse(
            views(PanelNSSlider.self, in: hosting.view).isEmpty,
            "\(language): the options were drawn, not just the loading line")
          window.contentViewController = nil
          window.close()
        }
      }
    }
    await fixture.shutdown()
  }

  /// The footer with Revert and Apply changes and the Not applied marks are drawn only while an
  /// edit waits, so the test above never meets them: with a property and a display's scale factor
  /// waiting, the inspector still takes the smallest window it is given in every language and both
  /// appearances, footer and marks included.
  func testTheInspectorWithChangesWaitingAcceptsTheWindowInEveryLanguage() async throws {
    let fixture = try InspectorRenderFixture()
    try await prepare(fixture)
    fixture.store.wallpaperOptionsSnapshot?.dirty = true
    fixture.store.wallpaperOptionsSnapshot?.properties[1].staged = true
    fixture.store.wallpaperOptionsSnapshot?.displayConfigurations[1].staged = true
    let waiting = fixture.controller.inspectorOptions(for: InspectorRenderFixture.selected)
    XCTAssertEqual(
      waiting?.properties.first { $0.id == "clock" }?.mark, .notApplied, "precondition: the switch waits")
    XCTAssertEqual(waiting?.displays.map(\.hasStagedChanges), [false, true], "and the second display")
    let size = ControlPanelWindow.minimumContentSize
    for language in AppLanguage.supported.map(\.tag) {
      let languages = AppLanguageStore(
        defaults: TemporaryDefaults.makeForCurrentTest().defaults, systemLanguages: [language])
      PanelLocale.shared.bind(to: languages)
      for dark in [false, true] {
        let (window, hosting) = windowHosting(fixture, size: size, dark: dark)
        try await settle()
        hosting.view.layoutSubtreeIfNeeded()
        XCTAssertTrue(
          identifiers(in: hosting.view).isSuperset(of: ["inspector.revert", "inspector.applyChanges"]),
          "\(language): the footer is drawn while an edit waits")
        XCTAssertLessThanOrEqual(
          hosting.sizeThatFits(in: size).width, size.width + 1,
          "\(language) \(dark ? "dark" : "light"): the footer must not ask for more width")
        window.contentViewController = nil
        window.close()
      }
    }
    await fixture.shutdown()
  }

  func testTheEmptyInspectorAsksForASelectionInTheWindowToo() async throws {
    let fixture = try InspectorRenderFixture()
    fixture.store.appSnapshot.selectedWallpaperId = nil
    try await fixture.panel.start()
    let (window, hosting) = windowHosting(
      fixture, size: ControlPanelWindow.minimumContentSize, dark: false)
    try await settle()
    hosting.view.layoutSubtreeIfNeeded()
    XCTAssertLessThanOrEqual(hosting.sizeThatFits(in: ControlPanelWindow.minimumContentSize).width, 761)
    XCTAssertTrue(views(PanelNSSlider.self, in: hosting.view).isEmpty, "nothing selected, nothing to adjust")
    window.contentViewController = nil
    window.close()
    await fixture.shutdown()
  }

  /// The whole panel with the inspector open beside the Installed page: the 260-point column and the
  /// content inside it must not push the split view past the window (the trap F-C found).
  func testThePanelWithTheInspectorOpenFitsItsWindowAtTheSmallestSizeInEveryLanguage() async throws {
    let fixture = try InspectorRenderFixture()
    for language in AppLanguage.supported.map(\.tag) {
      let languages = AppLanguageStore(
        defaults: fixture.panel.defaults, systemLanguages: [language])
      let navigation = ControlPanelNavigation(selection: .wallpaper)
      let hosting = NSHostingController(
        rootView: ControlPanelView(
          store: fixture.store, navigation: navigation, workshop: fixture.panel.workshop,
          pixiv: PixivStore(),
          updater: AppUpdateStore(currentVersion: "0.1.0", client: DisabledAppUpdateClient()),
          imports: LibraryImportStore(), defaults: fixture.panel.defaults, appLanguage: languages))
      hosting.sizingOptions = []
      hosting.sceneBridgingOptions = [.toolbars, .title]
      let window = ControlPanelWindow.make(contentViewController: hosting, delegate: nil)
      for size in [ControlPanelWindow.minimumContentSize, ControlPanelWindow.initialContentSize] {
        window.setContentSize(size)
        window.layoutIfNeeded()
        hosting.view.layoutSubtreeIfNeeded()
        try await settle(500)
        hosting.view.layoutSubtreeIfNeeded()
        var widest: CGFloat = 0
        func walk(_ view: NSView) {
          if let split = view as? NSSplitView { widest = max(widest, split.frame.width) }
          view.subviews.forEach(walk)
        }
        walk(window.contentView!)
        XCTAssertLessThanOrEqual(
          widest, size.width + 1,
          "\(language) at \(Int(size.width)): the inspector's content must not widen the panel")
        XCTAssertLessThanOrEqual(hosting.sizeThatFits(in: size).width, size.width + 1)
      }
      window.contentViewController = nil
      window.close()
    }
    await fixture.shutdown()
  }

  /// The Compatibility card once the runtime reports the video's player with a problem: the line it
  /// leads with and the renderer's id beneath wrap inside the narrowest inspector column in every
  /// shipped language and both appearances, rather than asking for more width.
  func testTheCompatibilityCardsRendererLinesWrapInTheNarrowestColumnInEveryLanguage() async throws {
    let fixture = try InspectorRenderFixture(selecting: .video)
    try await prepare(fixture)
    let controller = fixture.controller
    controller.navigation.targetDisplayID = "primary"
    let reason = "the project's video file could not be found"
    // The bridge reports by live display id: "Studio Display (1 - Primary)" is display 1.
    fixture.store.settingsSnapshot.videoBackends = [
      BridgeVideoBackendReport(
        displayId: 1, displayName: "Studio Display", wallpaperId: InspectorRenderFixture.selected,
        wallpaperTitle: "Aurora", backend: "native", fallbackReason: reason)
    ]
    let state = try XCTUnwrap(controller.compatibilityState)
    XCTAssertEqual(state.fallbackReason, reason, "precondition: the report carries its problem")
    XCTAssertNotNil(
      InspectorWording.backendLine(state)?.detail, "precondition: the renderer's lines, not the note")
    let row = try XCTUnwrap(controller.libraryRows.first { $0.id == InspectorRenderFixture.selected })
    // The inspector draws its cards 16 points in from either edge of its column.
    let inner = InspectorColumn<EmptyView>.widths.lowerBound - 2 * 16
    for language in AppLanguage.supported.map(\.tag) {
      let languages = AppLanguageStore(
        defaults: TemporaryDefaults.makeForCurrentTest().defaults, systemLanguages: [language])
      PanelLocale.shared.bind(to: languages)
      for dark in [false, true] {
        let hosting = NSHostingController(
          rootView: AnyView(
            CompatibilityCard(state: state, row: row)
              .environment(controller)
              .environment(\.panelImages, controller.images)
              .environment(\.panelIsVisible, true)
              .panelTheme(theme: controller.theme, locale: PanelLocale.shared)))
        hosting.sizingOptions = []
        let window = NSWindow(
          contentRect: NSRect(x: 0, y: 0, width: inner, height: 600), styleMask: [.titled],
          backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentViewController = hosting
        hosting.view.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
        window.layoutIfNeeded()
        hosting.view.layoutSubtreeIfNeeded()
        let measured = hosting.sizeThatFits(in: NSSize(width: inner, height: 2000))
        XCTAssertLessThanOrEqual(
          measured.width, inner + 1,
          "\(language) \(dark ? "dark" : "light"): the card wraps its lines in the column")
        XCTAssertGreaterThan(measured.height, 0, "\(language): the card was drawn")
        window.contentViewController = nil
        window.close()
      }
    }
    await fixture.shutdown()
  }

  /// The quiet buttons of the Presets and Collections cards set the accent button's type at its
  /// size, so the narrowest inspector column must hold their whole words in every language: a
  /// chosen preset's Apply beside the menu, Delete and Cancel under a preset's Delete…, the name
  /// form's Save preset or Save with Cancel, and a new collection's Create with Cancel. Each is
  /// drawn as wide in that column as it is with all the room it wants, so none is cut short.
  func testThePresetAndCollectionButtonsKeepTheirWholeWordsInTheNarrowestColumnInEveryLanguage()
    async throws
  {
    let fixture = try InspectorRenderFixture()
    try await prepare(fixture)
    let id = InspectorRenderFixture.selected
    // The Collections card opens by itself for a wallpaper that is in a collection.
    try await fixture.controller.createCollection(name: "Evenings by the sea", wallpaperIDs: [id])
    let preset = PresetsState.Item(id: "evening", name: "Evening glow over the harbour")
    let presets = PresetsState(
      wallpaperID: id, items: [preset], isDirty: false, canSave: true, status: nil, error: nil)
    var chosen = PresetsBarState()
    chosen.pick(preset.id)
    var deleting = chosen
    deleting.beginDelete(of: preset)
    var saving = chosen
    saving.beginSave()
    var renaming = chosen
    renaming.beginRename(of: preset)
    let cards: [(name: String, buttons: [String], card: AnyView)] = [
      ("a chosen preset", ["Apply"], AnyView(PresetsCard(state: presets, bar: chosen))),
      ("Delete…", ["Delete", "Cancel"], AnyView(PresetsCard(state: presets, bar: deleting))),
      ("Save current…", ["Save preset", "Cancel"], AnyView(PresetsCard(state: presets, bar: saving))),
      ("Rename…", ["Save", "Cancel"], AnyView(PresetsCard(state: presets, bar: renaming))),
      ("New collection…", ["Create", "Cancel"], AnyView(CollectionsCard(wallpaperID: id, isNaming: true))),
    ]
    // The inspector draws its cards 16 points in from either edge of its column.
    let inner = InspectorColumn<EmptyView>.widths.lowerBound - 2 * 16
    /// The width of each button of `card` named in `names`, drawn `width` points wide.
    func buttons(_ card: AnyView, names: [String], width: CGFloat) async throws -> [String: CGFloat] {
      let (window, view) = fixture.host(size: NSSize(width: width, height: 640)) { card }
      try await settle()
      view.layoutSubtreeIfNeeded()
      var found: [String: CGFloat] = [:]
      for element in AccessibilityElement(object: view).all()
      where element.role == NSAccessibility.Role.button.rawValue && names.contains(element.label) {
        found[element.label] = element.frame.width
      }
      window.contentView = nil
      window.close()
      return found
    }
    for language in AppLanguage.supported.map(\.tag) {
      let languages = AppLanguageStore(
        defaults: TemporaryDefaults.makeForCurrentTest().defaults, systemLanguages: [language])
      PanelLocale.shared.bind(to: languages)
      for (name, keys, card) in cards {
        let names = keys.map { L(String.LocalizationValue($0)) }
        let drawn = try await buttons(card, names: names, width: inner)
        let roomy = try await buttons(card, names: names, width: 1000)
        XCTAssertEqual(Set(drawn.keys), Set(names), "\(language) \(name): every button is drawn")
        for label in names {
          let wanted = try XCTUnwrap(roomy[label], "\(language) \(name): \(label)")
          XCTAssertGreaterThan(wanted, 2 * 14, "\(language) \(name): \(label)'s words are measured")
          XCTAssertGreaterThanOrEqual(
            drawn[label] ?? 0, wanted - 0.5,
            "\(language) \(name): \(label) is cut short in the narrowest column")
        }
      }
    }
    await fixture.shutdown()
  }

  // MARK: The narrowest window

  /// A library too short to fill the Installed page: four wallpapers, whose grid is about as tall
  /// as its scroll view at some window widths.
  private func makeShortLibraryPanel() async throws -> PanelFixture {
    let panel = try makeController()
    panel.show()
    try panel.installLibrary(
      (0..<4).map {
        LibrarySpec("item\($0)", "Wallpaper \($0)", kind: .projectScene, preview: .picture(Double($0) / 4))
      })
    panel.configureDisplays()
    panel.showOnPrimary("item1")
    try await panel.loadLibrary()
    try await panel.settleLibrary()
    panel.store.appSnapshot.selectedWallpaperId = "item1"
    return panel
  }

  /// The whole panel in a window made the way the app makes it, never ordered front. The window's
  /// toolbar is left out: its title view logs AppKit constraint conflicts while any panel window is
  /// first laid out, which XCTest records, and nothing here is about the toolbar.
  private func panelWindow(_ panel: PanelFixture, size: NSSize, dark: Bool = false) -> (
    window: NSWindow, hosting: NSHostingController<AnyView>
  ) {
    let controller = panel.controller
    let hosting = NSHostingController(
      rootView: AnyView(
        PanelRootView()
          .frame(maxWidth: .infinity, maxHeight: .infinity)
          .environment(controller)
          .environment(\.panelImages, controller.images)))
    hosting.sizingOptions = []
    hosting.sceneBridgingOptions = []
    let window = ControlPanelWindow.make(contentViewController: hosting, delegate: nil)
    hosting.view.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
    lay(window, hosting, at: size)
    return (window, hosting)
  }

  private func lay(_ window: NSWindow, _ hosting: NSHostingController<AnyView>, at size: NSSize) {
    window.setContentSize(size)
    window.layoutIfNeeded()
    hosting.view.layoutSubtreeIfNeeded()
  }

  /// Gives every scroll view below `root` the scroll bars of a Mac set to always show them (or with
  /// a mouse), which take room from the content: a grid as tall as its scroll view then gains a
  /// scroll bar, narrows, gets shorter than the scroll view and loses it again.
  private func showScrollBarsAlways(in root: NSView) {
    for scrollView in views(NSScrollView.self, in: root) {
      scrollView.scrollerStyle = .legacy
      scrollView.autohidesScrollers = true
    }
  }

  private func widestSplitView(in window: NSWindow) -> CGFloat {
    views(NSSplitView.self, in: window.contentView!).map(\.frame.width).max() ?? 0
  }

  /// Lays the window out until `condition` has held for a few passes in a row, for at most a few
  /// seconds. A window just made, resized or toggled settles over several passes, and the split
  /// view reports the inspector it shows back to the shell along the way.
  private func layOut(
    _ window: NSWindow, _ hosting: NSHostingController<AnyView>, until condition: () -> Bool
  ) async throws {
    let deadline = Date().addingTimeInterval(8)
    var held = 0
    while held < 3, Date() < deadline {
      try await settle(100)
      window.layoutIfNeeded()
      hosting.view.layoutSubtreeIfNeeded()
      held = condition() ? held + 1 : 0
    }
  }

  /// At the smallest window the inspector column beside the Installed page leaves the page about
  /// 250 points. A new window made at that size, and one shrunk to it from the first size, start
  /// with the inspector closed (the person has not chosen yet); the toolbar's button then shows it
  /// beside the page and hides it again, in both appearances, and the panel stays inside its window.
  func testThePanelAtItsSmallestWindowShowsTheInspectorBesideANarrowPage() async throws {
    let smallest = ControlPanelWindow.minimumContentSize
    for dark in [false, true] {
      for madeSmall in [true, false] {
        let context = "\(dark ? "dark" : "light"), \(madeSmall ? "made small" : "shrunk")"
        // A new window is a new controller, with no choice of the person's about the inspector.
        let panel = try await makeShortLibraryPanel()
        let shell = panel.controller.shell
        let library = panel.controller.library
        let pageWidth = { library.geometry.viewport.width }
        // The page beside the inspector: the window less the column.
        let isBeside = { (380...520).contains(pageWidth()) }
        let isAlone = { pageWidth() > 600 }
        let (window, hosting) = panelWindow(
          panel, size: madeSmall ? smallest : ControlPanelWindow.initialContentSize, dark: dark)
        if !madeSmall {
          try await layOut(window, hosting) { shell.isInspectorShown && pageWidth() > 600 }
          lay(window, hosting, at: smallest)
        }
        try await layOut(window, hosting) { shell.isCompact && !shell.isInspectorShown && isAlone() }
        XCTAssertFalse(shell.isInspectorShown, "\(context): a narrow window starts without it")
        XCTAssertTrue(isAlone(), "\(context): the page takes the room")

        // What the toolbar's button does.
        shell.isInspectorShown.toggle()
        try await layOut(window, hosting, until: isBeside)
        XCTAssertTrue(isBeside(), "\(context): the inspector opens beside the page, not \(pageWidth())")
        XCTAssertLessThanOrEqual(widestSplitView(in: window), smallest.width + 1, context)
        shell.isInspectorShown.toggle()
        try await layOut(window, hosting, until: isAlone)
        XCTAssertTrue(isAlone(), "\(context): and closes again, not \(pageWidth())")
        shell.isInspectorShown.toggle()
        try await layOut(window, hosting, until: isBeside)
        XCTAssertTrue(isBeside(), "\(context): and opens again, not \(pageWidth())")
        XCTAssertLessThanOrEqual(widestSplitView(in: window), smallest.width + 1, context)
        XCTAssertFalse(window.isVisible, "layout stays offscreen")
        window.contentViewController = nil
        window.close()
        await panel.shutdown()
      }
    }
  }

  /// Every width from the first size down to the smallest and back, with the inspector closed and
  /// open, over a grid about as tall as its scroll view at some of them, with scroll bars that take
  /// room. A scroll bar coming and going used to change what the Installed grid reported about its
  /// scrolling on every layout pass, and each report asked the window for another pass from inside
  /// the pass, until AppKit gave up with "needing another Update Constraints in Window pass" and the
  /// app ended. A crash here fails the run.
  func testResizingThePanelOverAShortLibraryWithScrollBarsThatTakeRoomNeverLoopsItsLayout() async throws {
    let panel = try await makeShortLibraryPanel()
    defer { Task { await panel.shutdown() } }
    let shell = panel.controller.shell
    let first = ControlPanelWindow.initialContentSize
    let smallest = ControlPanelWindow.minimumContentSize
    let (window, hosting) = panelWindow(panel, size: first)
    try await settle(500)
    for open in [false, true] {
      shell.isInspectorShown = open
      try await settle(300)
      let down = stride(from: first.width, through: smallest.width, by: -4)
      let up = stride(from: smallest.width, through: first.width, by: 4)
      for width in Array(down) + Array(up) {
        lay(window, hosting, at: NSSize(width: width, height: smallest.height))
        showScrollBarsAlways(in: hosting.view)
        hosting.view.layoutSubtreeIfNeeded()
        // The window's display cycle, where the passes run.
        try await settle(15)
      }
      XCTAssertEqual(shell.isInspectorShown, open)
      XCTAssertLessThanOrEqual(widestSplitView(in: window), first.width + 1)
    }
    XCTAssertFalse(window.isVisible, "layout stays offscreen")
    window.contentViewController = nil
    window.close()
  }

  /// A switch with Restore default beside it keeps its line whichever mark its row shows, none,
  /// Modified or Not applied: at every width of the column the row is as tall in all three, so the
  /// first edit, an Apply or a Revert never moves the switch from beside its label to under it.
  func testASwitchStaysOnItsLineWhetherItsRowShowsNoMarkModifiedOrNotApplied() async throws {
    let fixture = try InspectorRenderFixture()
    var inputs = InspectorOptions.Inputs()
    inputs.locale = PanelLocale(language: .english, region: nil)
    func row(dirty: Bool, staged: Bool) throws -> NSHostingController<AnyView> {
      let options = InspectorOptions.make(
        BridgeSnapshotFixtures.options(
          wallpaperId: InspectorRenderFixture.selected,
          properties: [
            BridgePropertyDescriptor(
              id: "clock", kind: .bool, labelHtml: "Show the clock", value: .bool(value: true),
              defaultValue: .bool(value: false), slider: nil, comboOptions: [], fileFilter: nil,
              directoryMode: nil, dirty: dirty, canRestoreDefaults: true, enabled: true,
              assetManaged: false, assetMissing: false, assetSourcePath: nil, staged: staged)
          ]), inputs: inputs)
      let row = try XCTUnwrap(options.properties.first)
      XCTAssertTrue(row.canRestoreDefault, "precondition: Restore default follows the mark")
      return NSHostingController(
        rootView: AnyView(
          PropertyRowView(options: options, row: row)
            .environment(fixture.controller)
            .panelTheme(theme: fixture.controller.theme, locale: PanelLocale.shared)))
    }
    let states = [
      ("no mark", try row(dirty: false, staged: false)), ("Modified", try row(dirty: true, staged: false)),
      ("Not applied", try row(dirty: true, staged: true)),
    ]
    // From a column wide enough for the label to keep one line under any mark (narrower, a wider
    // mark leaves the label less room and it wraps, which is not the switch moving).
    var heights = Set<CGFloat>()
    for width in stride(from: CGFloat(240), through: 420, by: 1) {
      let measured = states.map { ($0.0, $0.1.sizeThatFits(in: CGSize(width: width, height: 2000)).height) }
      heights.formUnion(measured.map(\.1))
      for (name, height) in measured.dropFirst() {
        XCTAssertEqual(height, measured[0].1, accuracy: 0.5, "\(name) at \(width) pt: the switch changed lines")
      }
    }
    XCTAssertGreaterThan(heights.count, 1, "precondition: the sweep crosses the width where the switch moves")
    await fixture.shutdown()
  }

  // MARK: VoiceOver

  /// What a test hears in place of VoiceOver.
  private final class Heard {
    var lines: [String] = []
  }

  /// Every element of the accessibility tree below `root`, as assistive apps walk it.
  private func accessibilityElements(in root: NSView) -> [NSAccessibilityProtocol] {
    var found: [NSAccessibilityProtocol] = []
    func walk(_ element: NSAccessibilityProtocol, depth: Int) {
      found.append(element)
      guard depth < 60 else { return }
      for case let child as NSAccessibilityProtocol in element.accessibilityChildren() ?? [] {
        walk(child, depth: depth + 1)
      }
    }
    walk(root, depth: 0)
    return found
  }

  /// Every element of the accessibility tree below `root`, read by key as `identifiers(in:)` reads
  /// them.
  private func accessibilityObjects(in root: NSView) -> [NSObject] {
    var found: [NSObject] = []
    func walk(_ element: Any?, depth: Int) {
      guard depth < 60, let object = element as? NSObject else { return }
      found.append(object)
      if object.responds(to: NSSelectorFromString("accessibilityChildren")),
        let children = object.value(forKey: "accessibilityChildren") as? [Any]
      {
        for child in children { walk(child, depth: depth + 1) }
      }
    }
    walk(root, depth: 0)
    return found
  }

  /// The accessibility identifiers of the controls drawn below `root`, which say which controls the
  /// inspector really drew. SwiftUI's elements answer the informal protocol, so they are read by key.
  private func identifiers(in root: NSView) -> Set<String> {
    var found = Set<String>()
    func walk(_ element: Any?, depth: Int) {
      guard depth < 60, let object = element as? NSObject else { return }
      if object.responds(to: NSSelectorFromString("accessibilityIdentifier")),
        let identifier = object.value(forKey: "accessibilityIdentifier") as? String, !identifier.isEmpty
      {
        found.insert(identifier)
      }
      if object.responds(to: NSSelectorFromString("accessibilityChildren")),
        let children = object.value(forKey: "accessibilityChildren") as? [Any]
      {
        for child in children { walk(child, depth: depth + 1) }
      }
    }
    walk(root, depth: 0)
    return found
  }

  /// Revert and Apply changes are drawn only while an edit waits, and the footer's sentence is a
  /// status line, as the page's was: the edit that leaves something to apply is said aloud, not only
  /// drawn, once each time it happens.
  func testTheFooterIsDrawnAndSaidAloudOnlyWhileAnEditWaits() async throws {
    let fixture = try InspectorRenderFixture()
    try await prepare(fixture)
    let sentence = "You have unapplied changes."
    let footer: Set<String> = ["inspector.revert", "inspector.applyChanges"]
    let heard = Heard()
    let (window, view) = fixture.host(size: NSSize(width: 360, height: 1400)) {
      InstalledInspector().environment(\.panelAnnouncer, PanelAnnouncer { heard.lines.append($0) })
    }
    try await settle(600)
    view.layoutSubtreeIfNeeded()
    XCTAssertEqual(fixture.controller.inspectorOptions(for: InspectorRenderFixture.selected)?.hasChanges, false)
    XCTAssertTrue(identifiers(in: view).contains("inspector.apply"), "the options and the header are drawn")
    XCTAssertTrue(identifiers(in: view).isDisjoint(with: footer), "nothing to apply yet, so no footer")
    XCTAssertFalse(heard.lines.contains(sentence), "nothing to apply yet")

    fixture.store.wallpaperOptionsSnapshot?.dirty = true
    try await fixture.panel.waitUntil(timeout: 5) {
      view.layoutSubtreeIfNeeded()
      return heard.lines.contains(sentence) && identifiers(in: view).isSuperset(of: footer)
    }
    XCTAssertEqual(heard.lines.filter { $0 == sentence }.count, 1, "said once")

    fixture.store.wallpaperOptionsSnapshot?.dirty = false
    try await fixture.panel.waitUntil(timeout: 5) {
      view.layoutSubtreeIfNeeded()
      return identifiers(in: view).isDisjoint(with: footer)
    }
    XCTAssertEqual(heard.lines.filter { $0 == sentence }.count, 1, "applied or reverted: nothing more is said")

    fixture.store.wallpaperOptionsSnapshot?.dirty = true
    try await fixture.panel.waitUntil(timeout: 5) {
      view.layoutSubtreeIfNeeded()
      return heard.lines.filter { $0 == sentence }.count == 2
    }
    XCTAssertTrue(identifiers(in: view).isSuperset(of: footer), "the next edit brings the footer back")

    // Apply changes and Revert go away with the footer once they have done their work, so that is
    // said too.
    for (button, said) in [("inspector.applyChanges", "Changes applied."), ("inspector.revert", "Changes reverted.")] {
      fixture.store.wallpaperOptionsSnapshot?.dirty = true
      try await fixture.panel.waitUntil(timeout: 5) {
        view.layoutSubtreeIfNeeded()
        return identifiers(in: view).isSuperset(of: footer)
      }
      let press = try XCTUnwrap(
        accessibilityObjects(in: view).first { $0.value(forKey: "accessibilityIdentifier") as? String == button })
      press.perform(NSSelectorFromString("accessibilityPerformPress"))
      try await fixture.panel.waitUntil(timeout: 5) {
        view.layoutSubtreeIfNeeded()
        return heard.lines.contains(said) && identifiers(in: view).isDisjoint(with: footer)
      }
    }
    window.contentView = nil
    await fixture.shutdown()
  }

  /// The footer comes in over the bottom of the inspector. A switch flipped, or text typed, at the
  /// bottom of what is on show is scrolled clear of it, so the footer never lands on the row whose
  /// edit brought it in.
  func testTheFooterNeverCoversTheRowWhoseEditBringsItIn() async throws {
    try await footerStaysClear(of: NSAccessibility.Role.checkBox, "Show the clock") { control, _ in
      control.perform(NSSelectorFromString("accessibilityPerformPress"))
    }
    try await footerStaysClear(of: NSAccessibility.Role.textField, "Caption") { _, root in
      // The first key typed: text not yet sent brings the footer in.
      guard let field = views(NSTextField.self, in: root).first(where: { $0.stringValue == "Good evening" })
      else { return XCTFail("the Caption field") }
      field.stringValue = "Good evening!"
      field.delegate?.controlTextDidChange?(Notification(name: NSControl.textDidChangeNotification, object: field))
    }
  }

  /// Puts the control named `label` at the bottom of the inspector, edits it with `edit`, and
  /// requires that the footer this brings in leaves the control on show above it.
  private func footerStaysClear(
    of role: NSAccessibility.Role, _ label: String, edit: (NSObject, NSView) -> Void
  ) async throws {
    let fixture = try InspectorRenderFixture()
    try await prepare(fixture)
    let (window, view) = fixture.host(size: NSSize(width: 360, height: 3000))
    try await settle(600)
    func element(_ match: (NSObject) -> Bool) -> NSObject? {
      view.layoutSubtreeIfNeeded()
      return accessibilityObjects(in: view).first(where: match)
    }
    func frame(_ object: NSObject?) -> NSRect? {
      (object?.value(forKey: "accessibilityFrame") as? NSValue)?.rectValue
    }
    func isControl(_ object: NSObject) -> Bool {
      object.value(forKey: "accessibilityRole") as? String == role.rawValue
        && object.value(forKey: "accessibilityLabel") as? String == label
    }
    // The window ends just under the control, as when the person has scrolled it to the bottom.
    let viewTop = { window.convertToScreen(view.convert(view.bounds, to: nil)).maxY }
    let height = viewTop() - (try XCTUnwrap(frame(element(isControl)), label)).minY + 12
    window.setContentSize(NSSize(width: 360, height: height))
    view.frame = NSRect(origin: .zero, size: NSSize(width: 360, height: height))
    try await settle(300)
    let before = try XCTUnwrap(frame(element(isControl)), label)
    XCTAssertLessThan(before.minY - (viewTop() - height), 40, "precondition: \(label) is at the bottom")

    edit(try XCTUnwrap(element(isControl), label), view)
    let footer: Set<String> = ["inspector.revert", "inspector.applyChanges"]
    try await fixture.panel.waitUntil(timeout: 5) {
      view.layoutSubtreeIfNeeded()
      return identifiers(in: view).isSuperset(of: footer)
    }
    try await settle(500)
    let after = try XCTUnwrap(frame(element(isControl)), label)
    let footerTop = try XCTUnwrap(
      accessibilityObjects(in: view)
        .filter {
          footer.contains($0.value(forKey: "accessibilityIdentifier") as? String ?? "")
            || ($0.value(forKey: "accessibilityLabel") as? String ?? "").contains("You have unapplied changes.")
            || ($0.value(forKey: "accessibilityValue") as? String ?? "").contains("You have unapplied changes.")
        }
        .compactMap { frame($0)?.maxY }
        .max())
    XCTAssertGreaterThanOrEqual(after.minY, footerTop, "the footer covers \(label), just edited")
    XCTAssertLessThanOrEqual(after.maxY, viewTop(), "\(label) is still on show")
    window.contentView = nil
    await fixture.shutdown()
  }

  /// Beside another display each card starts collapsed. A value staged later in one of them, as the
  /// Black bars card stages a scale factor, opens that card and gives it the Not applied mark; the
  /// other stays collapsed, and applying leaves the open card open.
  func testADisplayCardOpensWhenOneOfItsSettingsIsStagedFromElsewhere() async throws {
    let fixture = try InspectorRenderFixture()
    try await prepare(fixture)
    let (window, view) = fixture.host(size: NSSize(width: 360, height: 3000))
    try await settle(600)
    /// The card's header button: its words (name, summary, mark) and Expanded or Collapsed.
    func header(_ title: String) -> (label: String, value: String)? {
      view.layoutSubtreeIfNeeded()
      return accessibilityObjects(in: view).lazy
        .filter { $0.value(forKey: "accessibilityRole") as? String == NSAccessibility.Role.button.rawValue }
        .compactMap { element -> (String, String)? in
          guard let label = element.value(forKey: "accessibilityLabel") as? String, label.contains(title)
          else { return nil }
          return (label, element.value(forKey: "accessibilityValue") as? String ?? "")
        }
        .first
    }
    let first = "Studio Display (1 - Primary)"
    let second = "LG UltraFine (2 - Secondary)"
    XCTAssertEqual(header(first)?.value, "Collapsed")
    XCTAssertEqual(header(second)?.value, "Collapsed")
    XCTAssertEqual(header(second)?.label.contains("Not applied"), false)

    fixture.store.wallpaperOptionsSnapshot?.dirty = true
    fixture.store.wallpaperOptionsSnapshot?.displayConfigurations[1].staged = true
    try await fixture.panel.waitUntil(timeout: 5) { header(second)?.value == "Expanded" }
    XCTAssertEqual(header(second)?.label.contains("Not applied"), true, "the mark says what waits")
    XCTAssertEqual(header(first)?.value, "Collapsed", "the other card stays as it was")

    fixture.store.wallpaperOptionsSnapshot?.displayConfigurations[1].staged = false
    fixture.store.wallpaperOptionsSnapshot?.dirty = false
    try await fixture.panel.waitUntil(timeout: 5) { header(second)?.label.contains("Not applied") == false }
    XCTAssertEqual(header(second)?.value, "Expanded", "applied: the card the person now sees stays open")
    window.contentView = nil
    await fixture.shutdown()
  }

  /// VoiceOver meets the Position on screen frame as a draggable picture that says where the picture
  /// sits on which display, and its increment moves the picture a step, as an arrow key does.
  func testThePositionFrameIsADraggablePictureToVoiceOver() async throws {
    let fixture = try InspectorRenderFixture()
    try await prepare(fixture)
    let state = ImagePlacementState(
      wallpaperID: "image-a.png", displayID: "primary", displayTitle: "Studio Display",
      isSupported: true, reason: nil, x: 0.5, y: 0.5, zoom: 1, isCustomized: false, fit: .fill,
      imagePixelSize: CGSize(width: 1600, height: 900), imageAspectRatio: 16.0 / 9,
      displayAspectRatio: 16.0 / 10, displayViewportSize: CGSize(width: 1440, height: 900),
      displayPixelSize: CGSize(width: 2880, height: 1800))
    let (window, view) = fixture.host(size: NSSize(width: 320, height: 900)) {
      PlacementCard(state: state, row: LibraryRows.row("image-a.png", kind: .web))
    }
    try await settle(300)
    view.layoutSubtreeIfNeeded()
    let picture = try XCTUnwrap(
      accessibilityElements(in: view).first { $0.accessibilityRoleDescription() == "draggable picture" },
      "the frame calls itself a draggable picture")
    XCTAssertEqual(picture.accessibilityRole(), .image)
    let label = picture.accessibilityLabel() ?? ""
    XCTAssertTrue(label.hasPrefix("Picture position on Studio Display: 50% across, 50% down"), label)

    XCTAssertTrue(picture.accessibilityPerformIncrement())
    XCTAssertEqual(
      fixture.controller.inspector.placement.values(for: state).x, 0.51, accuracy: 0.0001,
      "a step to the right, as the right arrow key moves it")
    window.contentView = nil
    await fixture.shutdown()
  }

  // MARK: The controls reach the controller

  private func slider(
    _ label: String, in view: NSView
  ) throws -> PanelNSSlider {
    try XCTUnwrap(
      views(PanelNSSlider.self, in: view).first { $0.accessibilityLabel() == label },
      "the \(label) slider")
  }

  func testAPropertySliderTheInspectorDrawsSavesVoiceOverKeyAndPointerChanges() async throws {
    let fixture = try InspectorRenderFixture()
    try await prepare(fixture)
    let (window, view) = fixture.host(size: NSSize(width: 360, height: 1400))
    try await settle(600)
    view.layoutSubtreeIfNeeded()
    let count = try slider("Particle count", in: view)
    XCTAssertEqual(count.doubleValue, 120)
    XCTAssertEqual(count.step, 10)

    // VoiceOver: one step saves one edit, with no preview.
    XCTAssertTrue(count.accessibilityPerformIncrement())
    try await fixture.panel.waitUntil(timeout: 5) { fixture.bridge.edits.count == 1 }
    XCTAssertEqual(fixture.bridge.edits.last, .init(propertyId: "count", value: .number(value: 130)))
    XCTAssertTrue(fixture.store.editorState.propertyPreviewValues.isEmpty)
    XCTAssertNil(fixture.controller.errors.message)

    // A key press the same.
    count.keyDown(
      with: NSEvent.keyEvent(
        with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0, windowNumber: 0,
        context: nil, characters: "", charactersIgnoringModifiers: "", isARepeat: false, keyCode: 123)!)
    try await fixture.panel.waitUntil(timeout: 5) { fixture.bridge.edits.count == 2 }
    XCTAssertEqual(fixture.bridge.edits.last, .init(propertyId: "count", value: .number(value: 120)))

    // The pointer drag shows steps, saves nothing until it is released, and then saves the value it
    // settled on and drops the step.
    let key = WallpaperEditorState.FieldKey(wallpaperID: "wp", fieldID: "count")
    count.beginPointer()
    count.doubleValue = 300
    count.valueDidChange(nil)
    try await fixture.panel.waitUntil(timeout: 5) {
      fixture.store.editorState.propertyPreviewValues[key] == .number(value: 300)
    }
    XCTAssertEqual(fixture.bridge.edits.count, 2, "dragging saves nothing")
    count.endPointer()
    try await fixture.panel.waitUntil(timeout: 5) { fixture.bridge.edits.count == 3 }
    XCTAssertEqual(fixture.bridge.edits.last, .init(propertyId: "count", value: .number(value: 300)))
    try await fixture.panel.waitUntil(timeout: 5) {
      fixture.store.editorState.propertyPreviewValues[key] == nil
    }
    XCTAssertNil(fixture.controller.errors.message)
    window.contentView = nil
    await fixture.shutdown()
  }
}
