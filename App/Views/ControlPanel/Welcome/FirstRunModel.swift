import Foundation
import Observation

/// The first-run guide: five pages, shown once per Mac and again on request from Settings.
///
/// Language, appearance and the lock screen act the moment they are chosen (Skip puts back what
/// was there when the guide opened); the performance choices and the other preferences are drafts
/// that **Continue** commits. The guide asks for no Steam account and holds no password: the first
/// Workshop download asks for what it needs when it needs it. **Skip setup**, or Escape, ends the
/// guide from any page but the last.
///
/// All guide state lives here, not in the views, so a redraw loses nothing. A closed window releases
/// the controller and with it this model: the guide then starts again at page one with its drafts
/// gone, while what was applied at once (language, appearance, lock screen) stays.
@MainActor
@Observable
final class FirstRunModel {
  unowned let controller: PanelController

  /// What the guide waits on. A key is in the set while its action runs; a second request for the
  /// same key does nothing.
  enum Pending: Hashable, Sendable {
    case language, theme, performance, preferences, lockScreen
  }

  /// What the guide found when it opened, which Skip puts back.
  struct Initial: Equatable, Sendable {
    var mode: AppThemePreferences.Mode
    /// `AppLanguageStore.systemChoice` or a shipped tag.
    var language: String
    var lockScreen: Bool
  }

  // MARK: State

  /// Whether the guide is on screen, from the host's point of view.
  private(set) var isOpen = false
  private(set) var step = WelcomeStep.language
  /// The page's one message: the failure of the last action, cleared by every action and every move.
  private(set) var error: String?
  private(set) var pending = Set<Pending>()
  private(set) var initial: Initial?
  var performance = WelcomePerformanceDraft()
  var preferences = WelcomePreferenceDraft()
  /// **Import wallpapers** was chosen and the library's Import popover waits for the window to have
  /// drawn Installed (`openWaitingImportPopover()`).
  private(set) var importPopoverIsWaiting = false
  /// Counted up when the page title should take VoiceOver focus.
  private(set) var titleFocusRequest = 0

  init(controller: PanelController) { self.controller = controller }

  // MARK: Opening and closing

  /// Opens at the first page with nothing drafted. The host calls it when the guide appears, the
  /// first time or because Settings asked for it again.
  func open() {
    guard !isOpen else { return }
    isOpen = true
    step = .language
    error = nil
    performance.clear()
    preferences.clear()
    initial = Initial(
      mode: controller.themePreferences.mode,
      language: controller.languagePreference?.tag ?? AppLanguageStore.systemChoice,
      lockScreen: controller.lockScreenState.isRequested)
  }

  /// Closes the guide's own state; the host calls it when the guide goes away.
  func close() { isOpen = false }

  /// Ends the guide: the first-run flag is set unless it already is (a guide replayed from Settings
  /// leaves it alone), and the guide is no longer requested. A first run's guide was the day's
  /// question, so no one-time prompt follows it that day.
  func finish() {
    if !controller.welcomeSeen {
      controller.markWelcomeSeen()
      controller.store.supportPrompt?.recordWelcomeGuideEnded()
    }
    controller.shell.isWelcomeRequested = false
    close()
  }

  /// **Browse the Workshop**: ends the guide, then opens Steam Workshop.
  @discardableResult
  func browse() -> Task<Void, Never> {
    finish()
    return controller.launch(PanelActionCoordinator.key("navigate"), policy: .latestWins) {
      [controller] in try await controller.navigate(.workshop)
    }
  }

  /// **Import wallpapers**: ends the guide, shows Installed and asks for the library's Import
  /// popover, which explains what an import does and what happens to a wallpaper the library
  /// already holds, rather than going straight to the file picker.
  @discardableResult
  func importWallpapers() -> Task<Void, Never> {
    finish()
    return controller.launch(PanelActionCoordinator.key("navigate"), policy: .latestWins) {
      [self, controller] in
      try await controller.navigate(.wallpaper)
      importPopoverIsWaiting = true
    }
  }

  /// Opens the Import popover **Import wallpapers** asked for. The host calls it once the window has
  /// drawn the page change: the root closes every popover when the page changes, and a popover
  /// opened before that (a guide replayed from Settings comes back to Installed) would stay on
  /// screen while the window believed none was open, which the support offer waits on.
  func openWaitingImportPopover() {
    guard importPopoverIsWaiting else { return }
    importPopoverIsWaiting = false
    controller.library.openImport(from: .page)
  }

  // MARK: Moving

  /// Whether the footer's controls and the progress dots wait: a choice is being committed, and the
  /// guide must not leave a partly submitted operation.
  var navigationBusy: Bool {
    !pending.isDisjoint(with: [.language, .theme, .performance, .preferences, .lockScreen])
  }

  func go(to destination: WelcomeStep) {
    guard !navigationBusy else { return }
    step = destination
    error = nil
    // The Preferences page carries the performance data switch and the On battery choice, so it
    // answers both one-time questions; someone who leaves the guide before reaching it is asked
    // once later instead.
    if destination == .preferences {
      controller.store.supportPrompt?.recordTelemetryAsked()
      controller.store.supportPrompt?.recordBatteryAsked()
    }
  }

  func next() { if let next = step.next { go(to: next) } }
  func back() { if let previous = step.previous { go(to: previous) } }

  /// Whether **Skip setup** is offered: on every page but the last, whose **Start using the app**
  /// already ends the guide.
  var offersSkipSetup: Bool { !step.isLast }

  /// **Skip setup**, and Escape: ends the guide now, as **Start using the app** does. What applied
  /// at once stays, and the questions of pages never reached (performance data, battery) are asked
  /// later by the one-time prompts. Drafts are never dropped or saved silently: with any unsaved,
  /// the guide goes to the Start page instead, whose recap lists them with **Review**, and ends from
  /// there. Does nothing while a choice is being committed, or on the last page.
  func skipSetup() {
    guard !navigationBusy, offersSkipSetup else { return }
    if unsavedPerformanceCount + unsavedPreferencesCount > 0 {
      go(to: .start)
      requestTitleFocus()
      return
    }
    finish()
  }

  /// The shape of every action: refuses a repeat, shows a failure on the page and reports whether it
  /// worked. The failure never reaches the window banner, which sits behind the guide.
  @discardableResult
  private func perform(_ key: Pending, _ work: () async throws -> Void) async -> Bool {
    guard !pending.contains(key) else { return false }
    pending.insert(key)
    error = nil
    defer { pending.remove(key) }
    do {
      try await work()
      return true
    } catch is CancellationError {
      return false
    } catch {
      self.error = error.localizedDescription
      return false
    }
  }

  // MARK: Page 1: language and appearance

  /// The language chosen, `AppLanguageStore.systemChoice` while the app follows macOS.
  var languageChoice: String {
    controller.languagePreference?.tag ?? AppLanguageStore.systemChoice
  }

  var appearance: AppThemePreferences.Mode { controller.themePreferences.mode }

  /// Applies a language at once: the guide, the panel and the import picker switch together.
  func chooseLanguage(_ tag: String) async {
    guard tag != languageChoice else { return }
    let language = AppLanguage.named(tag)
    guard language != nil || tag == AppLanguageStore.systemChoice else { return }
    await perform(.language) { try await controller.setLanguage(language) }
  }

  func chooseAppearance(_ mode: AppThemePreferences.Mode) async {
    guard mode != appearance else { return }
    await perform(.theme) { try controller.setThemeMode(mode) }
  }

  /// Puts back the appearance and then the language the guide opened with, then moves on. A failed
  /// restore is silent: moving clears the message.
  func skipLanguage() async {
    if let initial {
      if appearance != initial.mode { await chooseAppearance(initial.mode) }
      if languageChoice != initial.language { await chooseLanguage(initial.language) }
    }
    next()
  }

  // MARK: Focus

  func requestTitleFocus() { titleFocusRequest &+= 1 }

  // MARK: Page 2: performance

  /// What is saved: the limit and the render scale the engine reports.
  var savedFrameRateCap: UInt32? { controller.store.settingsSnapshot.frameRateCap }
  var savedRenderScale: Float { controller.store.settingsSnapshot.preferredRenderScale }
  var frameRateSlider: FrameRateCapSlider {
    FrameRateCapSlider(displays: controller.store.settingsSnapshot.displays)
  }

  var shownFrameRateCap: UInt32? { performance.frameRateCap(saved: savedFrameRateCap) }
  var shownPreset: QualityPreset? {
    performance.activePreset(savedCap: savedFrameRateCap, savedScale: savedRenderScale)
  }

  /// Where the slider sits for the draft, or the saved limit.
  var frameRatePosition: Int { frameRateSlider.position(forCap: shownFrameRateCap) }

  func choosePreset(_ preset: QualityPreset) { performance.choose(preset) }

  func setFrameRatePosition(_ position: Int) {
    performance.setFrameRateCap(frameRateSlider.cap(atPosition: position))
  }

  var unsavedPerformanceCount: Int {
    performance.changes(savedCap: savedFrameRateCap, savedScale: savedRenderScale).count
  }

  /// **Continue** on Performance: sends each changed draft, in the order chosen, then moves on. A
  /// refusal stays on the page with its reason; what was already sent now matches the engine and the
  /// rest stay drafts.
  func continuePerformance() async {
    guard !navigationBusy else { return }
    let changes = performance.changes(savedCap: savedFrameRateCap, savedScale: savedRenderScale)
    guard !changes.isEmpty else {
      performance.clear()
      next()
      return
    }
    let committed = await perform(.performance) {
      for change in changes {
        switch change {
        case .frameRateCap(let cap): try await controller.setFrameRateCap(cap.map(Int.init))
        case .renderScale(let scale): try await controller.setRenderScale(Double(scale))
        }
      }
    }
    if committed {
      performance.clear()
      next()
    }
  }

  func skipPerformance() {
    guard !navigationBusy else { return }
    performance.clear()
    next()
  }

  // MARK: Page 3: preferences

  /// What the engine, macOS and the telemetry service report for the drafted preferences.
  var savedPreferences: WelcomePreferenceValues {
    WelcomePreferenceValues(
      launchAtLogin: controller.generalSettings.launchAtLogin.isOn,
      keepsWindowsOnWallpaperClick: controller.desktopSettings.keepsWindowsOnWallpaperClick,
      batteryMode: controller.store.settingsSnapshot.batteryMode,
      sendsPerformanceData: controller.performanceData?.isEnabled ?? false)
  }

  var shownPreferences: WelcomePreferenceValues { preferences.values(saved: savedPreferences) }

  var unsavedPreferencesCount: Int { preferences.changes(saved: savedPreferences).count }

  /// **Continue** on Preferences: the same ordered commit as Performance.
  func continuePreferences() async {
    guard !navigationBusy else { return }
    let changes = preferences.changes(saved: savedPreferences)
    guard !changes.isEmpty else {
      preferences.clear()
      next()
      return
    }
    let committed = await perform(.preferences) {
      for change in changes {
        switch change {
        case .launchAtLogin(let enabled): try await controller.setLaunchAtLogin(enabled)
        case .keepsWindows(let keeps): try await controller.setKeepsWindowsOnWallpaperClick(keeps)
        case .batteryMode(let mode): try await controller.setBatteryMode(mode)
        case .performanceData(let enabled): try await controller.setSendsPerformanceData(enabled)
        }
      }
    }
    if committed {
      preferences.clear()
      next()
    }
  }

  /// **Skip** on Preferences: drops the drafts, puts the lock screen back if the guide changed it,
  /// and moves on.
  func skipPreferences() async {
    guard !navigationBusy else { return }
    preferences.clear()
    if let initial, controller.lockScreenState.isRequested != initial.lockScreen {
      await perform(.lockScreen) { try await controller.setLockScreenEnabled(initial.lockScreen) }
    }
    next()
  }

  /// The lock screen applies at once, like Settings. A refusal leaves the switch where the service
  /// says it is and shows why.
  func setLockScreen(_ enabled: Bool) async {
    await perform(.lockScreen) { try await controller.setLockScreenEnabled(enabled) }
  }

  /// The lock screen row as it reads now: why it is unavailable, that it is working, or what it
  /// promises.
  var lockScreenRow: LockScreenRow {
    LockScreenRow.make(
      state: controller.lockScreenState, requestIsRunning: pending.contains(.lockScreen),
      isCommitting: pending.contains(.preferences))
  }

  /// Whether the Launch at login switch can be used: outside Applications the app cannot register
  /// itself, but a login item the person switched off in System Settings can still be asked for, and
  /// the row then says where to allow it.
  var canChangeLaunchAtLogin: Bool {
    !pending.contains(.preferences) && controller.generalSettings.launchAtLogin.isAvailable
  }

  /// Whether the Send performance data switch can be used: a run without the telemetry service
  /// (tests, a diagnostic run) has nothing to turn on.
  var canChangePerformanceData: Bool {
    !pending.contains(.preferences) && controller.performanceData != nil
  }

  // MARK: Page 5: start

  var recap: WelcomeRecap {
    WelcomeRecap.make(
      languageName: AppLanguage.named(languageChoice)?.name, appearance: appearance,
      signedInAccount: controller.steamAccount.saved,
      unsavedPerformance: unsavedPerformanceCount, unsavedPreferences: unsavedPreferencesCount)
  }
}

/// What the Animate lock screen row says and whether its switch can be used. Unlike the other rows it
/// is not a draft: it applies at once, so it waits for the service while it works.
struct LockScreenRow: Equatable {
  enum Note: Equatable {
    /// Why it cannot be turned on: the macOS version, or no service.
    case unavailable(String)
    /// The service is working, in its own words with an ellipsis.
    case working(String)
    /// The default: "Experimental. Applies right away."
    case promise
  }

  let note: Note
  let isSwitchEnabled: Bool

  /// - Parameters:
  ///   - requestIsRunning: the guide's own change is on its way to the service.
  ///   - isCommitting: **Continue** is committing the drafts, which holds every control.
  @MainActor
  static func make(state: LockScreenState, requestIsRunning: Bool, isCommitting: Bool) -> LockScreenRow
  {
    guard state.isAvailable else {
      return LockScreenRow(note: .unavailable(state.statusText), isSwitchEnabled: false)
    }
    let working = requestIsRunning || state.isBusy
    if working {
      // The service's words while it works; "Updating…" for the moment before it says anything.
      let text = state.isBusy ? state.statusText : L("Updating") + "…"
      return LockScreenRow(note: .working(text), isSwitchEnabled: false)
    }
    return LockScreenRow(note: .promise, isSwitchEnabled: !isCommitting)
  }
}

/// The recap of the Start page: what the guide set, and what it holds back.
struct WelcomeRecap: Equatable {
  struct Unsaved: Equatable, Identifiable {
    let step: WelcomeStep
    let count: Int
    var id: WelcomeStep { step }
  }

  /// The language's own name, nil while the app follows macOS (the page then says System (Auto)).
  let languageName: String?
  let appearance: AppThemePreferences.Mode
  /// What the Steam row says: who is signed in for downloads, or that the first download asks.
  let steam: String
  /// The pages with drafts that were not saved, Performance then Preferences.
  let unsaved: [Unsaved]

  /// - Parameter signedInAccount: the account signed in for downloads on this Mac (a SteamCMD or a
  ///   QR sign-in), nil without one.
  @MainActor
  static func make(
    languageName: String?, appearance: AppThemePreferences.Mode, signedInAccount: String?,
    unsavedPerformance: Int, unsavedPreferences: Int
  ) -> WelcomeRecap {
    let steam: String
    if let account = signedInAccount, !account.isEmpty {
      steam = L("Signed in as \(account)")
    } else {
      steam = L("Not signed in. You’ll be asked at your first download.")
    }
    return WelcomeRecap(
      languageName: languageName, appearance: appearance, steam: steam,
      unsaved: [
        Unsaved(step: .performance, count: unsavedPerformance),
        Unsaved(step: .preferences, count: unsavedPreferences),
      ].filter { $0.count > 0 })
  }
}
