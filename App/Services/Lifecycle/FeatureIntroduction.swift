import Foundation

/// A feature the app introduces once, in a window of its own, to people who update into it.
///
/// It is shown on the first launch of a version that has the feature, to anyone whose last
/// version did not have it, however many versions they skipped. A fresh install never shows it,
/// and neither does any later update: the version a launch ran is recorded, and so is each
/// introduction once it has been on screen.
struct FeatureIntroduction: Equatable, Sendable {
    /// Recorded once shown, so neither a relaunch nor a later update shows it again.
    let id: String
    /// The newest version without the feature: an update from it, or from anything older, shows
    /// the introduction.
    let lastVersionWithout: SemanticVersion

    /// Desktop widgets came after 1.10.0.
    static let desktopWidgets = FeatureIntroduction(
        id: "desktopWidgets", lastVersionWithout: SemanticVersion("1.10.0")!)

    /// Every introduction, the one to show first first.
    static let all: [FeatureIntroduction] = [.desktopWidgets]
}

/// What decides whether a launch introduces a feature, and remembers the answer.
@MainActor
final class FeatureIntroductionStore {
    /// The newest version this Mac has launched. Builds before the first introduction never
    /// wrote it, so without it an existing user came from one of those.
    static let lastLaunchedVersionKey = "WallpaperMachine.lastLaunchedVersion"
    /// The ids of the introductions already shown.
    static let shownKey = "WallpaperMachine.featureIntroductionsShown"

    private let defaults: UserDefaults
    private let currentVersion: SemanticVersion?
    private let introductions: [FeatureIntroduction]

    init(
        defaults: UserDefaults = ClientPreferences.defaults,
        currentVersion: String = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "",
        introductions: [FeatureIntroduction] = FeatureIntroduction.all
    ) {
        self.defaults = defaults
        self.currentVersion = SemanticVersion(currentVersion)
        self.introductions = introductions
    }

    /// The introduction this launch shows, or nil.
    ///
    /// - Parameter existingUser: Whether this Mac used the app before (the first-run guide was
    ///   seen). It decides only when no launched version was ever recorded: an existing user then
    ///   came from a build older than every introduction, and anyone else is a fresh install.
    ///
    /// With nothing to show, the launch is recorded at once. With something, it is recorded only
    /// when the window is on screen (`didPresent`), so a launch that ends first offers it again.
    func due(existingUser: Bool) -> FeatureIntroduction? {
        guard let currentVersion else { return nil }
        let previous = defaults.string(forKey: Self.lastLaunchedVersionKey).flatMap(SemanticVersion.init)
        let shown = Set(defaults.stringArray(forKey: Self.shownKey) ?? [])
        let due = introductions.first { introduction in
            guard !shown.contains(introduction.id), currentVersion > introduction.lastVersionWithout
            else { return false }
            guard let previous else { return existingUser }
            return previous <= introduction.lastVersionWithout
        }
        if due == nil { recordLaunch() }
        return due
    }

    /// Called once the introduction is on screen: it is spent, whatever the person does next.
    func didPresent(_ introduction: FeatureIntroduction) {
        var shown = defaults.stringArray(forKey: Self.shownKey) ?? []
        if !shown.contains(introduction.id) { shown.append(introduction.id) }
        defaults.set(shown, forKey: Self.shownKey)
        recordLaunch()
    }

    /// Keeps the newest version launched: going back to an older one and up again is no update.
    private func recordLaunch() {
        guard let currentVersion else { return }
        let previous = defaults.string(forKey: Self.lastLaunchedVersionKey).flatMap(SemanticVersion.init)
        if let previous, previous >= currentVersion { return }
        defaults.set(currentVersion.display, forKey: Self.lastLaunchedVersionKey)
    }
}
