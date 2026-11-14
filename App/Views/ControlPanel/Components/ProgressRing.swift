import SwiftUI

/// A thin ring that shows how far something is, or that it is working when that is not known.
///
/// Only the indeterminate ring moves, and only while it is `isActive`, the panel is on screen and
/// Reduce Motion is off; otherwise it is a still arc. It is decoration: the control that holds it
/// states the progress in its own accessibility label.
struct ProgressRing: View {
  /// 0 to 1, or nil while the amount is not known.
  let value: Double?
  var lineWidth: CGFloat = 2
  var isActive = true

  @Environment(\.panelIsVisible) private var panelIsVisible
  @Environment(\.accessibilityReduceMotion) private var reduceMotion

  private var spins: Bool { value == nil && isActive && panelIsVisible && !reduceMotion }

  var body: some View {
    ZStack {
      Circle().stroke(.primary.opacity(0.14), lineWidth: lineWidth)
      if let value {
        Circle()
          .trim(from: 0, to: min(max(value, 0), 1))
          .stroke(.tint, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
          .rotationEffect(.degrees(-90))
          .animation(reduceMotion ? nil : .easeOut(duration: 0.3), value: value)
      } else {
        // The timeline stops asking for frames while paused, so a ring that is not spinning costs
        // nothing.
        TimelineView(.animation(minimumInterval: 1.0 / 30, paused: !spins)) { context in
          Circle()
            .trim(from: 0, to: 0.26)
            .stroke(.tint, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
            .rotationEffect(.degrees(spins ? Self.angle(at: context.date) : -90))
        }
      }
    }
    .padding(lineWidth / 2)
    .accessibilityHidden(true)
  }

  /// One turn a second.
  static func angle(at date: Date) -> Double {
    (date.timeIntervalSinceReferenceDate * 360).truncatingRemainder(dividingBy: 360) - 90
  }
}

/// The bar a row, card or page edge shows while something runs, the linear `ProgressRing`. With an
/// amount it is the system's bar. Without one it is a short segment that slides along the track,
/// and only while the panel is on screen and Reduce Motion is off; otherwise the segment rests in
/// the middle, so it never reads as an amount. The system's indeterminate bar keeps sliding in a
/// hidden window and with Reduce Motion. It takes the system bar's height at the control size
/// around it, so a bar that learns its amount does not move what is under it.
///
/// It is one accessibility element: the place that holds it gives it a label, as it did the system
/// bar, unless the words beside it already say what is running.
struct ProgressBar: View {
  /// 0 to 1, or nil while the amount is not known.
  let value: Double?

  @Environment(\.panelIsVisible) private var panelIsVisible
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @Environment(\.controlSize) private var controlSize

  private var slides: Bool { panelIsVisible && !reduceMotion }

  /// The system bar's track at this control size: its frame and the capsule drawn inside it.
  private var metrics: (frame: CGFloat, track: CGFloat) {
    switch controlSize {
    case .mini, .small: (12, 6)
    default: (20, 8)
    }
  }

  var body: some View {
    if let value {
      ProgressView(value: value).progressViewStyle(.linear)
    } else {
      // The timeline stops asking for frames while paused, so a bar that is not sliding costs
      // nothing.
      TimelineView(.animation(minimumInterval: 1.0 / 30, paused: !slides)) { context in
        let start = slides ? Self.start(at: context.date) : (1 - Self.segment) / 2
        ZStack {
          Capsule().fill(.primary.opacity(0.07))
          Segment(start: start, length: Self.segment).fill(.tint)
          Capsule().strokeBorder(.primary.opacity(0.08), lineWidth: 0.5)
        }
        .clipShape(Capsule())
      }
      .frame(height: metrics.track)
      .frame(maxWidth: .infinity, minHeight: metrics.frame, maxHeight: metrics.frame)
      .accessibilityElement(children: .ignore)
    }
  }

  /// The sliding segment's share of the track.
  static let segment = 0.3

  /// Where the segment's leading edge is, as a share of the track: it enters at the leading end
  /// and leaves at the trailing one, easing in and out, once every 1.5 seconds.
  static func start(at date: Date) -> Double {
    let phase = (date.timeIntervalSinceReferenceDate / 1.5).truncatingRemainder(dividingBy: 1)
    let eased = phase * phase * (3 - 2 * phase)
    return eased * (1 + segment) - segment
  }

  /// The part of the track from `start` to `start + length`, cut where it leaves the track.
  private struct Segment: Shape {
    let start: Double
    let length: Double

    func path(in rect: CGRect) -> Path {
      let leading = rect.minX + rect.width * max(start, 0)
      let trailing = rect.minX + rect.width * min(start + length, 1)
      guard trailing > leading else { return Path() }
      return Path(
        roundedRect: CGRect(x: leading, y: rect.minY, width: trailing - leading, height: rect.height),
        cornerRadius: rect.height / 2)
    }
  }
}

/// The small ring under a page's words while the page is first read or fetched. The Library, Steam
/// Workshop and pixiv loading states all show this one, so they look alike and all stop in a hidden
/// window and with Reduce Motion, which the system spinner does not.
struct LoadingRing: View {
  var body: some View {
    ProgressRing(value: nil, lineWidth: 1.75).frame(width: 13, height: 13)
  }
}

/// The dark disc a status sits on over a picture: the download ring of a Steam Workshop or pixiv
/// tile and the mark of an Installed tile's apply that waits, one look on every page. It is the
/// same in every tone, season and appearance, since the picture under it can be any colour
/// (`SurfacePalette.markFill`), and darker while a ring that can be clicked is under the pointer.
struct ArtworkDisc: View {
  var isHighlighted = false

  @Environment(\.panelTheme) private var theme

  var body: some View {
    Circle().fill((isHighlighted ? theme.surface.markFillHover : theme.surface.markFill).color)
  }
}
