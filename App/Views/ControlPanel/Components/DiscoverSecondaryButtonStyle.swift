import SwiftUI

/// The quiet counterpart of `PrimaryButtonStyle`: a translucent neutral fill with a hairline, for
/// the button beside the main one (Cancel, Revert, Pause, View on Steam Workshop).
///
/// `.bordered` draws a near-white button that disappears on a white surface; this one takes the
/// panel's own hover, selected and pressed fills, so it reads on a card, a bar and the window in
/// every tone and appearance. It is drawn by the primary button's body (`PanelButtonBody`), so it
/// sets the same type at the same size as the main button beside it, and may expand to the width
/// it is offered, as the inspector's buttons do. A button whose role is `.destructive` (Move to
/// Trash, Delete) draws its title and symbol in the theme's danger colour; its fills stay neutral.
struct DiscoverSecondaryButtonStyle: ButtonStyle {
  var size: PrimaryButtonStyle.Size = .regular
  var expands = false

  func makeBody(configuration: Configuration) -> some View {
    PanelButtonBody(configuration: configuration, look: .quiet, size: size, expands: expands)
  }
}

extension ButtonStyle where Self == DiscoverSecondaryButtonStyle {
  /// `DiscoverSecondaryButtonStyle` at its regular size.
  static var panelSecondary: DiscoverSecondaryButtonStyle { DiscoverSecondaryButtonStyle() }
  static func panelSecondary(size: PrimaryButtonStyle.Size, expands: Bool = false)
    -> DiscoverSecondaryButtonStyle
  {
    DiscoverSecondaryButtonStyle(size: size, expands: expands)
  }
}
