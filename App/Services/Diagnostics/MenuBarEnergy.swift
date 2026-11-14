import Foundation
import Observation

/// Settings › General › Show energy use in the menu bar: whether the menu bar icon carries what this
/// app draws now. Off until turned on, since keeping the figure current means sampling all the
/// time; the menu bar panel shows it either way while it is open. `didChangeNotification` tells the
/// status item to follow at once.
enum MenuBarEnergyPreference {
  static let defaultsKey = "WallpaperMachine.menuBarEnergy"
  static let didChangeNotification = Notification.Name("WallpaperMachine.menuBarEnergyDidChange")

  static func isOn(in defaults: UserDefaults = ClientPreferences.defaults) -> Bool {
    defaults.object(forKey: defaultsKey) as? Bool ?? false
  }

  /// Saves the choice, the default as no value at all, and tells the status item.
  static func save(_ on: Bool, in defaults: UserDefaults, center: NotificationCenter = .default) {
    if on {
      defaults.set(true, forKey: defaultsKey)
    } else {
      defaults.removeObject(forKey: defaultsKey)
    }
    center.post(name: didChangeNotification, object: nil)
  }
}

/// What this app draws now, for the menu bar: the figure beside the icon when Settings asks for
/// it, and the Energy use row of the menu bar panel while that is open. One `EnergyUsageMonitor`
/// serves both, so opening the panel with the figure on shows a reading at once.
///
/// It samples only while someone can see the result: every two seconds while the panel is open,
/// as Settings' readout does, and every `menuBarInterval` for the icon alone, which stops while
/// nobody is at the Mac (displays asleep, session locked). Otherwise no timer exists. A sample is
/// about 3 ms of kernel calls, so the icon alone costs about 0.06 % of a core.
@MainActor
@Observable
final class MenuBarEnergyMeter {
  static let panelInterval = EnergyUsageMonitor.defaultInterval
  static let menuBarInterval: Duration = .seconds(5)

  /// The monitor's latest reading. Stale while not measuring; `isMeasuring` says which.
  private(set) var reading = EnergyUsageReading.measuring
  /// The battery's full charge in watt-hours, nil on a Mac without one.
  private(set) var batteryCapacity: Double?
  /// The Settings choice: the icon carries the figure.
  private(set) var showsInMenuBar: Bool
  /// Nobody is at the Mac, so the icon's figure is not kept current.
  private(set) var isUnattended = false
  private(set) var isPanelOpen = false
  /// Set by `stop()`, after which nothing measures again.
  private(set) var isStopped = false

  /// Called whenever what the icon shows may have changed: a reading, the choice, attendance.
  @ObservationIgnored var onChange: (@MainActor () -> Void)?
  @ObservationIgnored private let monitor: EnergyUsageMonitor

  init(monitor: EnergyUsageMonitor, showsInMenuBar: Bool) {
    self.monitor = monitor
    self.showsInMenuBar = showsInMenuBar
    monitor.onChange = { [weak self] in self?.monitorChanged() }
    update()
  }

  /// Whether the icon carries the figure now.
  var showsTitle: Bool { showsInMenuBar && !isUnattended }
  var isMeasuring: Bool { monitor.isActive }
  var interval: Duration { monitor.interval }

  func setShowsInMenuBar(_ shows: Bool) {
    guard shows != showsInMenuBar else { return }
    showsInMenuBar = shows
    update()
  }

  func setUnattended(_ unattended: Bool) {
    guard unattended != isUnattended else { return }
    isUnattended = unattended
    update()
  }

  /// The menu bar panel opened or closed.
  func setPanelOpen(_ open: Bool) {
    guard open != isPanelOpen else { return }
    isPanelOpen = open
    update()
  }

  /// The app is quitting: no more samples, whatever asks.
  func stop() {
    isStopped = true
    update()
  }

  /// The interval goes first, so a loop that starts now starts at the right pace.
  private func update() {
    let wanted = !isStopped && (isPanelOpen || showsTitle)
    monitor.setInterval(isPanelOpen ? Self.panelInterval : Self.menuBarInterval)
    monitor.setActive(wanted)
    monitorChanged()
  }

  private func monitorChanged() {
    if reading != monitor.reading { reading = monitor.reading }
    if batteryCapacity != monitor.batteryCapacity { batteryCapacity = monitor.batteryCapacity }
    onChange?()
  }
}
