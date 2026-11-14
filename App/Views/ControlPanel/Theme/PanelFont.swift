import AppKit
import SwiftUI

/// The panel's type scale: the size, weight, case and tracking of each kind of text, named for
/// what the text is (an inspector's title, a group heading, a caption) rather than for its size.
///
/// Text takes a role with `.font(.panel(.body))`, or `.panelFont(.eyebrow)` where the role also
/// sets the case and the tracking. AppKit code that measures text the panel draws reads the same
/// role's `nsFont` or `lineHeight`, so what is measured is what is drawn. A size that comes from a
/// control's geometry (a glyph in a disc, a symbol on a tile) is `proportional(to:ratio:weight:)`.
/// A rounded design is `Font.panel(_:design:)`, and figures that must not move are
/// `.monospacedDigit()` on the font.
///
/// The scale is the same in every tone, season and appearance, so it is not part of
/// `\.panelTheme`; it is read outside a view too (`LibraryCollectionLayout`).
struct PanelFont: Equatable, Sendable {
  enum Weight: Equatable, Sendable {
    case light, regular, medium, semibold, bold

    var font: Font.Weight {
      switch self {
      case .light: .light
      case .regular: .regular
      case .medium: .medium
      case .semibold: .semibold
      case .bold: .bold
      }
    }

    var appKit: NSFont.Weight {
      switch self {
      case .light: .light
      case .regular: .regular
      case .medium: .medium
      case .semibold: .semibold
      case .bold: .bold
      }
    }
  }

  let size: CGFloat
  let weight: Weight
  /// Drawn in capitals whatever case the words are written in.
  let isUppercase: Bool
  /// Extra space between letters, in points.
  let tracking: CGFloat

  private init(
    _ size: CGFloat, _ weight: Weight = .regular, isUppercase: Bool = false, tracking: CGFloat = 0
  ) {
    self.size = size
    self.weight = weight
    self.isUppercase = isUppercase
    self.tracking = tracking
  }

  // MARK: Roles

  /// The large title of a Settings or About page.
  static let pageTitle = PanelFont(22, .bold)
  /// An inspector's item title: the wallpaper or work it shows.
  static let title = PanelFont(17, .bold)
  /// A compact page title and the Now Playing title.
  static let headline = PanelFont(15, .semibold)
  /// The heading of a group of rows: a Settings group, the Workshop comments.
  static let sectionHeader = PanelFont(13, .semibold)
  /// Running text and row labels.
  static let body = PanelFont(13)
  /// The words of a regular or compact button.
  static let control = PanelFont(13, .medium)
  /// The words of a small button and of a chip.
  static let controlSmall = PanelFont(11, .medium)
  /// A capsule in a toolbar, a link-style action, the title of a check.
  static let label = PanelFont(12.5, .medium)
  /// Secondary lines: an item's facts, a notice, a comment.
  static let callout = PanelFont(12)
  /// A tile's title, a comment's author.
  static let calloutStrong = PanelFont(12, .semibold)
  /// A muted explanation under a control (`InspectorNote`).
  static let footnote = PanelFont(11.5)
  /// The smallest running text: a tile's kind, a date.
  static let caption = PanelFont(11)
  /// The words in a capsule badge.
  static let badge = PanelFont(11, .semibold)
  /// The small capitals over a title: Now Playing, Playlist, the menu bar panel's groups.
  static let eyebrow = PanelFont(10, .semibold, isUppercase: true, tracking: 0.4)
  /// The glyph of a mark over a tile's picture.
  static let mark = PanelFont(9.5, .bold)

  // MARK: Derived sizes

  /// The same role at `factor` times its size, as an author's heading or `<big>` text scales.
  func scaled(by factor: CGFloat) -> PanelFont {
    PanelFont(size * factor, weight, isUppercase: isUppercase, tracking: tracking)
  }

  /// The same role in another weight: the bold runs of an author's label.
  func weighted(_ weight: Weight) -> PanelFont {
    PanelFont(size, weight, isUppercase: isUppercase, tracking: tracking)
  }

  /// A size taken from a control's geometry: `ratio` of `side`, as a glyph fills a disc or a tile,
  /// and never under `minimum`.
  static func proportional(
    to side: CGFloat, ratio: CGFloat, weight: Weight = .regular, minimum: CGFloat = 0
  ) -> PanelFont {
    PanelFont(max(minimum, side * ratio), weight)
  }

  // MARK: AppKit

  /// The system font the role draws, for AppKit code that measures the panel's text.
  var nsFont: NSFont { NSFont.systemFont(ofSize: size, weight: weight.appKit) }

  /// The height of one line of the role, rounded up to a whole point as SwiftUI lays it out.
  var lineHeight: CGFloat {
    let font = nsFont
    return ceil(font.ascender - font.descender + font.leading)
  }
}

extension Font {
  /// The system font of a role of the panel's type scale (`PanelFont`). Case and tracking are
  /// not part of a `Font`; `View.panelFont(_:)` sets them too.
  static func panel(_ role: PanelFont, design: Font.Design = .default) -> Font {
    .system(size: role.size, weight: role.weight.font, design: design)
  }
}

extension View {
  /// Draws the text below in a role of the panel's type scale: its font, and its capitals and
  /// tracking where the role has them.
  func panelFont(_ role: PanelFont) -> some View {
    font(.panel(role))
      .transformEnvironment(\.textCase) { if role.isUppercase { $0 = .uppercase } }
      .tracking(role.tracking)
  }
}
