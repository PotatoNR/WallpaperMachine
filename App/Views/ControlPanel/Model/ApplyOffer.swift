import Foundation

/// What an inspector's apply button does for a wallpaper that is in the library, decided the same
/// way in the Installed, Workshop and pixiv inspectors, which all draw it with
/// `InspectorApplyButton`: the offer's own label, symbol and help, so only where the button sits
/// differs.
///
/// Applying what the target display already shows does nothing, so there the button reapplies,
/// which restarts it. Either way it runs under its own key (`reapplyWallpaper` or `activate`) and
/// is disabled while that action is pending, or when the wallpaper or the target cannot take it.
/// `PanelController.apply(_:)` carries it out.
struct ApplyOffer: Equatable {
  /// The symbol of putting a wallpaper on a display, wherever that is offered: Apply wallpaper,
  /// Download and apply, the Apply item of a tile's menu and the mark of an apply that waits. Never
  /// `play.fill`, which starts a rotation or resumes playback.
  static let symbol = "display.and.arrow.down"
  /// The symbol of Reapply wallpaper, which restarts what the target display shows.
  static let reapplySymbol = "arrow.clockwise"

  let wallpaperID: String
  /// The target display shows this wallpaper now: the button restarts it instead of applying it.
  let reapplies: Bool
  /// The wallpaper and the target display can take it and its action is not already pending.
  let isEnabled: Bool
  /// The target display's name, which the help says, or nil when there is only one display it
  /// could be (`PanelController.applyTargetName`). The label stays the bare verb, as VoiceOver's
  /// action and the toolbar's picker already say where.
  let targetName: String?

  /// - Parameters:
  ///   - shownID: what the target display shows now.
  ///   - canApply: the wallpaper can run and the target display can take it.
  ///   - targetName: the target display's name for the help (`PanelController.applyTargetName`).
  ///   - isBusy: whether an action key is pending (`PanelController.isBusy`).
  init(
    wallpaperID: String, shownID: String?, canApply: Bool, targetName: String? = nil,
    isBusy: (String) -> Bool
  ) {
    self.wallpaperID = wallpaperID
    reapplies = shownID == wallpaperID
    isEnabled = canApply && !isBusy(Self.key(wallpaperID, reapplies: reapplies))
    self.targetName = targetName
  }

  /// For the Workshop and pixiv inspectors: the target must be enabled and show a wallpaper of its
  /// own (not a mirror, not disabled); `canRun` is whether the wallpaper's type can play here.
  init(
    wallpaperID: String, target: MediaApplyTarget, canRun: Bool = true, targetName: String? = nil,
    isBusy: (String) -> Bool
  ) {
    self.init(
      wallpaperID: wallpaperID, shownID: target.wallpaperID,
      canApply: canRun && target.canShowWallpaper, targetName: targetName, isBusy: isBusy)
  }

  /// The key the button's action runs under.
  var key: String { Self.key(wallpaperID, reapplies: reapplies) }

  /// The button's symbol: `reapplySymbol` where it restarts the wallpaper, `symbol` otherwise.
  var systemImage: String { reapplies ? Self.reapplySymbol : Self.symbol }

  /// The button's label and accessibility label: **Apply wallpaper** or **Reapply wallpaper**.
  @MainActor var title: String { reapplies ? L("Reapply wallpaper") : L("Apply wallpaper") }

  /// The button's help: the label, naming the target display when there is more than one.
  @MainActor var help: String {
    guard let name = targetName else { return title }
    return reapplies ? L("Reapply wallpaper on \(name)") : L("Apply wallpaper to \(name)")
  }

  private static func key(_ wallpaperID: String, reapplies: Bool) -> String {
    PanelActionCoordinator.key(reapplies ? "reapplyWallpaper" : "activate", id: wallpaperID)
  }
}
