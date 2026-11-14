import AppKit
import SwiftUI
import XCTest

@testable import WallpaperMachine

/// Settings › Desktop Widgets: adding, editing, arranging and removing the desktop's clocks and dates. The
/// page edits the panel's own store over the fixture's preferences, so nothing reaches the desktop.
@MainActor
final class WidgetsSettingsTests: PanelTestCase {
  typealias Screen = DesktopWidgetController.Screen

  private let laptop = Screen(
    displayID: 1, uuid: "AAAA-1", name: "Built-in Display",
    frame: NSRect(x: 0, y: 0, width: 1512, height: 982), isMain: true)
  private let external = Screen(
    displayID: 2, uuid: "BBBB-2", name: "Studio Display",
    frame: NSRect(x: 1512, y: 0, width: 2560, height: 1440), isMain: false)

  func testAddingOpensTheNewWidgetAndRemovingMovesToTheNextOne() async throws {
    try await withPanel { panel in
      let controller = panel.controller
      let model = controller.widgetsSettings
      XCTAssertNil(model.selected)

      try await controller.addDesktopWidget(.time)
      try await controller.addDesktopWidget(.date)
      try await controller.addDesktopWidget(.time)
      let ids = model.widgets.map(\.id)
      XCTAssertEqual(model.widgets.map(\.kind), [.time, .date, .time])
      XCTAssertEqual(model.selectedID, ids[0], "a new widget opens in the editor, at the top of the list")

      model.select(ids[1])
      try await controller.removeDesktopWidget(ids[1])
      XCTAssertEqual(model.selectedID, ids[2], "the one after it")
      try await controller.removeDesktopWidget(ids[2])
      XCTAssertEqual(model.selectedID, ids[0], "the one before the last")

      XCTAssertEqual(
        DesktopWidgetStore(defaults: panel.defaults).widgets.map(\.id), [ids[0]], "every change is kept")
    }
  }

  func testTheListIsTheLayersAndThePreviewStacksThemSo() async throws {
    try await withPanel { panel in
      let controller = panel.controller
      controller.desktopWidgetScreens = { [laptop] in [laptop] }
      let model = controller.widgetsSettings
      try await controller.addDesktopWidget(.time)
      try await controller.addDesktopWidget(.date)
      try await controller.addDesktopWidget(.text)
      let ids = model.widgets.map(\.id)
      XCTAssertEqual(model.widgets(on: laptop).map(\.id), ids.reversed(), "drawn back to front")

      try await controller.moveDesktopWidget(ids[2], to: 0, expected: ids)
      XCTAssertEqual(model.widgets.map(\.id), [ids[2], ids[0], ids[1]])
      try await controller.moveDesktopWidget(ids[0], to: 2, expected: ids)
      XCTAssertEqual(model.widgets.map(\.id), [ids[2], ids[0], ids[1]], "a drop from an older order is refused")

      try await controller.duplicateDesktopWidget(ids[1])
      let copy = try XCTUnwrap(model.selectedID)
      XCTAssertEqual(model.widgets.map(\.id), [ids[2], ids[0], copy, ids[1]], "the copy, in front of it, opens")

      try await controller.changeDesktopWidget(copy, .shown(false))
      XCTAssertTrue(model.widgets(on: laptop).contains { $0.id == copy }, "the selected one is drawn while hidden")
      model.select(ids[0])
      XCTAssertFalse(model.widgets(on: laptop).contains { $0.id == copy }, "another hidden one is not")
    }
  }

  /// A click on the canvas's wallpaper selects nothing, to see the widgets as the desktop will:
  /// no outline, no handles, no hidden widget, on the same display; picking a widget ends it.
  func testClearingTheSelectionShowsTheDesktopAsItWillLookUntilAWidgetIsPicked() async throws {
    try await withPanel { panel in
      let controller = panel.controller
      controller.desktopWidgetScreens = { [laptop, external] in [laptop, external] }
      let model = controller.widgetsSettings
      try await controller.addDesktopWidget(.time)
      try await controller.addDesktopWidget(.date)
      let ids = model.widgets.map(\.id)
      try await controller.changeDesktopWidget(ids[0], .placement(.display(uuid: "BBBB-2", name: "Studio Display")))
      try await controller.changeDesktopWidget(ids[0], .shown(false))
      model.select(ids[0])
      XCTAssertEqual(model.widgets(on: external).map(\.id), [ids[0]], "the selected one is drawn while hidden")

      model.clearSelection()
      XCTAssertNil(model.selected)
      XCTAssertNil(model.selectedID, "no outline or handles, and the arrow keys move nothing")
      XCTAssertEqual(model.widgets(on: external), [], "a hidden widget is not drawn, as on the desktop")
      XCTAssertEqual(model.lastChosen?.id, ids[0], "the canvas stays on its display")
      XCTAssertEqual(
        model.lastChosen.flatMap { model.previewScreen(for: $0, among: model.screens()) }?.uuid, external.uuid)
      XCTAssertNotEqual(
        WidgetsSettingsSection.unofferedItems(controller), Set(WidgetsSettingsSection.editorItems.map(\.id)),
        "search results keep editing the widget chosen last")

      model.select(ids[1])
      XCTAssertEqual(model.selectedID, ids[1], "picking a widget selects it again")
      model.clearSelection()
      try await controller.addDesktopWidget(.text)
      XCTAssertEqual(model.selectedID, model.widgets.first?.id, "a new widget opens in the editor")
    }
  }

  func testDraggingSnapsToTheCenterUnlessCommandIsHeldAndTheCenterButtonsCenter() async throws {
    try await withPanel { panel in
      let controller = panel.controller
      controller.desktopWidgetScreens = { [laptop] in [laptop] }
      let model = controller.widgetsSettings
      try await controller.addDesktopWidget(.text)
      let id = try XCTUnwrap(model.selectedID)
      await model.commit(id, "alignment", to: DesktopWidget.Alignment.leading) { .alignment($0) }?.value
      await model.commit(id, "position", to: [0.1, 0.1]) { .position(x: $0[0], y: $0[1]) }?.value
      let widget = try XCTUnwrap(model.selected)
      let size = CGSize(width: 480, height: 480 * laptop.frame.height / laptop.frame.width)
      let scale = size.width / laptop.frame.width

      // Within a few of the picture's points of the centre, measured on the display.
      let display = laptop.frame.size
      let start = model.frame(of: widget, in: display, scale: 1)
      let near = CGSize(
        width: (display.width / 2 - start.midX) * scale + 3, height: (display.height / 2 - start.midY) * scale - 4)
      model.drag(widget, by: near, in: size, scale: scale, on: laptop, snaps: true)
      var frame = model.frame(of: model.shown(widget), in: display, scale: 1)
      XCTAssertEqual(frame.midX, display.width / 2, accuracy: 1, "on the desktop's vertical centre line")
      XCTAssertEqual(frame.midY, display.height / 2, accuracy: 1, "and its horizontal one")
      let guides = try XCTUnwrap(model.drag?.guides)
      XCTAssertEqual(Set(guides.map(\.kind)), [.center])
      XCTAssertEqual(
        guides.first { $0.axis == .vertical }?.position ?? 0, size.width / 2, accuracy: 1, "drawn on the picture")

      model.drag(widget, by: near, in: size, scale: scale, on: laptop, snaps: false)
      frame = model.frame(of: model.shown(widget), in: display, scale: 1)
      XCTAssertEqual(frame.midX, display.width / 2 + 3 / scale, accuracy: 1, "Command places it freely")
      XCTAssertEqual(model.drag?.guides, [])
      await model.endDrag()?.value

      var saved = try XCTUnwrap(model.selected)
      XCTAssertFalse(model.isCentered(saved, on: laptop, horizontally: true))
      try await controller.changeDesktopWidget(id, .x(model.centered(saved, on: laptop, horizontally: true)))
      try await controller.changeDesktopWidget(id, .y(model.centered(saved, on: laptop, horizontally: false)))
      saved = try XCTUnwrap(model.selected)
      XCTAssertTrue(model.isCentered(saved, on: laptop, horizontally: true))
      XCTAssertTrue(model.isCentered(saved, on: laptop, horizontally: false))
      let content = model.content(for: saved)
      let onDisplay = DesktopWidgetRendering.frame(
        textSize: content.size, padding: content.padding, widget: saved,
        display: NSRect(origin: .zero, size: laptop.frame.size))
      XCTAssertEqual(onDisplay.midX, laptop.frame.width / 2, accuracy: 1, "a left-aligned text centred by its middle")
      XCTAssertEqual(onDisplay.midY, laptop.frame.height / 2, accuracy: 1)
    }
  }

  /// The canvas's handles: a corner resizes about the middle and a knob turns, both shown while they
  /// move and saved when let go; a turn snaps to 15° unless Command is held; an arrow key nudges.
  func testTheCanvasHandlesResizeAndTurnAWidgetAndTheArrowKeysNudgeIt() async throws {
    try await withPanel { panel in
      let controller = panel.controller
      controller.desktopWidgetScreens = { [laptop] in [laptop] }
      let model = controller.widgetsSettings
      try await controller.addDesktopWidget(.time)
      let id = try XCTUnwrap(model.selectedID)
      var widget = try XCTUnwrap(model.selected)
      XCTAssertEqual(widget.size, 96)

      model.resize(widget, by: 1.5)
      model.resize(widget, by: 1.25)
      XCTAssertEqual(model.shown(widget).size, 120, "from the size at the start, not the last step")
      XCTAssertEqual(model.drag?.guides, [], "no snapping guides while resizing")
      XCTAssertEqual(model.selected?.size, 96, "nothing is saved before it is let go")
      await model.endDrag()?.value
      widget = try XCTUnwrap(model.selected)
      XCTAssertEqual(widget.size, 120)
      model.resize(widget, by: 100)
      XCTAssertEqual(model.shown(widget).size, DesktopWidget.sizeRange.upperBound)
      model.resize(widget, by: 0)
      XCTAssertEqual(model.shown(widget).size, 120, "a factor that means nothing changes nothing")
      await model.endDrag()?.value

      model.rotate(widget, by: 43, snaps: true)
      XCTAssertEqual(model.shown(widget).rotation, 45, "settles on 45°")
      model.rotate(widget, by: 43, snaps: false)
      XCTAssertEqual(model.shown(widget).rotation, 43, "Command turns it freely")
      model.rotate(widget, by: 200, snaps: false)
      XCTAssertEqual(model.shown(widget).rotation, -160, "past half a turn it goes the other way")
      await model.endDrag()?.value
      widget = try XCTUnwrap(model.selected)
      XCTAssertEqual(widget.rotation, -160)
      XCTAssertEqual(widget.size, 120, "turning keeps the size")

      let center = CGPoint(x: 100, y: 100)
      XCTAssertEqual(DesktopWidgetsSettingsModel.angle(of: CGPoint(x: 100, y: 0), around: center), 0, accuracy: 0.01)
      XCTAssertEqual(DesktopWidgetsSettingsModel.angle(of: CGPoint(x: 200, y: 100), around: center), 90, accuracy: 0.01)
      XCTAssertEqual(
        abs(DesktopWidgetsSettingsModel.angle(of: CGPoint(x: 100, y: 200), around: center)), 180, accuracy: 0.01,
        "clockwise from straight up in a picture whose y grows downwards")

      let x = widget.x, y = widget.y
      await model.nudge(widget, by: CGSize(width: 10, height: -1), on: laptop)?.value
      widget = try XCTUnwrap(model.selected)
      XCTAssertEqual(widget.x, x + 10 / laptop.frame.width, accuracy: 1e-9)
      XCTAssertEqual(widget.y, y - 1 / laptop.frame.height, accuracy: 1e-9)
      XCTAssertEqual(widget.id, id)
    }
  }

  /// Every ready-made widget adds valid widgets on the main display, front first and opened in the
  /// editor; a group is laid out without its widgets covering each other, and one that would pass
  /// the limit adds nothing.
  func testReadyMadeWidgetsAddFinishedWidgetsLaidOutTogether() async throws {
    try await withPanel { panel in
      let controller = panel.controller
      controller.desktopWidgetScreens = { [laptop] in [laptop] }
      let model = controller.widgetsSettings
      let display = laptop.frame.size
      for preset in DesktopWidgetPreset.allCases {
        let widgets = model.widgets(of: preset)
        XCTAssertFalse(widgets.isEmpty, "\(preset)")
        XCTAssertTrue(widgets.allSatisfy(\.isValid), "\(preset)")
        let frames = widgets.map { model.frame(of: $0, in: display, scale: 1) }
        for (index, frame) in frames.enumerated() {
          XCTAssertTrue(
            NSRect(origin: .zero, size: display).insetBy(dx: -1, dy: -1).contains(frame), "\(preset) on the display")
          for other in frames[(index + 1)...] {
            XCTAssertLessThan(
              frame.intersection(other).width * frame.intersection(other).height, 4, "\(preset) does not overlap")
          }
        }
      }
      let world = model.widgets(of: .worldClocks)
      XCTAssertEqual(world.map(\.timeZone), DesktopWidgetPreset.worldClockZones)
      XCTAssertEqual(world.map(\.text), DesktopWidgetPreset.worldClockZones.map(model.city), "each says its city")
      XCTAssertEqual(world.map(\.x), world.map(\.x).sorted(), "west to east")

      try await controller.addDesktopWidget(.text)
      try await controller.addDesktopWidgetPreset(.clockAndDate)
      XCTAssertEqual(model.widgets.map(\.kind), [.time, .date, .text], "in front, in the preset's order")
      XCTAssertEqual(model.selectedID, model.widgets.first?.id, "the first opens in the editor")
      XCTAssertEqual(Set(model.widgets.map(\.id)).count, 3)
      XCTAssertEqual(DesktopWidgetStore(defaults: panel.defaults).widgets.count, 3, "kept")

      while model.widgets.count < DesktopWidgetStore.limit - 1 {
        try await controller.addDesktopWidget(.battery)
      }
      do {
        try await controller.addDesktopWidgetPreset(.worldClocks)
        XCTFail("three clocks do not fit in one place")
      } catch {
        XCTAssertEqual(error as? DesktopWidgetError, .tooMany)
      }
      XCTAssertEqual(model.widgets.count, DesktopWidgetStore.limit - 1, "none of them is added")
    }
  }

  /// A sample's wallpaper fills its card and stays inside it, whatever the wallpaper's shape, so a
  /// card never spills over the one beside it.
  func testASamplesWallpaperStaysInsideItsCard() throws {
    for (width, height) in [(400, 100), (100, 400)] {
      let context = try XCTUnwrap(
        CGContext(
          data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
          space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
      let image = try XCTUnwrap(context.makeImage())
      let hosting = NSHostingController(
        rootView: AnyView(
          WidgetSampleBackdrop(image: image).environment(\.panelTheme, PanelTheme(appearance: .dark))))
      hosting.sizingOptions = []
      let size = hosting.sizeThatFits(in: NSSize(width: 160, height: 100))
      XCTAssertEqual(size.width, 160, accuracy: 0.5, "\(width)x\(height)")
      XCTAssertEqual(size.height, 100, accuracy: 0.5, "\(width)x\(height)")
    }
  }

  /// The inspector shows one pane at a time; a widget without the pane chosen shows its first.
  func testTheInspectorShowsThePaneChosenOrTheWidgetsFirst() async throws {
    try await withPanel { panel in
      let controller = panel.controller
      let model = controller.widgetsSettings
      try await controller.addDesktopWidget(.battery)
      let battery = try XCTUnwrap(model.selected)
      try await controller.addDesktopWidget(.time)
      let clock = try XCTUnwrap(model.selected)
      XCTAssertEqual(DesktopWidgetPane.panes(for: .battery), [.text, .style, .position], "a battery says nothing of its own")
      XCTAssertEqual(DesktopWidgetPane.panes(for: .time), DesktopWidgetPane.allCases)
      XCTAssertEqual(model.pane(for: clock), .content)
      XCTAssertEqual(model.pane(for: battery), .text)
      model.pane = .position
      XCTAssertEqual(model.pane(for: battery), .position)
      XCTAssertEqual(model.pane(for: clock), .position)
      XCTAssertEqual(
        Set(WidgetsSettingsSection.searchOrder), Set(DesktopWidgetPane.allCases), "search results show every pane")
    }
  }

  func testTheControlsChangeAWidgetWithoutWaitingForTheRenderer() async throws {
    try await withPanel { panel in
      let controller = panel.controller
      XCTAssertTrue(controller.settings.isUnavailable, "no renderer snapshot yet")
      try await controller.addDesktopWidget(.time)
      let model = controller.widgetsSettings
      let id = try XCTUnwrap(model.selectedID)

      await model.commit(id, "size", to: 140) { .size($0) }?.value
      await model.commit(id, "color", to: "#FF8000") { .color($0) }?.value
      await model.commit(id, "seconds", to: true, policy: .dropDuplicates) { .showsSeconds($0) }?.value
      model.drag = .init(id: id, x: 0.1, y: 0.9)
      XCTAssertEqual(model.shown(try XCTUnwrap(model.selected)).x, 0.1, "the preview follows the drag")
      await model.endDrag()?.value
      XCTAssertNil(model.drag)

      let widget = try XCTUnwrap(model.selected)
      XCTAssertEqual(widget.size, 140)
      XCTAssertEqual(widget.color, "#FF8000")
      XCTAssertTrue(widget.showsSeconds)
      XCTAssertEqual(widget.x, 0.1)
      XCTAssertEqual(widget.y, 0.9)
    }
  }

  func testTheEditorsRowsAreOfferedOnlyForAWidgetOfTheirKind() async throws {
    try await withPanel { panel in
      let controller = panel.controller
      let editor = Set(WidgetsSettingsSection.editorItems.map(\.id))
      XCTAssertEqual(WidgetsSettingsSection.unofferedItems(controller), editor, "nothing to edit yet")
      XCTAssertFalse(SettingsRegistry.unofferedItems(controller).contains(WidgetsSettingsSection.add.id))

      typealias Section = WidgetsSettingsSection
      let kindRows = Set(Section.kindRows.keys)
      let lettering: Set<String> = [Section.letterSpacing.id, Section.textCase.id]
      let expected: [DesktopWidget.Kind: Set<String>] = [
        .time: lettering.union([
          Section.lineHeight.id, Section.timeFormat.id, Section.clockLayout.id, Section.padsHour.id,
          Section.showsPeriod.id, Section.seconds.id, Section.timeZone.id, Section.label.id,
        ]),
        .date: lettering.union([Section.dateFormat.id, Section.calendarSystem.id, Section.timeZone.id, Section.label.id]),
        .text: lettering.union([Section.lineHeight.id, Section.content.id]),
        .countdown: lettering.union([Section.event.id, Section.targetDay.id]),
        .greeting: lettering.union([Section.name.id]),
        .battery: lettering,
        .sun: lettering.union([Section.sunStyle.id, Section.timeFormat.id]),
        .analog: [Section.accent.id, Section.dialMarks.id, Section.dialRing.id, Section.seconds.id, Section.timeZone.id],
        .calendar: lettering.union([Section.accent.id]),
      ]
      // A new widget has a shadow, a solid fill and no outline, glow or background.
      let waiting: Set<String> = [
        Section.gradientColor.id, Section.gradientAngle.id, Section.outlineColor.id, Section.glowColor.id,
        Section.backgroundColor.id, Section.backgroundOpacity.id, Section.backgroundPadding.id,
      ]
      for kind in DesktopWidget.Kind.allCases {
        try await controller.addDesktopWidget(kind)
        XCTAssertEqual(
          WidgetsSettingsSection.unofferedItems(controller),
          kindRows.subtracting(expected[kind] ?? []).union(waiting), "\(kind)")
        let widget = try XCTUnwrap(controller.widgetsSettings.selected)
        XCTAssertFalse(controller.widgetsSettings.text(for: widget).isEmpty, "\(kind) says something in the list")
      }
    }
  }

  func testTheTimeZoneMenuOffersCitiesAndLabelsAClockWithTheCityChosen() async throws {
    try await withPanel { panel in
      let controller = panel.controller
      try await controller.addDesktopWidget(.time)
      let model = controller.widgetsSettings
      let id = try XCTUnwrap(model.selectedID)
      var widget = try XCTUnwrap(model.selected)
      let options = model.timeZoneOptions(for: widget)
      XCTAssertNil(options.first?.value, "this Mac's own first")
      XCTAssertTrue(options.contains { $0.value == "Asia/Tokyo" })
      XCTAssertEqual(Set(options.map(\.title)).count, options.count, "each city reads differently")

      try await controller.setDesktopWidgetTimeZone(id, "Asia/Tokyo", label: model.city("Asia/Tokyo"))
      XCTAssertEqual(model.selected?.text, model.city("Asia/Tokyo"), "a world clock says whose time it is")
      try await controller.changeDesktopWidget(id, .text("Home"))
      try await controller.setDesktopWidgetTimeZone(id, "America/Argentina/Ushuaia", label: "Ushuaia")
      widget = try XCTUnwrap(model.selected)
      XCTAssertEqual(widget.text, "Home", "a label of one's own stays")
      XCTAssertEqual(widget.timeZone, "America/Argentina/Ushuaia")
      XCTAssertEqual(
        model.timeZoneOptions(for: widget).filter { $0.value == "America/Argentina/Ushuaia" }.count, 1,
        "a zone the list lacks is still offered")
      XCTAssertEqual(
        model.calendarOptions().map(\.value), DesktopWidget.CalendarSystem.allCases, "every calendar by name")
      XCTAssertEqual(Set(model.calendarOptions().map(\.title)).count, DesktopWidget.CalendarSystem.allCases.count)
    }
  }

  /// The preview's background is a settled frame of the display's wallpaper, shown only while that
  /// wallpaper is still the one shown; otherwise the still stands in.
  func testThePreviewShowsTheFrameTheDisplaysWallpaperDrew() async throws {
    try await withPanel { panel in
      let model = panel.controller.widgetsSettings
      Self.show("aurora", in: panel)
      let drawn = try Self.picture()
      var asked: [(UInt32, Int)] = []
      panel.store.wallpaperFrame = { display, pixels in
        asked.append((display, pixels))
        return .frame(drawn)
      }

      XCTAssertNil(model.frameRequest(on: 2), "a display without a wallpaper asks nothing")
      let request = try XCTUnwrap(model.frameRequest(on: 1))
      XCTAssertNil(model.wallpaperFrame(on: 1), "the still until the frame comes")
      await model.loadWallpaperFrame(request)
      XCTAssertTrue(model.wallpaperFrame(on: 1) === drawn)
      XCTAssertFalse(model.waitsForWallpaperToSettle(on: 1))
      XCTAssertEqual(asked.map(\.0), [1])
      XCTAssertEqual(asked.map(\.1), [DesktopWidgetsSettingsModel.framePixels])

      Self.show("rain", in: panel)
      XCTAssertNil(model.wallpaperFrame(on: 1), "a frame of the wallpaper before is not shown")
      XCTAssertNotEqual(model.frameRequest(on: 1), request, "the new wallpaper is asked again")
    }
  }

  /// A wallpaper still in its intro shows its first frame at once and is asked once more when it
  /// can have settled, whose frame then replaces it; without a first frame the still shows with a
  /// note under it. One that does not play is asked again once it plays.
  func testAWallpaperInItsIntroShowsItsFirstFrameThenItsSettledOne() async throws {
    try await withPanel { panel in
      let model = panel.controller.widgetsSettings
      Self.show("aurora", in: panel)
      let first = try Self.picture(), settled = try Self.picture()
      var answers: [DesktopWallpaperFrames.Answer] = [
        .unsettled(first: first, retryAfter: .seconds(9)), .frame(settled),
      ]
      panel.store.wallpaperFrame = { _, _ in answers.removeFirst() }
      var waits: [Duration] = []
      var shownWhileWaiting: CGImage?
      var notedWhileWaiting = true
      model.sleep = { duration in
        await MainActor.run {
          waits.append(duration)
          shownWhileWaiting = model.wallpaperFrame(on: 1)
          notedWhileWaiting = model.waitsForWallpaperToSettle(on: 1)
        }
      }

      await model.loadWallpaperFrame(try XCTUnwrap(model.frameRequest(on: 1)))
      XCTAssertTrue(shownWhileWaiting === first, "the first frame at once")
      XCTAssertFalse(notedWhileWaiting, "no note over a frame")
      XCTAssertEqual(waits.count, 1)
      XCTAssertGreaterThanOrEqual(waits.first ?? .zero, .seconds(9))
      XCTAssertTrue(model.wallpaperFrame(on: 1) === settled, "then the settled one")

      answers = [.unsettled(first: nil, retryAfter: nil)]
      waits = []
      Self.show("rain", in: panel)
      await model.loadWallpaperFrame(try XCTUnwrap(model.frameRequest(on: 1)))
      XCTAssertNil(model.wallpaperFrame(on: 1))
      XCTAssertTrue(model.waitsForWallpaperToSettle(on: 1), "the still, with its note")
      XCTAssertEqual(waits, [], "a wallpaper that does not play is not waited for")

      // Paused because the panel covers the desktop: asked again once it has played.
      answers = [.unsettled(first: nil, retryAfter: nil), .frame(settled)]
      var changes = 0
      panel.store.wallpaperSettleChange = { display in
        XCTAssertEqual(display, 1)
        changes += 1
      }
      Self.show("snow", in: panel)
      await model.loadWallpaperFrame(try XCTUnwrap(model.frameRequest(on: 1)))
      XCTAssertEqual(changes, 1)
      XCTAssertTrue(model.wallpaperFrame(on: 1) === settled)
    }
  }

  private static func show(_ wallpaper: String, in panel: PanelFixture) {
    panel.store.monitorInformationSnapshot = BridgeMonitorInformationSnapshot(rows: [
      BridgeMonitorInfoRow(
        displayId: "1", title: "Built-in Display (1 - Primary)", wallpaperId: wallpaper,
        wallpaperTitle: wallpaper, mirrorTargetDisplayId: nil, mirrorTargetTitle: nil,
        scalingMode: "fill", targetFps: "30", audioResponse: false)
    ])
  }

  private static func picture() throws -> CGImage {
    try XCTUnwrap(
      CGContext(
        data: nil, width: 4, height: 2, bitsPerComponent: 8, bytesPerRow: 0,
        space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)?
        .makeImage())
  }

  func testTheDisplayMenuOffersEveryDisplayAndKeepsOneThatIsNotConnected() async throws {
    try await withPanel { panel in
      let controller = panel.controller
      let both = [external, laptop]
      controller.desktopWidgetScreens = { both }
      try await controller.addDesktopWidget(.time)
      let model = controller.widgetsSettings
      let id = try XCTUnwrap(model.selectedID)
      let screens = model.screens()
      XCTAssertEqual(screens.map(\.displayID), [1, 2], "the main display first")

      var widget = try XCTUnwrap(model.selected)
      XCTAssertEqual(
        model.placementOptions(for: widget, among: screens).map(\.title),
        ["Main display", "All displays", "Built-in Display", "Studio Display"])
      XCTAssertEqual(model.previewScreen(for: widget, among: screens)?.displayID, 1)

      try await controller.changeDesktopWidget(id, .placement(.display(uuid: "bbbb-2", name: "Old name")))
      widget = try XCTUnwrap(model.selected)
      XCTAssertEqual(
        model.placementValue(for: widget, among: screens), .display(uuid: "BBBB-2", name: "Studio Display"),
        "a display chosen under another name still selects its entry")
      XCTAssertEqual(model.placementTitle(for: widget, among: screens), "Studio Display")
      XCTAssertEqual(model.previewScreen(for: widget, among: screens)?.displayID, 2)

      let one = [laptop]
      controller.desktopWidgetScreens = { one }
      let options = model.placementOptions(for: widget, among: model.screens())
      XCTAssertEqual(options.last?.title, "Old name (not connected)")
      XCTAssertEqual(options.last?.value, widget.placement)
      XCTAssertEqual(model.widgets(on: laptop).count, 0, "it is not drawn on another display")
    }
  }

  func testTheDateFormatMenuWritesEveryStyleOut() async throws {
    try await withPanel { panel in
      try await panel.controller.addDesktopWidget(.date)
      let model = panel.controller.widgetsSettings
      try await panel.controller.changeDesktopWidget(try XCTUnwrap(model.selectedID), .text("Paris"))
      let widget = try XCTUnwrap(model.selected)
      let titles = model.dateStyleOptions(for: widget).map(\.title)
      XCTAssertFalse(titles.contains { $0.hasPrefix("Paris") }, "the menu shows the style, not the label")
      XCTAssertEqual(titles.count, DesktopWidget.DateStyle.allCases.count)
      XCTAssertEqual(Set(titles).count, titles.count, "each style reads differently")
      XCTAssertFalse(titles.contains(""))
    }
  }

  func testASearchFindsTheWidgetsPageByWhatItAdds() async throws {
    try await withPanel { panel in
      let settings = panel.controller.settings
      settings.query = "Clock"
      XCTAssertTrue(settings.search.shows(WidgetsSettingsSection.add))
      settings.query = "Countdown"
      XCTAssertTrue(settings.search.shows(WidgetsSettingsSection.add), "by every kind it adds")
      XCTAssertFalse(settings.search.shows(WidgetsSettingsSection.size), "no widget, no editor")
      settings.query = "World clocks"
      XCTAssertTrue(settings.search.shows(WidgetsSettingsSection.readyMade), "by every ready-made widget")
      settings.query = ""
    }
  }

  // MARK: Layout

  private func settle(_ hosting: NSHostingController<AnyView>, _ window: NSWindow, at size: NSSize) {
    window.setContentSize(size)
    window.layoutIfNeeded()
    hosting.view.layoutSubtreeIfNeeded()
    RunLoop.current.run(until: Date().addingTimeInterval(0.06))
    hosting.view.layoutSubtreeIfNeeded()
  }

  /// With `WALLPAPER_MACHINE_WIDGET_SNAPSHOTS` set to a folder, writes the workspace there for a
  /// person to look at: empty, with ready-made widgets in each pane, wide and narrow.
  func testSnapshotsOnRequest() async throws {
    guard let folder = ProcessInfo.processInfo.environment["WALLPAPER_MACHINE_WIDGET_SNAPSHOTS"]
    else { throw XCTSkip("set WALLPAPER_MACHINE_WIDGET_SNAPSHOTS to write snapshots") }
    let url = URL(fileURLWithPath: folder, isDirectory: true)
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    try await withPanel { panel in
      let controller = panel.controller
      controller.desktopWidgetScreens = { [laptop] in [laptop] }
      Self.show("aurora", in: panel)
      let wallpaper = try Self.wallpaper()
      panel.store.wallpaperFrame = { _, _ in .frame(wallpaper) }
      let hosting = NSHostingController(
        rootView: AnyView(
          SettingsPages().environment(controller)
            .panelTheme(theme: controller.theme, locale: PanelLocale.shared)))
      hosting.sizingOptions = []
      let window = ControlPanelWindow.make(contentViewController: hosting, delegate: nil)
      defer {
        window.contentViewController = nil
        window.close()
      }
      controller.settings.select(.widgets)
      @MainActor func write(_ name: String, _ size: NSSize) async throws {
        settle(hosting, window, at: size)
        try await Task.sleep(for: .milliseconds(300))
        settle(hosting, window, at: size)
        let view = hosting.view
        let rep = try XCTUnwrap(view.bitmapImageRepForCachingDisplay(in: view.bounds))
        view.cacheDisplay(in: view.bounds, to: rep)
        try XCTUnwrap(rep.representation(using: .png, properties: [:]))
          .write(to: url.appendingPathComponent("\(name).png"))
      }
      try await write("empty-wide", NSSize(width: 1020, height: 760))
      try await controller.addDesktopWidgetPreset(.worldClocks)
      try await controller.addDesktopWidgetPreset(.monthCalendar)
      try await controller.addDesktopWidgetPreset(.clockAndDate)
      for pane in DesktopWidgetPane.allCases {
        controller.widgetsSettings.pane = pane
        try await write("wide-\(pane)", NSSize(width: 1020, height: 760))
      }
      let selected = try XCTUnwrap(controller.widgetsSettings.selected)
      controller.widgetsSettings.rotate(selected, by: 14, snaps: true)
      try await write("wide-turning", NSSize(width: 1020, height: 760))
      controller.widgetsSettings.endDrag()
      controller.widgetsSettings.clearSelection()
      try await write("wide-none-selected", NSSize(width: 1020, height: 760))
      controller.widgetsSettings.select(selected.id)
      controller.widgetsSettings.pane = .style
      try await write("narrow-style", NSSize(width: 540, height: 700))
      controller.settings.query = "shadow"
      try await write("search", NSSize(width: 1020, height: 760))
      controller.settings.query = ""
    }
  }

  /// A wallpaper-like gradient, wider than the laptop, as a wallpaper of another shape than the
  /// cards it is drawn in.
  private static func wallpaper() throws -> CGImage {
    let context = try XCTUnwrap(
      CGContext(
        data: nil, width: 1200, height: 491, bitsPerComponent: 8, bytesPerRow: 0,
        space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
    let colors = [CGColor(red: 0.12, green: 0.2, blue: 0.45, alpha: 1), CGColor(red: 0.85, green: 0.45, blue: 0.4, alpha: 1)]
    let gradient = try XCTUnwrap(
      CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors as CFArray, locations: [0, 1]))
    context.drawLinearGradient(gradient, start: .zero, end: CGPoint(x: 300, y: 491), options: [])
    return try XCTUnwrap(context.makeImage())
  }

  func testThePageLaysOutInTheNarrowestAndTheWidestColumnWithAndWithoutWidgets() async throws {
    try await withPanel { panel in
      let controller = panel.controller
      let both = [external, laptop]
      controller.desktopWidgetScreens = { both }
      let hosting = NSHostingController(
        rootView: AnyView(
          SettingsPages().environment(controller)
            .panelTheme(theme: controller.theme, locale: PanelLocale.shared)))
      hosting.sizingOptions = []
      let window = ControlPanelWindow.make(contentViewController: hosting, delegate: nil)
      defer {
        window.contentViewController = nil
        window.close()
        PanelLocale.shared.bind(to: .testHost)
      }
      controller.settings.select(.widgets)
      for state in ["empty", "widgets", "none selected"] {
        if state == "none selected" { controller.widgetsSettings.clearSelection() }
        if state == "widgets" {
          try await controller.addDesktopWidget(.date)
          try await controller.addDesktopWidget(.time)
          try await controller.addDesktopWidget(.calendar)
          try await controller.addDesktopWidget(.analog)
          try await controller.addDesktopWidget(.countdown)
        }
        for language in ["en", "ja"] {
          PanelLocale.shared.bind(
            to: AppLanguageStore(defaults: try TemporaryDefaults.make(for: self).defaults, systemLanguages: [language]))
          // The workspace beside and under the canvas, and every pane of the inspector.
          let sizes = [NSSize(width: 460, height: 560), NSSize(width: 980, height: 800), NSSize(width: 1400, height: 900)]
          for size in sizes {
            for pane in state == "widgets" ? DesktopWidgetPane.allCases : [.content] {
              controller.widgetsSettings.pane = pane
              settle(hosting, window, at: size)
              let context = "\(state) \(language) \(Int(size.width)) \(pane)"
              let least = hosting.sizeThatFits(in: NSSize(width: 0, height: size.height))
              XCTAssertLessThanOrEqual(least.width, size.width, "\(context): too wide")
              let taken = hosting.sizeThatFits(in: size)
              XCTAssertEqual(taken.width, size.width, accuracy: 1, "\(context): takes the width it is given")
            }
          }
        }
      }
      XCTAssertFalse(window.isVisible, "layout stays off screen")
    }
  }
}
