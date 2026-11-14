import AppKit
import SwiftUI
import XCTest

@testable import WallpaperMachine

/// The panel's type scale (`PanelFont`): its roles read as a hierarchy, none is too small to read,
/// and the AppKit code that measures the panel's text measures the font SwiftUI draws it in.
@MainActor
final class PanelFontTests: XCTestCase {
  private let roles: [(String, PanelFont)] = [
    ("pageTitle", .pageTitle), ("title", .title), ("headline", .headline),
    ("sectionHeader", .sectionHeader), ("body", .body), ("control", .control),
    ("controlSmall", .controlSmall), ("label", .label), ("callout", .callout),
    ("calloutStrong", .calloutStrong), ("footnote", .footnote), ("caption", .caption),
    ("badge", .badge), ("eyebrow", .eyebrow), ("mark", .mark),
  ]

  private func fitting<V: View>(_ view: V, width: CGFloat = 4000) -> CGSize {
    NSHostingController(rootView: view).sizeThatFits(in: NSSize(width: width, height: 4000))
  }

  private func heavier(_ a: PanelFont, than b: PanelFont) -> Bool {
    a.weight.appKit.rawValue > b.weight.appKit.rawValue
  }

  func testTheScaleReadsInOrderFromThePageTitleDownToATilesMark() {
    let descending: [PanelFont] = [
      .pageTitle, .title, .headline, .sectionHeader, .body, .label, .callout, .footnote, .caption,
      .eyebrow, .mark,
    ]
    for (larger, smaller) in zip(descending, descending.dropFirst()) {
      XCTAssertGreaterThanOrEqual(larger.size, smaller.size)
    }
    XCTAssertGreaterThan(PanelFont.pageTitle.size, PanelFont.title.size)
    XCTAssertGreaterThan(PanelFont.title.size, PanelFont.headline.size)
    XCTAssertGreaterThan(PanelFont.headline.size, PanelFont.sectionHeader.size)
    XCTAssertGreaterThan(PanelFont.caption.size, PanelFont.eyebrow.size)
    XCTAssertGreaterThan(PanelFont.eyebrow.size, PanelFont.mark.size)
    // A heading is never lighter than the text it heads, even where they share a size.
    for heading in [PanelFont.pageTitle, .title, .headline, .sectionHeader, .eyebrow] {
      XCTAssertTrue(heavier(heading, than: .body), "\(heading)")
    }
    XCTAssertTrue(heavier(.calloutStrong, than: .callout))
    XCTAssertTrue(heavier(.badge, than: .caption))
  }

  func testEveryRoleThatHoldsWordsIsAtLeastTenPoints() {
    for (name, role) in roles where name != "mark" {
      XCTAssertGreaterThanOrEqual(role.size, 10, name)
    }
    // The mark is a glyph on a disc, never words.
    XCTAssertGreaterThanOrEqual(PanelFont.mark.size, 9)
  }

  /// `LibraryCollectionLayout` and `ModifiedMark` lay out with AppKit what SwiftUI draws: a role's
  /// `nsFont` and `lineHeight` must be the size SwiftUI gives the same words in that role.
  func testWhatAppKitMeasuresIsWhatSwiftUIDraws() {
    let words = "Wallpaper Machine 0123"
    for (name, role) in roles {
      XCTAssertEqual(role.nsFont.pointSize, role.size, name)
      let drawn = fitting(Text(verbatim: words).font(.panel(role)).fixedSize())
      let measured = NSAttributedString(string: words, attributes: [.font: role.nsFont]).size()
      XCTAssertEqual(drawn.width, measured.width, accuracy: 1, name)
      XCTAssertEqual(drawn.height, role.lineHeight, accuracy: 1, name)
    }
  }

  func testAHeavierRoleDrawsWiderWordsThanALighterOneOfTheSameSize() {
    let words = "Wallpaper Machine"
    let regular = fitting(Text(verbatim: words).font(.panel(.callout)).fixedSize()).width
    let semibold = fitting(Text(verbatim: words).font(.panel(.calloutStrong)).fixedSize()).width
    XCTAssertGreaterThan(semibold, regular, "the weight reaches the drawn text")
  }

  func testTheEyebrowDrawsInCapitals() {
    let lower = fitting(Text(verbatim: "now playing").panelFont(.eyebrow).fixedSize()).width
    let upper = fitting(Text(verbatim: "NOW PLAYING").panelFont(.eyebrow).fixedSize()).width
    XCTAssertEqual(lower, upper, accuracy: 0.5)
    let plain = fitting(Text(verbatim: "now playing").panelFont(.caption).fixedSize()).width
    XCTAssertLessThan(plain, lower, "only a role that asks for capitals gets them")
  }

  func testAProportionalSizeFollowsTheGeometryItIsTakenFrom() {
    XCTAssertEqual(PanelFont.proportional(to: 40, ratio: 0.5).size, 20)
    XCTAssertEqual(PanelFont.proportional(to: 28, ratio: 0.5, weight: .medium).weight, .medium)
    XCTAssertEqual(PanelFont.body.scaled(by: 1.5).size, 19.5)
    XCTAssertEqual(PanelFont.body.scaled(by: 1.5).weight, PanelFont.body.weight)
  }

  /// A group heading has one size wherever it heads a group: an author's property group heading in
  /// the inspector draws its words as a Settings group's title does, and an author's own bold or
  /// heading runs only ever grow from there.
  func testAPropertyGroupHeadingIsSetLikeASettingsGroupTitle() {
    let words = "Colours and motion"
    let settingsTitle = fitting(Text(verbatim: words).font(.panel(.sectionHeader)).fixedSize())
    let heading = fitting(
      PropertyLabelView(document: .parse(words), role: .sectionHeader).fixedSize())
    XCTAssertEqual(heading.width, settingsTitle.width, accuracy: 1)
    XCTAssertEqual(heading.height, settingsTitle.height, accuracy: 1)
    let body = fitting(PropertyLabelView(document: .parse(words), role: .body).fixedSize())
    XCTAssertLessThan(body.width, heading.width, "a heading is heavier than a row's label")
    let bold = fitting(
      PropertyLabelView(document: .parse("<b>\(words)</b>"), role: .sectionHeader).fixedSize())
    XCTAssertGreaterThanOrEqual(bold.width, heading.width)
  }

  /// The Library grid sizes its cells before any tile is drawn (`LibraryCollectionLayout`); the
  /// height it reserves under the art must be the caption a tile draws, or captions are cut off or
  /// rows drift apart.
  func testTheLibraryGridReservesTheCaptionATileDraws() {
    let tile = WallpaperTile(title: "A wallpaper", subtitle: "Scene", kind: "Scene") {
      Color.gray
    }
    .frame(width: 180)
    XCTAssertEqual(
      fitting(tile, width: 180).height, 180 + LibraryCollectionLayout.captionHeight, accuracy: 1)
  }

  /// A property row keeps room for its pill measured in AppKit (`ModifiedMark.width`), so the pill
  /// must draw in the font it is measured in. `InspectorInputTests` checks the same in every
  /// language; this is the check beside the type scale, in the language the tests run in.
  func testAPropertyPillIsAsWideAsTheRoomItsRowKeepsForIt() {
    let slot = ModifiedMark.slotWidth()
    for kind in [ModifiedMark.Kind.modified, .notApplied] {
      let drawn = fitting(
        ModifiedMark(kind: kind).environment(\.locale, PanelLocale.shared.locale).fixedSize())
      XCTAssertEqual(drawn.width, ModifiedMark.width(kind), accuracy: 1, "\(kind)")
      XCTAssertEqual(ModifiedMark.width(kind) + ModifiedMark.reserve(for: kind), slot, "\(kind)")
    }
  }
}
