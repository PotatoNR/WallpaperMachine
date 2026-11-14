import CoreGraphics
import XCTest

@testable import WallpaperMachine

/// Where a widget dragged on the Arrange picture snaps to, and the guides drawn while it does.
final class DesktopWidgetSnappingTests: XCTestCase {
  typealias Snapping = DesktopWidgetSnapping

  private let picture = CGSize(width: 480, height: 300)

  func testAWidgetNearTheCenterSnapsOntoBothCenterLines() {
    let frame = CGRect(x: 240 - 50 + 4, y: 150 - 20 - 5, width: 100, height: 40)
    let result = Snapping.snap(frame, in: picture, others: [])
    XCTAssertEqual(result.offset, CGSize(width: -4, height: 5))
    XCTAssertEqual(Set(result.guides.map(\.axis)), [.vertical, .horizontal])
    XCTAssertTrue(result.guides.allSatisfy { $0.kind == .center })
    let vertical = result.guides.first { $0.axis == .vertical }
    XCTAssertEqual(vertical?.position, 240)
    XCTAssertEqual(vertical?.start, 0, "a display line crosses the whole picture")
    XCTAssertEqual(vertical?.end, 300)
  }

  func testAWidgetBeyondThePullStaysWhereItIs() {
    let frame = CGRect(x: 240 - 50 + 20, y: 60, width: 100, height: 40)
    let result = Snapping.snap(frame, in: picture, others: [])
    XCTAssertEqual(result.offset, .zero)
    XCTAssertEqual(result.guides, [])
  }

  func testTheNearestLineWinsAndThirdsAndMarginsPullToo() {
    let third = Snapping.snap(CGRect(x: 160 - 30 + 2, y: 200, width: 60, height: 20), in: picture, others: [])
    XCTAssertEqual(third.offset.width, -2)
    XCTAssertEqual(third.guides.first { $0.axis == .vertical }?.kind, .third)

    let margin = (min(picture.width, picture.height) * Snapping.marginFraction).rounded()
    let edge = Snapping.snap(CGRect(x: margin + 3, y: 200, width: 60, height: 20), in: picture, others: [])
    XCTAssertEqual(edge.offset.width, -3, "the left edge onto the margin")
    XCTAssertEqual(edge.guides.first { $0.axis == .vertical }?.kind, .margin)
  }

  func testAWidgetLinesUpWithAnotherOnesEdgesAndGuidesSpanBoth() {
    let other = CGRect(x: 60, y: 40, width: 120, height: 30)
    let frame = CGRect(x: 63, y: 200, width: 80, height: 20)
    let result = Snapping.snap(frame, in: picture, others: [other])
    XCTAssertEqual(result.offset.width, -3, "left edges line up")
    let guide = result.guides.first { $0.axis == .vertical }
    XCTAssertEqual(guide?.kind, .widget)
    XCTAssertEqual(guide?.position, 60)
    XCTAssertEqual(guide?.start, 40, "from the other widget")
    XCTAssertEqual(guide?.end, 220, "to the dragged one")

    let after = Snapping.snap(CGRect(x: 183, y: 200, width: 80, height: 20), in: picture, others: [other])
    XCTAssertEqual(after.offset.width, -3, "a left edge onto the other's right edge")
  }

  func testTheFaintCenterLinesCrossThePicture() {
    let lines = Snapping.displayGuides(in: picture)
    XCTAssertEqual(lines.map(\.position).sorted(), [150, 240])
    XCTAssertTrue(lines.allSatisfy { $0.kind == .center })
  }
}
