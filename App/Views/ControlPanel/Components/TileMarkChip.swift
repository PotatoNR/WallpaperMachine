import SwiftUI

/// A mark a tile wears on a corner of its picture, one vocabulary for the Library, the Steam
/// Workshop and pixiv grids. Each is a glyph on a disc that reads over any picture: the dark mark
/// disc for what the wallpaper is or has, and the accent disc only for Installed's update arrow,
/// something to act on. The accent disc with a tick is the selection check of an Installed tile
/// (`LibraryTileChrome.checkSymbol`), so a wallpaper already in the library wears the Library tab's
/// own grid symbol instead and is never taken for a ticked one.
///
/// The update arrow is the same `arrow.down` a Steam Workshop or pixiv ring shows while its download
/// waits: both say a download, and they never meet, since the arrow mark is only ever drawn in an
/// Installed tile's corner and a download ring only over a Steam Workshop or pixiv tile.
enum TileMark: Hashable, CaseIterable {
  /// The wallpaper is in the library.
  case inLibrary
  /// Wallpaper Engine's staff approved it.
  case approved
  /// The wallpaper is one of the favorites.
  case favorite
  /// The signed-in Steam account subscribes to it.
  case subscribed
  /// A Workshop preset: values for another wallpaper, which a download fetches with it.
  case preset
  /// Its author published an update.
  case update

  /// The tooltip, and the words VoiceOver reads with the tile.
  @MainActor
  var label: String {
    switch self {
    case .inLibrary: L("In your library")
    case .approved: L("Approved by Wallpaper Engine")
    case .favorite: L("Favorite")
    case .subscribed: L("Subscribed on Steam")
    case .preset: L("Preset")
    case .update: L("Update available")
    }
  }

  var systemImage: String {
    switch self {
    case .inLibrary: "square.grid.2x2.fill"
    case .approved: "trophy.fill"
    case .favorite: "heart.fill"
    case .subscribed: "bookmark.fill"
    case .preset: "slider.horizontal.3"
    case .update: "arrow.down"
    }
  }

  /// The glyph's colour and the disc's.
  func look(in theme: PanelTheme) -> (glyph: PanelColor, fill: PanelColor) {
    let surface = theme.surface
    switch self {
    case .update: return (theme.accent.onPrimary, theme.accent.primary)
    case .approved: return (surface.markApproved, surface.markFill)
    case .favorite: return (surface.markHeart, surface.markFill)
    case .inLibrary, .subscribed, .preset: return (surface.markGlyph, surface.markFill)
    }
  }
}

/// A `TileMark` drawn as a small round chip over a tile's picture, with its label as the tooltip.
/// A compact chip is for a tile too small for the full one (pixiv's).
struct TileMarkChip: View {
  let mark: TileMark
  var isCompact = false

  @Environment(\.panelTheme) private var theme

  init(_ mark: TileMark, isCompact: Bool = false) {
    self.mark = mark
    self.isCompact = isCompact
  }

  var body: some View {
    let look = mark.look(in: theme)
    let side: CGFloat = isCompact ? 16 : 20
    Image(systemName: mark.systemImage)
      .font(.panel(isCompact ? .proportional(to: side, ratio: 0.5, weight: .bold) : .mark))
      .foregroundStyle(look.glyph.color)
      .frame(width: side, height: side)
      .background(look.fill.color, in: Circle())
      .help(mark.label)
      .accessibilityHidden(true)
  }
}
