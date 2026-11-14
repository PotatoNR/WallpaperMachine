import SwiftUI

/// The ring a Workshop tile wears over its picture while the wallpaper is on its way: live
/// progress, one click to cancel, a shield when Steam needs the person, a retry mark after a
/// failure. A ring whose click cancels swaps its centre for a cross while hovered or while its tile
/// has keyboard focus, as pixiv's does.
///
/// It draws a `TileDownloadState` and nothing else; the state says what the ring is, what it reads
/// and what a click does, and the tile passes the action on. Only a ring that has something to show
/// moves: a transfer without a figure sweeps, and a ring that waits for the person breathes, both only
/// while the window is on screen and Reduce Motion is off.
struct WorkshopTileRing: View {
  let state: TileDownloadState
  /// The ring's outside diameter, which the tile sizes to its width.
  let diameter: CGFloat
  let action: () -> Void

  @Environment(\.panelTheme) private var theme
  @Environment(\.panelIsVisible) private var panelIsVisible
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  /// The tile's keyboard focus: the grids are `TileGrid`s, whose focus is the tile cell.
  @Environment(\.isFocused) private var isFocused
  @State private var isHovering = false

  /// The most the ring grows: bigger tiles do not need a bigger ring.
  static let largestDiameter: CGFloat = 64

  var body: some View {
    Button(action: action) {
      ZStack {
        ArtworkDisc(isHighlighted: isHovering && interactive)
        ring
        centre
        if showsClose {
          Image(systemName: DownloadRowAction.cancel.systemImage)
            .font(.panel(.proportional(to: diameter, ratio: 0.26, weight: .bold)))
            .foregroundStyle(theme.surface.markGlyph.color)
            .transition(.opacity)
        }
      }
      .frame(width: diameter, height: diameter)
      .contentShape(Circle())
    }
    .buttonStyle(.plain)
    .disabled(!state.isEnabled)
    // The one control that fades less than `PanelTheme.disabledOpacity`: a ring that cannot be
    // clicked yet (a retry waiting for SteamCMD's setup) sits on a dimmed picture, where it would
    // all but vanish at 0.4, and it still has to say why the download stopped.
    .opacity(state.isEnabled ? 1 : 0.6)
    .onHover { isHovering = $0 }
    .animation(reduceMotion ? nil : .easeOut(duration: 0.12), value: isHovering)
    .help(state.label)
    .accessibilityLabel(Text(verbatim: state.label))
    .accessibilityIdentifier("workshop-tile-ring")
  }

  private var interactive: Bool { state.isEnabled }

  private var showsClose: Bool { state.showsClose(isHovering: isHovering, isFocused: isFocused) }

  /// The track and the value arc, over the backdrop.
  @ViewBuilder
  private var ring: some View {
    let width = max(2.5, diameter * 0.06)
    switch state.kind {
    case .progress:
      ProgressRing(value: state.progress, lineWidth: width)
        .foregroundStyle(theme.surface.markGlyph.color)
        .tint(accent)
        .padding(diameter * 0.1)
    case .busy:
      ProgressRing(value: nil, lineWidth: width)
        .foregroundStyle(theme.surface.markGlyph.color)
        .tint(accent)
        .padding(diameter * 0.1)
    case .attention:
      Circle()
        .strokeBorder(accent, lineWidth: width)
        .padding(diameter * 0.1)
        .overlay { Halo(isActive: panelIsVisible && !reduceMotion, color: accent) }
    case .failed:
      Circle()
        .strokeBorder(theme.surface.danger.color, lineWidth: width)
        .padding(diameter * 0.1)
    case .queued:
      Circle()
        .strokeBorder(theme.surface.markGlyph.color.opacity(0.28), lineWidth: width)
        .padding(diameter * 0.1)
    }
  }

  /// What sits inside: the percentage or the step word, with the speed under it, or a glyph.
  @ViewBuilder
  private var centre: some View {
    // The same rule as the close mark, so the two never draw over each other.
    let hidden = showsClose
    Group {
      if !state.text.isEmpty || !state.speed.isEmpty {
        VStack(spacing: 0) {
          if !state.text.isEmpty {
            Text(verbatim: state.text)
              .font(
                .panel(
                  .proportional(
                    to: diameter, ratio: state.isStepWord ? 0.145 : 0.24, weight: .semibold),
                  design: .rounded
                ).monospacedDigit()
              )
              .lineLimit(1)
              .minimumScaleFactor(0.6)
          }
          if !state.speed.isEmpty {
            Text(verbatim: state.speed)
              .font(.panel(.proportional(to: diameter, ratio: 0.115, minimum: 7.5)).monospacedDigit())
              .opacity(0.8)
              .lineLimit(1)
              .minimumScaleFactor(0.6)
          }
        }
        .padding(.horizontal, diameter * 0.16)
      } else if let glyph = state.glyph {
        Image(systemName: glyph.systemImage)
          .font(.panel(.proportional(to: diameter, ratio: 0.3, weight: .semibold)))
      }
    }
    .foregroundStyle(theme.surface.markGlyph.color)
    .opacity(hidden ? 0 : 1)
  }

  private var accent: Color { theme.accent.accent.color }

  /// A soft pulse around a ring that waits for the person. It draws frames only while it is active
  /// and stops entirely otherwise.
  private struct Halo: View {
    let isActive: Bool
    let color: Color

    var body: some View {
      TimelineView(.animation(minimumInterval: 1.0 / 24, paused: !isActive)) { context in
        let phase = isActive ? (context.date.timeIntervalSinceReferenceDate / 1.6).truncatingRemainder(dividingBy: 1) : 0
        Circle()
          .strokeBorder(color.opacity(isActive ? 0.5 * (1 - phase) : 0), lineWidth: 2)
          .scaleEffect(1 + 0.22 * phase)
      }
    }
  }
}
