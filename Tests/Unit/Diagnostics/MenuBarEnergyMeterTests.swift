import XCTest

@testable import WallpaperMachine

/// The menu bar's energy meter: it measures only while the panel is open or the icon carries the
/// figure and someone can see it, at the panel's pace while it is open, and carries its reading
/// across a change of pace. The figure's words are `EnergyReadoutTests`.
@MainActor
final class MenuBarEnergyMeterTests: XCTestCase {
  private let second: UInt64 = 1_000_000_000

  private func sample(at seconds: UInt64, cpuNanojoules: UInt64) -> EnergyUsageSample {
    EnergyUsageSample(
      uptimeNanoseconds: seconds * second,
      own: [1: CoalitionEnergyCounters(cpuEnergyNanojoules: cpuNanojoules, gpuEnergyNanojoules: 0, gpuTimeNanoseconds: 0)],
      otherGPUTime: [:])
  }

  private func meter(showsInMenuBar: Bool = false) -> (MenuBarEnergyMeter, EnergyUsageMonitor) {
    let monitor = EnergyUsageMonitor(source: NoSample())
    let meter = MenuBarEnergyMeter(monitor: monitor, showsInMenuBar: showsInMenuBar)
    addTeardownBlock { @MainActor in meter.stop() }
    return (meter, monitor)
  }

  func testNothingMeasuresUntilThePanelOpensOrTheIconCarriesTheFigure() {
    let (meter, _) = meter()
    XCTAssertFalse(meter.isMeasuring, "off by default, with the panel closed, no timer exists")
    XCTAssertFalse(meter.showsTitle)

    meter.setPanelOpen(true)
    XCTAssertTrue(meter.isMeasuring)
    XCTAssertEqual(meter.interval, MenuBarEnergyMeter.panelInterval, "the panel samples as Settings does")
    meter.setPanelOpen(false)
    XCTAssertFalse(meter.isMeasuring, "closing the panel stops it")

    meter.setShowsInMenuBar(true)
    XCTAssertTrue(meter.showsTitle)
    XCTAssertTrue(meter.isMeasuring)
    XCTAssertEqual(meter.interval, MenuBarEnergyMeter.menuBarInterval, "the icon alone samples less often")
    XCTAssertGreaterThan(MenuBarEnergyMeter.menuBarInterval, MenuBarEnergyMeter.panelInterval)

    meter.setPanelOpen(true)
    XCTAssertEqual(meter.interval, MenuBarEnergyMeter.panelInterval, "an open panel sets the pace")
    meter.setPanelOpen(false)
    XCTAssertEqual(meter.interval, MenuBarEnergyMeter.menuBarInterval)
    XCTAssertTrue(meter.isMeasuring, "the icon keeps its figure after the panel closes")

    meter.setShowsInMenuBar(false)
    XCTAssertFalse(meter.isMeasuring)
  }

  func testTheFigureStopsWhileNobodyIsAtTheMacButAnOpenPanelStillMeasures() {
    let (meter, _) = meter(showsInMenuBar: true)
    var changes = 0
    meter.onChange = { changes += 1 }

    meter.setUnattended(true)
    XCTAssertFalse(meter.showsTitle, "the icon drops the figure it no longer keeps current")
    XCTAssertFalse(meter.isMeasuring, "displays asleep or a locked session wake nothing")
    XCTAssertGreaterThan(changes, 0, "the icon is told")

    meter.setPanelOpen(true)
    XCTAssertTrue(meter.isMeasuring)
    meter.setPanelOpen(false)
    meter.setUnattended(false)
    XCTAssertTrue(meter.showsTitle)
    XCTAssertTrue(meter.isMeasuring)

    meter.stop()
    XCTAssertFalse(meter.isMeasuring, "nothing measures after the app began to quit")
    meter.setPanelOpen(true)
    XCTAssertFalse(meter.isMeasuring)
  }

  func testOpeningThePanelKeepsTheFigureTheIconAlreadyHas() {
    let (meter, monitor) = meter(showsInMenuBar: true)
    var changes = 0
    meter.onChange = { changes += 1 }
    monitor.record(sample(at: 100, cpuNanojoules: 0))
    monitor.record(sample(at: 105, cpuNanojoules: 6_000_000_000))
    XCTAssertEqual(meter.reading.status, .ready)
    XCTAssertEqual(meter.reading.totalMilliwatts, 1_200, accuracy: 0.001)
    XCTAssertGreaterThan(changes, 0, "each reading reaches the icon")

    meter.setPanelOpen(true)
    XCTAssertEqual(meter.reading.status, .ready, "a change of pace does not measure afresh")
    XCTAssertEqual(meter.reading.totalMilliwatts, 1_200, accuracy: 0.001)

    // At the panel's pace the window still runs from the oldest sample it holds.
    monitor.record(sample(at: 107, cpuNanojoules: 6_000_000_000))
    XCTAssertEqual(meter.reading.totalMilliwatts, 6_000.0 / 7, accuracy: 0.001)
  }

  func testTheChoiceIsOffUntilTurnedOnAndTellsTheStatusItem() throws {
    let defaults = try TemporaryDefaults.make(for: self).defaults
    let center = NotificationCenter()
    var posts = 0
    let observer = center.addObserver(
      forName: MenuBarEnergyPreference.didChangeNotification, object: nil, queue: nil
    ) { _ in posts += 1 }
    defer { center.removeObserver(observer) }

    XCTAssertFalse(MenuBarEnergyPreference.isOn(in: defaults))
    MenuBarEnergyPreference.save(true, in: defaults, center: center)
    XCTAssertTrue(MenuBarEnergyPreference.isOn(in: defaults))
    MenuBarEnergyPreference.save(false, in: defaults, center: center)
    XCTAssertFalse(MenuBarEnergyPreference.isOn(in: defaults))
    XCTAssertNil(defaults.object(forKey: MenuBarEnergyPreference.defaultsKey), "the default is saved as no value")
    XCTAssertEqual(posts, 2)
  }
}

/// A source the meter's own loop can call without adding readings to the ones a test records.
private struct NoSample: EnergyUsageSource {
  func sample() -> EnergyUsageSample? {
    EnergyUsageSample(uptimeNanoseconds: 0, own: [:], otherGPUTime: [:])
  }
}
