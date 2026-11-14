import SwiftUI

/// A button that reads as a link: the panel's accent colour, underlined while the pointer is over
/// it, dimmed while pressed. A `.destructive` role (Delete…, Remove from display) draws it in the
/// danger colour instead.
///
/// The system `.link` style takes the foreground colour of the view it is in, so it goes dark
/// wherever a container sets the panel's text colour. This one draws the contrast-fitted accent
/// itself (`AccentPalette.accent`), which reads on every surface. It sets no font: a link takes
/// the type of the text around it, as in a notice or in the column of links under an inspector's
/// notes (`.panel(.callout)` with `.panelLinkRow`). An action link that stands on its own in an
/// inspector card (Center, Check again, Delete…) is `.panelCardLink` instead.
struct DiscoverLinkButtonStyle: ButtonStyle {
  /// The least height a card's own link is drawn and clicked at, so a short link is still easy to
  /// hit.
  static let cardLinkHeight: CGFloat = 20

  /// Whether the link stands on its own in an inspector card: it then sets the card's label type
  /// (`.panel(.label)`) and is at least `cardLinkHeight` tall.
  var isCardLink = false

  func makeBody(configuration: Configuration) -> some View {
    DiscoverLinkButtonBody(configuration: configuration, isCardLink: isCardLink)
  }

  /// A link's colour: the accent, or the danger colour for a `.destructive` role.
  static func foreground(role: ButtonRole?, in theme: PanelTheme) -> PanelColor {
    role == .destructive ? theme.surface.danger : theme.accent.accent
  }
}

private struct DiscoverLinkButtonBody: View {
  let configuration: ButtonStyleConfiguration
  let isCardLink: Bool

  @Environment(\.panelTheme) private var theme
  @Environment(\.isEnabled) private var isEnabled
  @State private var isHovering = false

  var body: some View {
    label
      .foregroundStyle(DiscoverLinkButtonStyle.foreground(role: configuration.role, in: theme).color)
      .underline(isHovering && isEnabled)
      .opacity(configuration.isPressed ? 0.6 : 1)
      .panelDisabledOpacity(isEnabled)
      .contentShape(Rectangle())
      .onHover { isHovering = $0 }
  }

  @ViewBuilder
  private var label: some View {
    if isCardLink {
      configuration.label
        .font(.panel(.label))
        .frame(minHeight: DiscoverLinkButtonStyle.cardLinkHeight)
    } else {
      configuration.label
    }
  }
}

extension ButtonStyle where Self == DiscoverLinkButtonStyle {
  /// `DiscoverLinkButtonStyle`, in the type of the text around it.
  static var panelLink: DiscoverLinkButtonStyle { DiscoverLinkButtonStyle() }
  /// `DiscoverLinkButtonStyle` for an action link on its own in an inspector card: the card's
  /// label type and a click target at least `cardLinkHeight` tall.
  static var panelCardLink: DiscoverLinkButtonStyle { DiscoverLinkButtonStyle(isCardLink: true) }
}

/// A link's symbol in a column of fixed width before its words, so links stacked one under another
/// start their words at the same place however wide their symbols are.
struct PanelLinkRowLabelStyle: LabelStyle {
  func makeBody(configuration: Configuration) -> some View {
    HStack(spacing: 6) {
      configuration.icon
        .frame(width: 18)
      configuration.title
    }
  }
}

extension LabelStyle where Self == PanelLinkRowLabelStyle {
  /// `PanelLinkRowLabelStyle`, for the label of a `.panelLink` button in a stack of links.
  static var panelLinkRow: PanelLinkRowLabelStyle { PanelLinkRowLabelStyle() }
}
