import SwiftUI

// The small controls the inspector is made of besides the panel's own buttons and links
// (`.panelPrimary`, `.panelSecondary`, `.panelLink`): icon buttons, notices and the collapsible
// section. All follow `\.panelTheme`, dim when disabled, and show a hover and a pressed state.

/// A square glyph button beside the main action: favorite, the more menu, Restore default.
struct InspectorIconButtonStyle: ButtonStyle {
  /// The glyph's colour when it is switched on (a favorite's heart).
  var activeTint: Color?
  var isActive = false
  var side: CGFloat = 28

  func makeBody(configuration: Configuration) -> some View {
    IconBody(configuration: configuration, activeTint: activeTint, isActive: isActive, side: side)
  }

  private struct IconBody: View {
    let configuration: ButtonStyleConfiguration
    let activeTint: Color?
    let isActive: Bool
    let side: CGFloat
    @Environment(\.panelTheme) private var theme
    @Environment(\.isEnabled) private var isEnabled
    @State private var isHovering = false

    var body: some View {
      configuration.label
        .font(.panel(.proportional(to: side, ratio: 0.5, weight: .medium)))
        .foregroundStyle(isActive ? (activeTint ?? theme.accent.accent.color) : theme.surface.text.color)
        .frame(width: side, height: side)
        .background(fill, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
        .panelDisabledOpacity(isEnabled)
        .contentShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
        .onHover { isHovering = $0 }
    }

    private var fill: Color {
      if configuration.isPressed { return theme.surface.pressed.color }
      return isHovering && isEnabled ? theme.surface.selected.color : theme.surface.hover.color
    }
  }
}

/// The inspector's lead action, Apply wallpaper: drawn as `.panelPrimary` while `isPrimary`,
/// otherwise as `.panelSecondary`, for the time staged edits give the accent to Apply changes.
///
/// Both looks come from the one body the panel's buttons share (`PanelButtonBody`), so the look
/// flips under the same view. Two buttons, or two style bodies chosen by an if/else, would give
/// the button a new identity the moment an edit is staged or applied, and its keyboard focus,
/// VoiceOver focus and hover would reset under the person using it.
struct InspectorActionButtonStyle: ButtonStyle {
  var isPrimary: Bool
  var size: PrimaryButtonStyle.Size = .regular
  var expands = false

  func makeBody(configuration: Configuration) -> some View {
    PanelButtonBody(
      configuration: configuration, look: isPrimary ? .accent : .quiet, size: size,
      expands: expands)
  }
}

extension ButtonStyle where Self == InspectorActionButtonStyle {
  static func inspectorAction(
    isPrimary: Bool, size: PrimaryButtonStyle.Size = .regular, expands: Bool = false
  ) -> InspectorActionButtonStyle {
    InspectorActionButtonStyle(isPrimary: isPrimary, size: size, expands: expands)
  }
}

// MARK: - Notices

/// A short status or warning in the inspector, tinted by what it says: a Workshop update, a host
/// that failed to load, shared resources that are missing.
struct InspectorNotice<Content: View>: View {
  enum Tone {
    case info, warning, error
  }

  var tone = Tone.info
  var systemImage: String?
  @ViewBuilder var content: Content

  @Environment(\.panelTheme) private var theme

  var body: some View {
    HStack(alignment: .top, spacing: 8) {
      if let glyph = systemImage ?? defaultSymbol {
        Image(systemName: glyph)
          .font(.panel(.calloutStrong))
          .foregroundStyle(accent)
          .frame(width: 14)
          .padding(.top, 1)
          .accessibilityHidden(true)
      }
      VStack(alignment: .leading, spacing: 6) { content }
        .font(.panel(.callout))
        .foregroundStyle(theme.surface.text.color)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
    .padding(10)
    .background(
      fill, in: RoundedRectangle(cornerRadius: PanelCardSurface.cornerRadius, style: .continuous))
    .overlay {
      RoundedRectangle(cornerRadius: PanelCardSurface.cornerRadius, style: .continuous)
        .strokeBorder(accent.opacity(tone == .info ? 0.2 : 0.28), lineWidth: 0.5)
    }
  }

  private var defaultSymbol: String? {
    switch tone {
    case .info: "info.circle.fill"
    case .warning: "exclamationmark.triangle.fill"
    case .error: "exclamationmark.octagon.fill"
    }
  }

  private var accent: Color {
    switch tone {
    case .info: theme.accent.accent.color
    case .warning: theme.surface.warning.color
    case .error: theme.surface.danger.color
    }
  }

  private var fill: Color {
    switch tone {
    case .info: theme.accent.accent.color.opacity(0.09)
    case .warning: theme.surface.warning.color.opacity(0.12)
    case .error: theme.surface.danger.color.opacity(0.1)
    }
  }
}

/// A line of muted explanation under a control or a card's rows.
struct InspectorNote: View {
  private let text: Text
  var insets = EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 0)

  @Environment(\.panelTheme) private var theme

  init(_ key: LocalizedStringKey) { text = Text(key) }
  init(verbatim: String) { text = Text(verbatim: verbatim) }
  init(_ text: Text) { self.text = text }

  var body: some View {
    text
      .font(.panel(.footnote))
      .foregroundStyle(theme.surface.muted.color)
      .frame(maxWidth: .infinity, alignment: .leading)
      .textSelection(.enabled)
      .padding(insets)
  }
}

// MARK: - Sections

/// A titled card that folds away: Compatibility check, General configuration, Wallpaper properties,
/// Displays. The open state is the view's own, so it starts as `isOpen` says when the section
/// first appears and then belongs to the person; the inspector keys its content by the wallpaper,
/// so a different wallpaper starts again from the defaults. `opensWhen` opens a closed section each
/// time it turns true (something it holds came to need the person), and never closes one.
struct InspectorSection<Accessory: View, Content: View>: View {
  private let title: Text
  private let usesCard: Bool
  private let isNested: Bool
  private let opensWhen: Bool
  private let accessory: Accessory
  private let content: Content
  @State private var isOpen: Bool

  @Environment(\.panelTheme) private var theme
  @Environment(\.accessibilityReduceMotion) private var reduceMotion

  init(
    _ title: LocalizedStringKey, isOpen: Bool = true, card: Bool = true, nested: Bool = false,
    @ViewBuilder accessory: () -> Accessory, @ViewBuilder content: () -> Content
  ) {
    self.title = Text(title)
    usesCard = card
    isNested = nested
    opensWhen = false
    self.accessory = accessory()
    self.content = content()
    _isOpen = State(initialValue: isOpen)
  }

  init(
    verbatim title: String, isOpen: Bool = true, opensWhen: Bool = false, card: Bool = true,
    nested: Bool = false, @ViewBuilder accessory: () -> Accessory, @ViewBuilder content: () -> Content
  ) {
    self.title = Text(verbatim: title)
    usesCard = card
    isNested = nested
    self.opensWhen = opensWhen
    self.accessory = accessory()
    self.content = content()
    _isOpen = State(initialValue: isOpen)
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 6) {
      Button {
        withAnimation(reduceMotion ? nil : .easeOut(duration: 0.18)) { isOpen.toggle() }
      } label: {
        HStack(spacing: 6) {
          VStack(alignment: .leading, spacing: 1) {
            title
              // A card's title is a group heading, as a Settings group's is; a nested one is a
              // label inside its card.
              .font(.panel(isNested ? .label : .sectionHeader))
              .foregroundStyle(isNested ? theme.surface.text.color : theme.surface.muted.color)
              .lineLimit(2)
            accessory
          }
          Spacer(minLength: 4)
          Image(systemName: "chevron.right")
            .font(.system(size: 9, weight: .bold))
            .rotationEffect(.degrees(isOpen ? 90 : 0))
            .accessibilityHidden(true)
        }
        .foregroundStyle(theme.surface.muted.color)
        .padding(.horizontal, 12)
        .frame(minHeight: 22)
        .contentShape(Rectangle())
      }
      .buttonStyle(.plain)
      .accessibilityAddTraits(.isHeader)
      .accessibilityValue(isOpen ? Text("Expanded") : Text("Collapsed"))
      if isOpen {
        Group {
          if usesCard {
            PanelCard { content }
          } else {
            content
          }
        }
        .transition(.opacity)
      }
    }
    .onChange(of: opensWhen) { _, opens in
      if opens, !isOpen {
        withAnimation(reduceMotion ? nil : .easeOut(duration: 0.18)) { isOpen = true }
      }
    }
  }
}

extension InspectorSection where Accessory == EmptyView {
  init(
    _ title: LocalizedStringKey, isOpen: Bool = true, card: Bool = true, nested: Bool = false,
    @ViewBuilder content: () -> Content
  ) {
    self.init(
      title, isOpen: isOpen, card: card, nested: nested, accessory: { EmptyView() },
      content: content)
  }

  init(
    verbatim title: String, isOpen: Bool = true, card: Bool = true, nested: Bool = false,
    @ViewBuilder content: () -> Content
  ) {
    self.init(
      verbatim: title, isOpen: isOpen, card: card, nested: nested, accessory: { EmptyView() },
      content: content)
  }
}

/// One row of an inspector card (`PanelCard`): a label on the leading side and its control or
/// value trailing, at least 36 points high.
struct InspectorRow<Label: View, Trailing: View>: View {
  private let label: Label
  private let trailing: Trailing

  init(@ViewBuilder trailing: () -> Trailing, @ViewBuilder label: () -> Label) {
    self.label = label()
    self.trailing = trailing()
  }

  var body: some View {
    HStack(spacing: 12) {
      label
        .font(.panel(.body))
        .frame(maxWidth: .infinity, alignment: .leading)
      trailing
    }
    .padding(.horizontal, 12)
    .padding(.vertical, 4)
    .frame(minHeight: 36)
  }
}

extension InspectorRow where Label == Text {
  /// A row named by fixed wording.
  init(_ title: LocalizedStringKey, @ViewBuilder trailing: () -> Trailing) {
    self.init(trailing: trailing) { Text(title) }
  }

  /// A row named by text that is not a catalog key.
  init(verbatim title: String, @ViewBuilder trailing: () -> Trailing) {
    self.init(trailing: trailing) { Text(verbatim: title) }
  }
}

/// A row of a card that is not a label and a control: a paragraph, a button, a notice.
struct InspectorCardRow<Content: View>: View {
  @ViewBuilder var content: Content

  var body: some View {
    content
      .padding(.horizontal, 12)
      .padding(.vertical, 8)
      .frame(maxWidth: .infinity, alignment: .leading)
  }
}

// MARK: - Announcements

/// Where the inspector's status lines are spoken: VoiceOver's announcement queue. A test puts a
/// recorder in the environment to hear what would be said.
struct PanelAnnouncer {
  let post: @MainActor (String) -> Void

  static let voiceOver = PanelAnnouncer { AccessibilityNotification.Announcement($0).post() }
}

extension EnvironmentValues {
  @Entry var panelAnnouncer = PanelAnnouncer.voiceOver
}

extension View {
  /// Posts `text` for VoiceOver whenever it changes to something: the status lines the web panel
  /// marked `role="status"`.
  func announcing(_ text: String?) -> some View {
    modifier(Announcing(text: text))
  }
}

private struct Announcing: ViewModifier {
  let text: String?

  @Environment(\.panelAnnouncer) private var announcer

  func body(content: Content) -> some View {
    content.onChange(of: text) { _, new in
      if let new, !new.isEmpty { announcer.post(new) }
    }
  }
}
