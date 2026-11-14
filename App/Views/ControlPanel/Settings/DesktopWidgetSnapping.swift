import CoreGraphics

/// Where a widget dragged on Settings › Desktop Widgets' Arrange picture snaps to, and the guides
/// the picture draws while it does. A widget is pulled, within `threshold`, onto:
///
/// - the display's centre lines, with its own centre;
/// - the lines a third of the way across and down, with its own centre;
/// - a margin in from each edge, with the edge facing it;
/// - another widget on the same display: its edges and centre with the dragged one's.
///
/// The nearest line on each axis wins, so a widget can sit on a vertical and a horizontal line at
/// once. Everything is in the picture's points, top-left origin, so the pull feels the same at
/// every display size.
enum DesktopWidgetSnapping {
  /// A guide's direction: a vertical line marks an x, a horizontal one a y.
  enum Axis: Hashable, Sendable {
    case vertical, horizontal
  }

  /// What a guide lines the widget up with, which the picture draws differently.
  enum Kind: Hashable, Sendable {
    /// The display's centre line.
    case center
    /// A third of the way across or down the display.
    case third
    /// The margin in from an edge.
    case margin
    /// An edge or the centre of another widget.
    case widget
  }

  /// A line the picture draws while the dragged widget lies on it, from `start` to `end` along it.
  struct Guide: Hashable, Sendable {
    var axis: Axis
    var position: CGFloat
    var start: CGFloat
    var end: CGFloat
    var kind: Kind
  }

  struct Result: Equatable, Sendable {
    /// How far the widget moves to lie on its guides.
    var offset: CGSize
    var guides: [Guide]
  }

  /// The pull, in the picture's points.
  static let threshold: CGFloat = 6

  /// The margin from each edge, as a fraction of the display's shorter side.
  static let marginFraction: CGFloat = 0.04

  /// The display's lines a dragged widget may lie on, drawn faintly while it is dragged so the
  /// centre can be found before the widget gets there.
  static func displayGuides(in size: CGSize) -> [Guide] {
    [
      Guide(axis: .vertical, position: size.width / 2, start: 0, end: size.height, kind: .center),
      Guide(axis: .horizontal, position: size.height / 2, start: 0, end: size.width, kind: .center),
    ]
  }

  /// Where `frame` snaps among `others` in a picture of `size`.
  static func snap(
    _ frame: CGRect, in size: CGSize, others: [CGRect], threshold: CGFloat = threshold
  ) -> Result {
    let margin = (min(size.width, size.height) * marginFraction).rounded()
    let x = axis(
      anchors: (frame.minX, frame.midX, frame.maxX), extent: size.width, margin: margin,
      others: others.map { (($0.minX, $0.midX, $0.maxX), $0.minY, $0.maxY) }, threshold: threshold)
    let y = axis(
      anchors: (frame.minY, frame.midY, frame.maxY), extent: size.height, margin: margin,
      others: others.map { (($0.minY, $0.midY, $0.maxY), $0.minX, $0.maxX) }, threshold: threshold)
    let moved = frame.offsetBy(dx: x.offset, dy: y.offset)
    let guides =
      x.lines.map { line in
        Guide(
          axis: .vertical, position: line.position,
          start: line.span.map { min($0.lower, moved.minY) } ?? 0,
          end: line.span.map { max($0.upper, moved.maxY) } ?? size.height, kind: line.kind)
      }
      + y.lines.map { line in
        Guide(
          axis: .horizontal, position: line.position,
          start: line.span.map { min($0.lower, moved.minX) } ?? 0,
          end: line.span.map { max($0.upper, moved.maxX) } ?? size.width, kind: line.kind)
      }
    return Result(offset: CGSize(width: x.offset, height: y.offset), guides: merged(guides))
  }

  // MARK: One axis

  private typealias Anchors = (min: CGFloat, mid: CGFloat, max: CGFloat)

  private enum Anchor { case min, mid, max }

  /// A line on one axis, and the other axis' span of the widget it belongs to (nil for the
  /// display's own lines, which cross the whole picture).
  private struct Line {
    var position: CGFloat
    var anchors: [Anchor]
    var kind: Kind
    var span: (lower: CGFloat, upper: CGFloat)?
  }

  private static func axis(
    anchors: Anchors, extent: CGFloat, margin: CGFloat,
    others: [(Anchors, CGFloat, CGFloat)], threshold: CGFloat
  ) -> (offset: CGFloat, lines: [Line]) {
    var lines = [
      Line(position: extent / 2, anchors: [.mid], kind: .center),
      Line(position: extent / 3, anchors: [.mid], kind: .third),
      Line(position: extent * 2 / 3, anchors: [.mid], kind: .third),
      Line(position: margin, anchors: [.min], kind: .margin),
      Line(position: extent - margin, anchors: [.max], kind: .margin),
    ]
    for (edges, lower, upper) in others {
      let span = (lower: lower, upper: upper)
      lines.append(Line(position: edges.min, anchors: [.min, .max], kind: .widget, span: span))
      lines.append(Line(position: edges.mid, anchors: [.mid], kind: .widget, span: span))
      lines.append(Line(position: edges.max, anchors: [.min, .max], kind: .widget, span: span))
    }
    func value(_ anchor: Anchor, moved offset: CGFloat = 0) -> CGFloat {
      offset + (anchor == .min ? anchors.min : anchor == .mid ? anchors.mid : anchors.max)
    }
    var best: CGFloat?
    for line in lines {
      for anchor in line.anchors {
        let distance = line.position - value(anchor)
        if abs(distance) <= threshold, abs(distance) < abs(best ?? .infinity) { best = distance }
      }
    }
    guard let offset = best else { return (0, []) }
    let met = lines.filter { line in
      line.anchors.contains { abs(line.position - value($0, moved: offset)) < 0.5 }
    }
    return (offset, met)
  }

  /// One guide per line: guides on the same line join into one spanning them all, and a widget's
  /// guide on a display line gives way to the display's.
  private static func merged(_ guides: [Guide]) -> [Guide] {
    var result: [Guide] = []
    for guide in guides {
      if let index = result.firstIndex(where: {
        $0.axis == guide.axis && abs($0.position - guide.position) < 0.5
      }) {
        var joined = result[index]
        joined.start = min(joined.start, guide.start)
        joined.end = max(joined.end, guide.end)
        if joined.kind == .widget { joined.kind = guide.kind }
        result[index] = joined
      } else {
        result.append(guide)
      }
    }
    return result
  }
}
