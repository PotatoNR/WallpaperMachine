import AppKit
import SwiftUI
import XCTest

@testable import WallpaperMachine

/// The desktop widgets introduction, drawn in a window that is never shown: its words fit the
/// window in every language.
@MainActor
final class FeatureIntroWindowTests: XCTestCase {
  private static let languages = ["en", "zh-Hans", "zh-Hant", "ja", "ko", "pt-BR"]

  private func host(language: String, dark: Bool, actions: FeatureIntroWindow.Actions = .init(open: {}, close: {}))
    -> (NSWindow, NSHostingController<AnyView>)
  {
    let root = DesktopWidgetsIntroView(actions: actions)
      .environment(\.panelTheme, PanelTheme(appearance: dark ? .dark : .light))
      .environment(\.locale, Locale(identifier: language))
      .environment(\.colorScheme, dark ? .dark : .light)
    let hosting = NSHostingController(rootView: AnyView(root))
    hosting.sizingOptions = []
    let window = NSWindow(
      contentRect: NSRect(origin: .zero, size: FeatureIntroWindow.contentSize),
      styleMask: [.titled, .closable, .fullSizeContentView], backing: .buffered, defer: false)
    window.isReleasedWhenClosed = false
    window.titlebarAppearsTransparent = true
    window.contentViewController = hosting
    window.setContentSize(FeatureIntroWindow.contentSize)
    hosting.view.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
    window.layoutIfNeeded()
    return (window, hosting)
  }

  func testTheWindowOpensAtItsSize() {
    let window = FeatureIntroWindow.make(actions: .init(open: {}, close: {}))
    XCTAssertEqual(window.contentLayoutRect.size.width, FeatureIntroWindow.contentSize.width, accuracy: 1)
    XCTAssertFalse(window.styleMask.contains(.resizable))
    window.contentViewController = nil
    window.close()
  }

  func testTheWordsFitTheWindowInEveryLanguage() {
    for language in Self.languages {
      let (window, hosting) = host(language: language, dark: false)
      // The least height the content can take: every line it wraps into, and the footer. The
      // picture runs under the title bar, which the measurement counts once more.
      let needed = hosting.sizeThatFits(in: NSSize(width: FeatureIntroWindow.contentSize.width, height: 0))
      let titleBar = FeatureIntroWindow.contentSize.height - window.contentLayoutRect.height
      XCTAssertGreaterThan(titleBar, 0)
      XCTAssertLessThanOrEqual(needed.height - titleBar, FeatureIntroWindow.contentSize.height, "\(language) fits")
      window.contentViewController = nil
      window.close()
    }
  }

  /// With `WALLPAPER_MACHINE_FEATURE_INTRO_SNAPSHOTS` set to a folder, writes the window in each
  /// language and appearance there for a person to look at.
  func testSnapshotsOnRequest() async throws {
    guard let folder = ProcessInfo.processInfo.environment["WALLPAPER_MACHINE_FEATURE_INTRO_SNAPSHOTS"]
    else { throw XCTSkip("set WALLPAPER_MACHINE_FEATURE_INTRO_SNAPSHOTS to write snapshots") }
    let url = URL(fileURLWithPath: folder, isDirectory: true)
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    let looks = Self.languages.map { ($0, false) } + [("en", true), ("zh-Hans", true)]
    for (language, dark) in looks {
      let (window, hosting) = host(language: language, dark: dark)
      try await Task.sleep(for: .milliseconds(200))
      window.layoutIfNeeded()
      let view = hosting.view
      let rep = try XCTUnwrap(view.bitmapImageRepForCachingDisplay(in: view.bounds))
      view.cacheDisplay(in: view.bounds, to: rep)
      let png = try XCTUnwrap(rep.representation(using: .png, properties: [:]))
      try png.write(to: url.appendingPathComponent("feature-intro-\(language)-\(dark ? "dark" : "light").png"))
      window.contentViewController = nil
      window.close()
    }
  }
}
