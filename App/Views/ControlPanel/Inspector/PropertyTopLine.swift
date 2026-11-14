import AppKit
import SwiftUI

/// The top line of a switch, choice or colour row: the label, its marks (Modified or Not applied,
/// Restore default) and the control.
///
/// They share one line while the label fits beside the marks and the control without wrapping.
/// Otherwise the control moves under the label, at the trailing edge, and the label takes the whole
/// width beside its marks: in the narrowest inspector a long author label then wraps between words
/// instead of being broken mid-word in a sliver of a column, and the control keeps its own width.
///
/// The choice always counts the wider of the two marks, whichever is shown or none (`reserve`,
/// `ModifiedMark.reserve(for:)`), so changing, applying or reverting a value never moves the
/// control from one line to the other under the pointer.
struct PropertyTopLineLayout: Layout {
  enum Part { case label, marks, control }

  /// Which part a subview is; a subview that does not say is the label.
  struct PartKey: LayoutValueKey {
    static let defaultValue = Part.label
  }

  /// The width counted beside the mark that is shown, so that a row's marks always count the widest
  /// mark when choosing the arrangement.
  var reserve: CGFloat = 0
  var spacing: CGFloat = 8
  var lineSpacing: CGFloat = 6

  /// Whether the label fits on one line beside the marks and the control in `width`.
  ///
  /// - Parameters:
  ///   - label: The label's width on one line.
  ///   - marks: The width of the marks shown, plus `reserve`.
  ///   - control: The control's own width; 0 for none, which always fits.
  static func fitsBeside(label: CGFloat, marks: CGFloat, control: CGFloat, spacing: CGFloat, width: CGFloat)
    -> Bool
  {
    guard control > 0 else { return true }
    let gaps = spacing * (marks > 0 ? 2 : 1)
    return label + gaps + marks + control <= width
  }

  /// Where each part goes for a width.
  fileprivate struct Arrangement {
    var size: CGSize
    var label: CGRect
    var marks: CGRect
    var control: CGRect
  }

  /// The parts' measurements, kept until a part changes (SwiftUI then makes a new cache).
  ///
  /// SwiftUI asks a row for its size several times in one layout pass, and lays the open inspector
  /// out again whenever anything in the window changes. Measuring the parts afresh each time (the
  /// control is often an AppKit slider) made the inspector most of the panel's main-thread time and
  /// dropped frames while the grid beside it scrolled.
  struct Cache {
    fileprivate var ideal: (label: CGSize, marks: CGSize, control: CGSize)?
    fileprivate var arrangements: [CGFloat: Arrangement] = [:]
  }

  func makeCache(subviews: Subviews) -> Cache { Cache() }

  private func parts(_ subviews: Subviews) -> (label: LayoutSubview?, marks: LayoutSubview?, control: LayoutSubview?) {
    (
      subviews.first { $0[PartKey.self] == .label }, subviews.first { $0[PartKey.self] == .marks },
      subviews.first { $0[PartKey.self] == .control }
    )
  }

  private func arrangement(width proposed: CGFloat?, _ subviews: Subviews, cache: inout Cache)
    -> Arrangement
  {
    let (label, marks, control) = parts(subviews)
    let measured =
      cache.ideal
      ?? (
        label?.sizeThatFits(.unspecified) ?? .zero, marks?.sizeThatFits(.unspecified) ?? .zero,
        control?.sizeThatFits(.unspecified) ?? .zero
      )
    cache.ideal = measured
    let (labelIdeal, marksSize, controlSize) = measured
    let marksGap = marksSize.width > 0 ? spacing : 0
    let controlGap = controlSize.width > 0 ? spacing : 0
    // No width, or an unbounded one, asks for the ideal size: everything on one line.
    let ideal = labelIdeal.width + marksGap + marksSize.width + controlGap + controlSize.width
    let width = proposed.map { $0.isFinite ? $0 : ideal } ?? ideal
    if let known = cache.arrangements[width] { return known }
    let made = arrangement(
      width: width, label: label, control: control, labelIdeal: labelIdeal, marksSize: marksSize,
      controlSize: controlSize)
    cache.arrangements[width] = made
    return made
  }

  private func arrangement(
    width: CGFloat, label: LayoutSubview?, control: LayoutSubview?, labelIdeal: CGSize,
    marksSize: CGSize, controlSize: CGSize
  ) -> Arrangement {
    let marksGap = marksSize.width > 0 ? spacing : 0
    let controlGap = controlSize.width > 0 ? spacing : 0
    let beside = Self.fitsBeside(
      label: labelIdeal.width, marks: marksSize.width + reserve, control: controlSize.width,
      spacing: spacing, width: width)

    if beside {
      let labelWidth = max(0, width - marksGap - marksSize.width - controlGap - controlSize.width)
      let labelHeight = label?.sizeThatFits(.init(width: labelWidth, height: nil)).height ?? 0
      let height = max(labelHeight, marksSize.height, controlSize.height)
      let controlX = width - controlSize.width
      let marksX = controlX - controlGap - marksSize.width
      return Arrangement(
        size: CGSize(width: width, height: height),
        label: CGRect(x: 0, y: (height - labelHeight) / 2, width: labelWidth, height: labelHeight),
        marks: CGRect(
          x: marksX, y: (height - marksSize.height) / 2, width: marksSize.width,
          height: marksSize.height),
        control: CGRect(
          x: controlX, y: (height - controlSize.height) / 2, width: controlSize.width,
          height: controlSize.height))
    }

    let labelWidth = max(0, width - marksGap - marksSize.width)
    let labelHeight = label?.sizeThatFits(.init(width: labelWidth, height: nil)).height ?? 0
    let firstLine = max(labelHeight, marksSize.height)
    let controlWidth = min(controlSize.width, width)
    let controlHeight =
      control?.sizeThatFits(.init(width: controlWidth, height: nil)).height ?? controlSize.height
    return Arrangement(
      size: CGSize(width: width, height: firstLine + lineSpacing + controlHeight),
      label: CGRect(x: 0, y: (firstLine - labelHeight) / 2, width: labelWidth, height: labelHeight),
      marks: CGRect(
        x: width - marksSize.width, y: (firstLine - marksSize.height) / 2,
        width: marksSize.width, height: marksSize.height),
      control: CGRect(
        x: width - controlWidth, y: firstLine + lineSpacing, width: controlWidth,
        height: controlHeight))
  }

  func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout Cache) -> CGSize {
    arrangement(width: proposal.width, subviews, cache: &cache).size
  }

  func placeSubviews(
    in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout Cache
  ) {
    let arrangement = arrangement(width: bounds.width, subviews, cache: &cache)
    let (label, marks, control) = parts(subviews)
    func place(_ subview: LayoutSubview?, _ frame: CGRect) {
      subview?.place(
        at: CGPoint(x: bounds.minX + frame.minX, y: bounds.minY + frame.minY), anchor: .topLeading,
        proposal: ProposedViewSize(frame.size))
    }
    place(label, arrangement.label)
    place(marks, arrangement.marks)
    place(control, arrangement.control)
  }
}

/// The pill beside a property's label (`PropertyRow.mark`): **Modified** while the saved value
/// differs from the author's default, **Not applied** while the value waits for Apply changes.
/// Not applied is an outline with a dot, the way macOS marks an unsaved document, so the two read
/// apart at a glance; its help says how to apply or undo it.
struct ModifiedMark: View {
  typealias Kind = InspectorOptions.PropertyRow.Mark

  var kind = Kind.modified

  private static let fontSize: CGFloat = 10.5
  private static let inset: CGFloat = 6
  private static let dot: CGFloat = 5
  private static let dotSpacing: CGFloat = 4

  @Environment(\.panelTheme) private var theme

  /// The pill's width in the panel's language. The words are measured as that language, as the
  /// catalog's text is drawn: the language picks the glyphs (Japanese kanji are narrower than the
  /// same characters measured without it).
  @MainActor
  static func width(_ kind: Kind) -> CGFloat {
    let font = NSFont.systemFont(ofSize: fontSize, weight: .semibold)
    let language = NSAttributedString.Key(kCTLanguageAttributeName as String)
    let text = NSAttributedString(
      string: kind == .notApplied ? L("Not applied") : L("Modified"),
      attributes: [.font: font, language: PanelLocale.shared.tag])
    let dotWidth = kind == .notApplied ? dot + dotSpacing : 0
    return (text.size().width + dotWidth + inset * 2).rounded(.up)
  }

  /// The room a row keeps for its mark: the wider of the two pills, so a row going from Modified to
  /// Not applied, to none or back never moves its control from one line to the other.
  @MainActor
  static func slotWidth() -> CGFloat { max(width(.modified), width(.notApplied)) }

  /// What a row counts beside the mark it shows (`PropertyTopLineLayout.reserve`), so that the two
  /// together always come to `slotWidth()`.
  ///
  /// - Parameter spacing: The gap the row draws after a shown mark, before what follows it (Restore
  ///   default); with no mark there is no gap, so the reserve counts it too.
  @MainActor
  static func reserve(for mark: Kind?, followedBy spacing: CGFloat = 0) -> CGFloat {
    slotWidth() + spacing - (mark.map { width($0) + spacing } ?? 0)
  }

  var body: some View {
    // Only Not applied has something to explain; Modified carries no empty help.
    if kind == .notApplied {
      pill.help(L("Not applied yet. Apply changes saves it; Revert undoes it."))
    } else {
      pill
    }
  }

  private var pill: some View {
    let accent = theme.accent.accent.color
    return HStack(spacing: Self.dotSpacing) {
      if kind == .notApplied {
        Circle().fill(accent).frame(width: Self.dot, height: Self.dot).accessibilityHidden(true)
        Text("Not applied")
      } else {
        Text("Modified")
      }
    }
    .font(.system(size: Self.fontSize, weight: .semibold))
    .lineLimit(1)
    .fixedSize(horizontal: true, vertical: false)
    .foregroundStyle(accent)
    .padding(.horizontal, Self.inset)
    .frame(minHeight: 16)
    .background(kind == .modified ? accent.opacity(0.14) : .clear, in: Capsule())
    .overlay {
      // The accent's text colour at full strength: a hairline in it keeps graphic contrast on
      // every surface, which a faded one does not.
      if kind == .notApplied { Capsule().strokeBorder(accent, lineWidth: 0.75) }
    }
  }
}
