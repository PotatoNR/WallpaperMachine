import AppKit
import Observation

/// Whether the panel can be seen, and whether it has the keyboard.
///
/// Work whose result nobody would see is gated on `isVisible`: the per-display options fetch, the
/// energy sampler, the support prompt's offer, and anything that rebuilds a derived cache. A
/// window that is closed releases the whole controller; a hidden one (ordered out, minimized, or
/// entirely covered) only stops doing model work, and resumes the moment it is shown.
///
/// A real window drives it through `attach(to:)` and the notifications below. Tests never attach
/// one: they call `show()`, `hide()` and `becomeKey()`, which is also how a panel is injected as
/// visible without ordering a window front.
@MainActor
@Observable
final class PanelPresentation {
  /// The window is on screen: visible, not minimized and not occluded.
  private(set) var isVisible: Bool
  /// When the window was last shown: opened, ordered in again after it was hidden, brought back
  /// from the Dock, or its app unhidden; nil while it is not shown. Being covered and uncovered,
  /// leaving its Space and coming back, or a screen lock keep it: the window was open all along.
  /// The support offer waits for a window shown a day after the apply that earned it, so one
  /// already open across that mark does not interrupt.
  private(set) var shownSince: Date?
  /// The window is ordered in, not minimized, and its app is not hidden, whether or not anything
  /// covers it.
  private var isShown: Bool
  /// The window is the key window.
  private(set) var isKey: Bool
  /// The window sheets and pickers attach to; nil without one.
  private(set) weak var window: NSWindow?

  /// Runs each time the window becomes key (including `becomeKey()`): scene assets and a Login
  /// Items approval are read again because they change while the user is elsewhere.
  @ObservationIgnored var onBecameKey: (@MainActor () -> Void)?
  /// Runs when the window closes or the view loses it for good.
  @ObservationIgnored var onClose: (@MainActor () -> Void)?

  @ObservationIgnored private var observers: [NSObjectProtocol] = []
  /// Whether the app is hidden, as **Hide window after applying a wallpaper** leaves it; a test
  /// passes its own, since the app that hosts the tests runs hidden.
  @ObservationIgnored private let appIsHidden: @MainActor () -> Bool

  init(
    isVisible: Bool = false, isKey: Bool = false,
    appIsHidden: @escaping @MainActor () -> Bool = { NSApp.isHidden }
  ) {
    self.isVisible = isVisible
    self.isKey = isKey
    self.appIsHidden = appIsHidden
    isShown = isVisible
    shownSince = isVisible ? Date() : nil
  }

  deinit { for observer in observers { NotificationCenter.default.removeObserver(observer) } }

  // MARK: Injection (tests, and previews without a window)

  /// `date` is when it was shown, for a test that needs a window shown earlier.
  func show(at date: Date = Date()) { setVisible(true, shown: true, at: date) }
  func hide() { setVisible(false, shown: false) }

  func becomeKey() {
    isKey = true
    onBecameKey?()
  }

  func resignKey() { isKey = false }

  // MARK: A real window

  /// Follows `window`. Attaching nil, or another window, ends the previous one's tracking; losing
  /// a window that was attached means the view was dismantled, which `onClose` hears.
  func attach(to window: NSWindow?) {
    guard window !== self.window else { return }
    let hadWindow = self.window != nil
    removeObservers()
    self.window = window
    guard let window else {
      setVisible(false, shown: false)
      isKey = false
      if hadWindow { onClose?() }
      return
    }
    for name in [
      NSWindow.didChangeOcclusionStateNotification, NSWindow.didMiniaturizeNotification,
      NSWindow.didDeminiaturizeNotification, NSWindow.didEnterFullScreenNotification,
      NSWindow.didExitFullScreenNotification, NSWindow.didResignKeyNotification,
    ] {
      observe(name, window) { $0.windowChanged() }
    }
    // Hiding the app (Hide window after applying a wallpaper does) and unhiding it.
    for name in [NSApplication.didHideNotification, NSApplication.didUnhideNotification] {
      observe(name, NSApp) { $0.windowChanged() }
    }
    observe(NSWindow.didBecomeKeyNotification, window) {
      $0.windowChanged()
      $0.onBecameKey?()
    }
    observe(NSWindow.willCloseNotification, window) { $0.windowClosed() }
    windowChanged()
  }

  /// AppKit posts window notifications on the main thread, so the handler runs before the post
  /// returns; one that arrives anywhere else hops.
  private func observe(
    _ name: Notification.Name, _ object: AnyObject,
    _ handler: @escaping @MainActor (PanelPresentation) -> Void
  ) {
    observers.append(
      NotificationCenter.default.addObserver(forName: name, object: object, queue: nil) {
        [weak self] _ in
        if Thread.isMainThread {
          MainActor.assumeIsolated { if let self { handler(self) } }
        } else {
          Task { @MainActor [weak self] in if let self { handler(self) } }
        }
      })
  }

  private func windowChanged() {
    guard let window else { return }
    let shown = window.isVisible && !window.isMiniaturized && !appIsHidden()
    setVisible(shown && window.occlusionState.contains(.visible), shown: shown)
    isKey = window.isKeyWindow
  }

  private func windowClosed() {
    setVisible(false, shown: false)
    isKey = false
    removeObservers()
    window = nil
    onClose?()
  }

  /// The time it was shown changes only when it is shown: being uncovered, a key change or another
  /// notification of a window already shown keeps it.
  private func setVisible(_ visible: Bool, shown: Bool, at date: Date = Date()) {
    if shown != isShown { shownSince = shown ? date : nil }
    isShown = shown
    isVisible = visible
  }

  private func removeObservers() {
    for observer in observers { NotificationCenter.default.removeObserver(observer) }
    observers.removeAll()
  }
}
