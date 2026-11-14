import AppKit
import QuartzCore
import SwiftUI
import XCTest

@testable import WallpaperMachine

/// Exercises the real settings pages without showing a window or changing system settings.
@MainActor
final class SettingsSearchRenderingTests: PanelTestCase {
  override func tearDown() async throws {
    restoreSharedPanelLanguage()
    try await super.tearDown()
  }

  private func host(_ controller: PanelController) -> (NSWindow, NSHostingController<AnyView>) {
    let hosting = NSHostingController(rootView: AnyView(
      SettingsPages().environment(controller)
        .panelTheme(theme: controller.theme, locale: PanelLocale.shared)))
    hosting.sizingOptions = []
    let window = ControlPanelWindow.make(contentViewController: hosting, delegate: nil)
    window.setContentSize(NSSize(width: 760, height: 560))
    return (window, hosting)
  }

  private func settle(_ window: NSWindow, _ hosting: NSHostingController<AnyView>) async throws {
    window.layoutIfNeeded()
    hosting.view.layoutSubtreeIfNeeded()
    try await Task.sleep(for: .milliseconds(30))
    window.layoutIfNeeded()
    hosting.view.layoutSubtreeIfNeeded()
  }

  func testRefiningSearchDoesNotRepeatSystemReadings() async throws {
    try pinPanelLanguageToEnglish()
    try await withRecordingPanel { panel, _ in
      panel.store.snapshotRevision = 1
      let controller = panel.controller
      let settings = controller.settings
      settings.query = "wallp"
      let (window, hosting) = host(controller)
      defer { window.contentViewController = nil; window.close() }
      try await settle(window, hosting)
      try await settle(window, hosting)
      let sections = settings.search.sections
      let readings = controller.systemReadingsRevision
      var samples: [String] = []
      for query in ["wallpa", "wallpap", "wallpape", "wallpaper", "wallpape", "wallpap", "wallpa", "wallp"] {
        let start = CACurrentMediaTime()
        settings.query = query
        let searchStart = CACurrentMediaTime()
        XCTAssertEqual(settings.search.sections, sections)
        let searchMS = (CACurrentMediaTime() - searchStart) * 1_000
        try await settle(window, hosting)
        samples.append(String(format: "%@ model=%.2fms update=%.2fms", query, searchMS,
                              (CACurrentMediaTime() - start) * 1_000))
      }
      print("SETTINGS_SEARCH_TIMINGS (includes 30ms settling per update):\n" + samples.joined(separator: "\n"))
      XCTAssertEqual(controller.systemReadingsRevision, readings,
                     "Refining the same results must not re-read system preferences and battery state")
      XCTAssertFalse(window.isVisible)
    }
  }

  func testQueryChangesAndSectionRevealsReturnToTop() async throws {
    try pinPanelLanguageToEnglish()
    try await withRecordingPanel { panel, _ in
      panel.store.snapshotRevision = 1
      let settings = panel.controller.settings
      settings.query = "wallp"
      let (window, hosting) = host(panel.controller)
      defer { window.contentViewController = nil; window.close() }
      try await settle(window, hosting)
      for query in ["wallpa", "wallp", ""] {
        let scroll = try XCTUnwrap(Self.scrollView(in: hosting.view))
        scroll.contentView.scroll(to: NSPoint(x: 0, y: 200))
        scroll.reflectScrolledClipView(scroll.contentView)
        try await settle(window, hosting)
        XCTAssertGreaterThan(scroll.contentView.bounds.minY, 100)
        settings.query = query
        try await settle(window, hosting)
        let updated = try XCTUnwrap(Self.scrollView(in: hosting.view))
        XCTAssertEqual(updated.contentView.bounds.minY + updated.contentInsets.top, 0, accuracy: 1,
                       "Changing the query to '\(query)' must return to the top")
      }
      settings.select(.playback)
      try await settle(window, hosting)
      let scroll = try XCTUnwrap(Self.scrollView(in: hosting.view))
      scroll.contentView.scroll(to: NSPoint(x: 0, y: 200))
      scroll.reflectScrolledClipView(scroll.contentView)
      try await settle(window, hosting)
      settings.select(.playback)
      try await settle(window, hosting)
      let updated = try XCTUnwrap(Self.scrollView(in: hosting.view))
      XCTAssertEqual(updated.contentView.bounds.minY + updated.contentInsets.top, 0, accuracy: 1)

      // The widget workspace replaces the scrolling page. Returning to search
      // must start at the top even if the previous search was scrolled down.
      for _ in 0..<2 {
        settings.select(.widgets)
        try await settle(window, hosting)
        settings.query = "wallp"
        try await settle(window, hosting)
        let results = try XCTUnwrap(Self.scrollView(in: hosting.view))
        XCTAssertEqual(results.contentView.bounds.minY + results.contentInsets.top, 0, accuracy: 1)
        results.contentView.scroll(to: NSPoint(x: 0, y: 200))
        results.reflectScrolledClipView(results.contentView)
        try await settle(window, hosting)
      }
      XCTAssertFalse(window.isVisible)
    }
  }

  func testEnteringAndClearingBroadSearchPreservesDisclosureChoices() async throws {
    try pinPanelLanguageToEnglish()
    try await withRecordingPanel { panel, _ in
      panel.store.snapshotRevision = 1
      let settings = panel.controller.settings
      settings.select(.performance)
      settings.setOpen(true, for: PerformanceSettingsSection.advanced)
      let (window, hosting) = host(panel.controller)
      defer { window.contentViewController = nil; window.close() }
      try await settle(window, hosting)
      for query in ["a", "", "s", "", "wallpaper", ""] {
        let start = CACurrentMediaTime()
        settings.query = query
        try await settle(window, hosting)
        print(String(format: "SETTINGS_SEARCH_ENTRY query=%@ update=%.2fms", query,
                     (CACurrentMediaTime() - start) * 1_000))
        XCTAssertEqual(settings.search.query, query)
        if query.isEmpty {
          XCTAssertEqual(settings.selectedSection, .performance)
          XCTAssertTrue(settings.isOpen(PerformanceSettingsSection.advanced))
        } else {
          XCTAssertFalse(settings.search.hasNoResults)
        }
      }
      XCTAssertFalse(window.isVisible)
    }
  }

  func testTheLastMatchingSectionCanBeReachedByScrolling() async throws {
    try pinPanelLanguageToEnglish()
    try await withRecordingPanel { panel, _ in
      panel.store.snapshotRevision = 1
      let settings = panel.controller.settings
      settings.query = "a"
      XCTAssertEqual(settings.search.sections.last, .about)
      XCTAssertTrue(settings.search.shows(AboutSettingsSection.shareApp))
      let (window, hosting) = host(panel.controller)
      defer { window.contentViewController = nil; window.close() }
      try await settle(window, hosting)
      var reached = false
      // A lazy list refines its estimated height as its later sections load.
      for _ in 0..<12 {
        let scroll = try XCTUnwrap(Self.scrollView(in: hosting.view))
        let document = try XCTUnwrap(scroll.documentView)
        let bottom = max(0, document.frame.height - scroll.contentView.bounds.height)
        scroll.contentView.scroll(to: NSPoint(x: 0, y: bottom))
        scroll.reflectScrolledClipView(scroll.contentView)
        try await settle(window, hosting)
        reached = AccessibilityElement.everything(in: hosting.view).contains {
          $0.identifier == AboutSettingsSection.shareApp.id || $0.text == "Star on GitHub"
        }
        if reached { break }
      }
      XCTAssertTrue(reached, "The last matching section remains available in the scrolling results")
      XCTAssertFalse(window.isVisible)
    }
  }

  private static func scrollView(in view: NSView) -> NSScrollView? {
    if let scroll = view as? NSScrollView { return scroll }
    return view.subviews.lazy.compactMap { scrollView(in: $0) }.first
  }
}
