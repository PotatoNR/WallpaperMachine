import SwiftUI
import XCTest
@testable import WallpaperMachine

/// The panel's bar (`ProgressBar`): without an amount it is the panel's own, which stops in a
/// hidden window and with Reduce Motion, never the system's indeterminate bar, which slides on.
/// It stands at the system bar's height, so a bar that learns its amount moves nothing under it.
@MainActor
final class ProgressBarRenderTests: XCTestCase {
  private var windows: [NSWindow] = []

  override func setUp() async throws {
    try await super.setUp()
    // SwiftUI builds no accessibility elements for hosted content until a client has asked the app
    // something, and the first check reads that tree.
    await AccessibilityClient.connect()
  }

  override func tearDown() async throws {
    for window in windows {
      window.contentView = nil
      window.close()
    }
    windows.removeAll()
    try await super.tearDown()
  }

  private func host(_ view: some View, controlSize: ControlSize) -> NSView {
    let hosting = NSHostingView(
      rootView: AnyView(view.controlSize(controlSize).frame(width: 240).environment(\.panelIsVisible, true)))
    hosting.sceneBridgingOptions = []
    let window = NSWindow(
      contentRect: NSRect(x: 0, y: 0, width: 240, height: 80), styleMask: [.titled],
      backing: .buffered, defer: false)
    window.isReleasedWhenClosed = false
    window.contentView = hosting
    windows.append(window)
    hosting.layoutSubtreeIfNeeded()
    return hosting
  }

  func testABarWithoutAnAmountIsThePanelsOwnAtTheSystemBarsHeight() async throws {
    for size in [ControlSize.regular, .small] {
      let unknown = host(
        ProgressBar(value: nil).accessibilityLabel(Text(verbatim: "Copying the library")),
        controlSize: size)
      let known = host(ProgressBar(value: 0.4), controlSize: size)
      try await Task.sleep(for: .milliseconds(200))
      unknown.layoutSubtreeIfNeeded()
      known.layoutSubtreeIfNeeded()
      XCTAssertTrue(
        AccessibilityElement.everything(in: unknown).contains { $0.text == "Copying the library" },
        "\(size): the label of the place that holds it reaches VoiceOver, so an empty tree cannot pass")
      XCTAssertEqual(AccessibilityElement.systemProgressIndicators(in: unknown), [], "\(size)")
      XCTAssertFalse(
        AccessibilityElement.systemProgressIndicators(in: known).isEmpty,
        "\(size): with an amount it is the system's bar, which the check finds")
      XCTAssertEqual(
        unknown.fittingSize.height, known.fittingSize.height, accuracy: 0.5,
        "\(size): learning the amount moves nothing under the bar")
    }
  }
}
