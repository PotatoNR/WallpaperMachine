import AppKit
import XCTest

@testable import WallpaperMachine

/// Whether the panel can be seen and has the keyboard, which gates every piece of work nobody
/// would see the result of.
@MainActor
final class PanelPresentationTests: XCTestCase {
  /// A titled window that is never ordered onto the screen.
  private func unorderedWindow() -> NSWindow {
    let window = NSWindow(
      contentRect: NSRect(x: 0, y: 0, width: 100, height: 100),
      styleMask: [.titled, .closable], backing: .buffered, defer: true)
    window.isReleasedWhenClosed = false
    return window
  }

  /// A window that says it is ordered in, minimized or covered, and whether its app is hidden, as
  /// the test sets it, without ever being ordered onto the screen; the test posts the notification
  /// AppKit would.
  private final class StagedWindow: NSWindow {
    var appHidden = false
    var ordered = true
    var minimized = false
    var occlusion: NSWindow.OcclusionState = .visible
    override var isVisible: Bool { ordered }
    override var isMiniaturized: Bool { minimized }
    override var occlusionState: NSWindow.OcclusionState { occlusion }
  }

  func testInjectionDrivesVisibilityAndTheKeyHook() {
    let presentation = PanelPresentation()
    XCTAssertFalse(presentation.isVisible, "a panel with no window is not on screen")
    XCTAssertFalse(presentation.isKey)
    var keyed = 0
    presentation.onBecameKey = { keyed += 1 }

    XCTAssertNil(presentation.shownSince)
    presentation.show()
    XCTAssertTrue(presentation.isVisible)
    XCTAssertNotNil(presentation.shownSince)
    presentation.becomeKey()
    XCTAssertTrue(presentation.isKey)
    XCTAssertEqual(keyed, 1)
    presentation.resignKey()
    XCTAssertFalse(presentation.isKey)
    presentation.hide()
    XCTAssertFalse(presentation.isVisible)
    XCTAssertNil(presentation.shownSince)
    XCTAssertEqual(keyed, 1, "only becoming key runs the hook")
  }

  /// Being covered and uncovered (by another window, another Space or a screen lock) hides the
  /// panel but keeps when its window was shown: the window was open all along, so the support
  /// offer, which waits for a window shown after its mark, does not come up then. Ordering the
  /// window out, minimizing it or hiding the app, and showing it again, is showing it again.
  func testCoveringKeepsWhenTheWindowWasShownAndOrderingOutOrMinimizingResetsIt() throws {
    let window = StagedWindow(
      contentRect: NSRect(x: 0, y: 0, width: 100, height: 100),
      styleMask: [.titled, .closable], backing: .buffered, defer: true)
    window.isReleasedWhenClosed = false
    let presentation = PanelPresentation(appIsHidden: { window.appHidden })
    defer {
      presentation.attach(to: nil)
      window.ordered = false
    }
    func post(_ name: Notification.Name) { NotificationCenter.default.post(name: name, object: window) }

    presentation.attach(to: window)
    XCTAssertTrue(presentation.isVisible)
    let shown = try XCTUnwrap(presentation.shownSince, "an attached window on screen was shown")

    window.occlusion = []
    post(NSWindow.didChangeOcclusionStateNotification)
    XCTAssertFalse(presentation.isVisible, "a covered window cannot be seen")
    XCTAssertEqual(presentation.shownSince, shown, "but it is still open")
    window.occlusion = .visible
    post(NSWindow.didChangeOcclusionStateNotification)
    XCTAssertTrue(presentation.isVisible)
    XCTAssertEqual(presentation.shownSince, shown, "uncovering it is not showing it again")

    window.ordered = false
    post(NSWindow.didChangeOcclusionStateNotification)
    XCTAssertFalse(presentation.isVisible)
    XCTAssertNil(presentation.shownSince, "an ordered-out window is not shown")
    window.ordered = true
    post(NSWindow.didChangeOcclusionStateNotification)
    XCTAssertTrue(presentation.isVisible)
    XCTAssertNotNil(presentation.shownSince, "ordered in again, it is shown again")

    window.minimized = true
    post(NSWindow.didMiniaturizeNotification)
    XCTAssertFalse(presentation.isVisible)
    XCTAssertNil(presentation.shownSince, "a minimized window is not shown")
    window.minimized = false
    post(NSWindow.didDeminiaturizeNotification)
    XCTAssertTrue(presentation.isVisible)
    XCTAssertNotNil(presentation.shownSince, "brought back from the Dock, it is shown again")

    // AppKit posts the window's occlusion change when the app hides and unhides, as well as the
    // app's own notifications, which the test leaves alone: the app hosting it listens to them.
    window.appHidden = true
    post(NSWindow.didChangeOcclusionStateNotification)
    XCTAssertFalse(presentation.isVisible)
    XCTAssertNil(presentation.shownSince, "a hidden app's window is not shown")
    window.appHidden = false
    post(NSWindow.didChangeOcclusionStateNotification)
    XCTAssertTrue(presentation.isVisible)
    XCTAssertNotNil(presentation.shownSince, "unhidden, it is shown again")
  }

  func testAWindowThatIsNotOnScreenIsNotVisible() {
    let presentation = PanelPresentation(isVisible: true)
    let window = unorderedWindow()
    presentation.attach(to: window)
    XCTAssertTrue(presentation.window === window)
    XCTAssertFalse(presentation.isVisible, "an unordered window cannot be seen, whatever it was told before")
    XCTAssertFalse(presentation.isKey)
    presentation.attach(to: nil)
  }

  func testTheWindowsNotificationsDriveTheKeyHookAndTheCloseHook() {
    let presentation = PanelPresentation()
    var keyed = 0
    var closed = 0
    presentation.onBecameKey = { keyed += 1 }
    presentation.onClose = { closed += 1 }
    let window = unorderedWindow()
    presentation.attach(to: window)

    NotificationCenter.default.post(name: NSWindow.didBecomeKeyNotification, object: window)
    XCTAssertEqual(keyed, 1)
    NotificationCenter.default.post(name: NSWindow.didBecomeKeyNotification, object: unorderedWindow())
    XCTAssertEqual(keyed, 1, "another window's notifications are not ours")

    NotificationCenter.default.post(name: NSWindow.willCloseNotification, object: window)
    XCTAssertEqual(closed, 1)
    XCTAssertNil(presentation.window)
    XCTAssertFalse(presentation.isVisible)
    NotificationCenter.default.post(name: NSWindow.didBecomeKeyNotification, object: window)
    XCTAssertEqual(keyed, 1, "a closed window is no longer followed")
    presentation.attach(to: nil)
    XCTAssertEqual(closed, 1, "losing a window that already closed does not close twice")
  }

  func testTheViewLosingItsWindowCountsAsClosing() {
    let presentation = PanelPresentation()
    var closed = 0
    presentation.onClose = { closed += 1 }
    presentation.attach(to: nil)
    XCTAssertEqual(closed, 0, "nothing was attached")
    presentation.attach(to: unorderedWindow())
    presentation.attach(to: nil)
    XCTAssertEqual(closed, 1)
  }

  func testSwitchingWindowsStopsListeningToTheOldOne() {
    let presentation = PanelPresentation()
    var keyed = 0
    presentation.onBecameKey = { keyed += 1 }
    let first = unorderedWindow()
    let second = unorderedWindow()
    presentation.attach(to: first)
    presentation.attach(to: second)
    NotificationCenter.default.post(name: NSWindow.didBecomeKeyNotification, object: first)
    XCTAssertEqual(keyed, 0)
    NotificationCenter.default.post(name: NSWindow.didBecomeKeyNotification, object: second)
    XCTAssertEqual(keyed, 1)
    presentation.attach(to: nil)
  }
}
