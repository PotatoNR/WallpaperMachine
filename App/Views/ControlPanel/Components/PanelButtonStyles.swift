import SwiftUI

/// The accent-filled button: Apply, Download, Choose wallpapers.
///
/// `.borderedProminent` always draws a white label, which cannot be read on a yellow, white or
/// grey accent. This style paints `AccentPalette.primary` and the label colour that was fitted to
/// it, and uses the palette's hover and pressed fills.
struct PrimaryButtonStyle: ButtonStyle {
  enum Size {
    case regular
    case compact
    /// As tall and in the same type as a small bordered button (`.controlSize(.small)`), for the
    /// main action of a row of small buttons, as on the Settings pages.
    case small

    var height: CGFloat {
      switch self {
      case .regular: 28
      case .compact: 24
      case .small: 20
      }
    }

    var font: PanelFont { self == .small ? .controlSmall : .control }
    var horizontalPadding: CGFloat { self == .small ? 9 : 14 }
    var cornerRadius: CGFloat { self == .small ? 5 : 7 }
  }

  var size: Size = .regular
  /// Whether the button takes the width it is offered, as the inspector's main action does.
  var expands = false

  func makeBody(configuration: Configuration) -> some View {
    PanelButtonBody(configuration: configuration, look: .accent, size: size, expands: expands)
  }
}

/// What a panel button is drawn as: the accent fill of the main action, or the quiet fill and
/// hairline of the button beside it.
enum PanelButtonLook: Equatable {
  /// The accent fill: `.panelPrimary`.
  case accent
  /// The translucent neutral fill and hairline: `.panelSecondary`.
  case quiet
}

/// The body every panel button with words is drawn by: `PrimaryButtonStyle`,
/// `DiscoverSecondaryButtonStyle` and the inspector's `InspectorActionButtonStyle`, so the main
/// action and the button beside it share their type, padding, corners and height
/// (`PrimaryButtonStyle.Size`), and a button whose look changes keeps the same view and its
/// hover. A `.destructive` role draws a secondary button's words in the danger colour.
struct PanelButtonBody: View {
  let configuration: ButtonStyleConfiguration
  let look: PanelButtonLook
  let size: PrimaryButtonStyle.Size
  let expands: Bool

  @Environment(\.panelTheme) private var theme
  @Environment(\.isEnabled) private var isEnabled
  @State private var isHovering = false

  var body: some View {
    let shape = RoundedRectangle(cornerRadius: size.cornerRadius, style: .continuous)
    configuration.label
      .font(.panel(size.font))
      .foregroundStyle(foreground)
      .lineLimit(1)
      .padding(.horizontal, size.horizontalPadding)
      .frame(maxWidth: expands ? .infinity : nil, minHeight: size.height)
      .background(fill, in: shape)
      .overlay { shape.strokeBorder(stroke, lineWidth: 0.5) }
      .panelDisabledOpacity(isEnabled)
      .contentShape(shape)
      .onHover { isHovering = $0 }
  }

  private var foreground: Color {
    Self.foreground(look: look, role: configuration.role, in: theme).color
  }

  /// The colour of a button's words and symbol: the label colour fitted to the accent fill, or on
  /// the quiet fill the text colour, and the danger colour for a `.destructive` role.
  static func foreground(look: PanelButtonLook, role: ButtonRole?, in theme: PanelTheme)
    -> PanelColor
  {
    switch look {
    case .accent: theme.accent.onPrimary
    case .quiet: role == .destructive ? theme.surface.danger : theme.surface.text
    }
  }

  /// The accent and its hover and pressed fills, or the translucent neutral ones, which read on a
  /// card, a bar and the window alike.
  private var fill: Color {
    let hovered = isHovering && isEnabled
    switch look {
    case .accent:
      let accent = theme.accent
      if configuration.isPressed { return accent.primaryActive.color }
      return hovered ? accent.primaryHover.color : accent.primary.color
    case .quiet:
      if configuration.isPressed { return theme.surface.pressed.color }
      return hovered ? theme.surface.selected.color : theme.surface.hover.color
    }
  }

  private var stroke: Color { look == .quiet ? theme.surface.line.color : .clear }
}

/// A quiet capsule button for the bars above a page: Filter, Sort, Select, and the pills that
/// report activity. `isActive` tints it with the accent, as a Filter that has filters set; a bar
/// short of room passes less `horizontalPadding` (`HeaderTier.capsulePadding`).
struct ToolbarCapsuleButtonStyle: ButtonStyle {
  var isActive = false
  var horizontalPadding: CGFloat = 10

  func makeBody(configuration: Configuration) -> some View {
    ToolbarCapsuleBody(
      configuration: configuration, isActive: isActive, horizontalPadding: horizontalPadding)
  }
}

private struct ToolbarCapsuleBody: View {
  let configuration: ButtonStyleConfiguration
  let isActive: Bool
  let horizontalPadding: CGFloat

  @Environment(\.panelTheme) private var theme
  @Environment(\.isEnabled) private var isEnabled
  @State private var isHovering = false

  var body: some View {
    configuration.label
      .font(.panel(.label))
      .foregroundStyle(isActive ? theme.accent.accent.color : theme.surface.text.color)
      .lineLimit(1)
      .padding(.horizontal, horizontalPadding)
      .frame(minHeight: 26)
      .background(background, in: Capsule())
      .panelDisabledOpacity(isEnabled)
      .contentShape(Capsule())
      .onHover { isHovering = $0 }
  }

  private var background: Color {
    if isActive { return theme.accent.accent.color.opacity(configuration.isPressed ? 0.24 : 0.16) }
    if configuration.isPressed { return theme.surface.pressed.color }
    return isHovering ? theme.surface.selected.color : theme.surface.hover.color
  }
}

extension ButtonStyle where Self == PrimaryButtonStyle {
  /// `PrimaryButtonStyle` at its regular size.
  static var panelPrimary: PrimaryButtonStyle { PrimaryButtonStyle() }
  static func panelPrimary(size: PrimaryButtonStyle.Size, expands: Bool = false)
    -> PrimaryButtonStyle
  {
    PrimaryButtonStyle(size: size, expands: expands)
  }
}

extension ButtonStyle where Self == ToolbarCapsuleButtonStyle {
  /// `ToolbarCapsuleButtonStyle` in its resting state.
  static var panelCapsule: ToolbarCapsuleButtonStyle { ToolbarCapsuleButtonStyle() }
  static func panelCapsule(isActive: Bool = false, horizontalPadding: CGFloat = 10)
    -> ToolbarCapsuleButtonStyle
  {
    ToolbarCapsuleButtonStyle(isActive: isActive, horizontalPadding: horizontalPadding)
  }
}
