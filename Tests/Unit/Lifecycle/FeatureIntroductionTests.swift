import XCTest

@testable import WallpaperMachine

/// A feature introduction opens once, for people who update from a version without the feature,
/// however many versions they skip; never on a fresh install and never after a later update.
@MainActor
final class FeatureIntroductionTests: XCTestCase {
    private let widgets = FeatureIntroduction(id: "widgets", lastVersionWithout: SemanticVersion("1.10.0")!)
    private var defaults: UserDefaults!

    override func setUpWithError() throws {
        defaults = try TemporaryDefaults.make(for: self).defaults
    }

    private func launch(_ version: String) -> FeatureIntroductionStore {
        FeatureIntroductionStore(defaults: defaults, currentVersion: version, introductions: [widgets])
    }

    /// Runs a launch of `version` that presents whatever is due, as the app does.
    @discardableResult
    private func run(_ version: String, existingUser: Bool = true) -> FeatureIntroduction? {
        let store = launch(version)
        let due = store.due(existingUser: existingUser)
        if let due { store.didPresent(due) }
        return due
    }

    func testAnUpdateFromABuildThatRecordedNoVersionShowsItOnce() {
        XCTAssertEqual(run("1.11.0"), widgets, "an existing user from 1.10 or older")
        XCTAssertNil(run("1.11.0"), "a relaunch")
        XCTAssertNil(run("1.12.0"), "the next update")
    }

    func testAFreshInstallNeverShowsIt() {
        XCTAssertNil(run("1.11.0", existingUser: false))
        XCTAssertNil(run("1.12.0"), "a later update: the fresh install recorded its version")
    }

    func testAnUpdateThatSkipsVersionsStillShowsIt() {
        XCTAssertNil(run("1.10.0"), "a version without the feature introduces nothing")
        XCTAssertEqual(run("2.3.0"), widgets, "updating from 1.10.0 straight to a much newer one")
        XCTAssertNil(run("2.4.0"))
    }

    func testAnUpdateFromAVersionThatHadTheFeatureDoesNotShowIt() {
        defaults.set("1.11.2", forKey: FeatureIntroductionStore.lastLaunchedVersionKey)
        XCTAssertNil(run("1.12.0"))
    }

    func testALaunchThatEndsBeforeTheWindowShowsOffersItAgain() {
        XCTAssertEqual(launch("1.11.0").due(existingUser: true), widgets)
        XCTAssertNil(defaults.string(forKey: FeatureIntroductionStore.lastLaunchedVersionKey))
        XCTAssertEqual(run("1.11.0"), widgets)
    }

    func testGoingBackToAnOlderVersionKeepsTheNewestLaunched() {
        run("1.12.0", existingUser: false)
        run("1.11.0")
        XCTAssertEqual(defaults.string(forKey: FeatureIntroductionStore.lastLaunchedVersionKey), "1.12.0")
    }

    func testAnUnreadableVersionShowsNothingAndRecordsNothing() {
        XCTAssertNil(run("dev"))
        XCTAssertNil(defaults.string(forKey: FeatureIntroductionStore.lastLaunchedVersionKey))
    }

    func testDesktopWidgetsAreIntroducedToUpdatesFrom1_10() {
        let store = FeatureIntroductionStore(defaults: defaults, currentVersion: "1.11.0")
        XCTAssertEqual(store.due(existingUser: true), .desktopWidgets)
    }
}
