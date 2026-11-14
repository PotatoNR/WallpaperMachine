import AppKit
import Foundation
import Observation

/// One pane of the Desktop Widgets inspector, which shows the selected widget's controls a pane at a
/// time beside the canvas, so none of them is a long scroll away from the picture they change.
enum DesktopWidgetPane: String, CaseIterable, Identifiable, Sendable {
  /// What the widget says: its format, words, time zone, day.
  case content
  /// The letters: size, font, weight, spacing, case.
  case text
  /// The finished looks, the colours and the effects.
  case style
  /// Where it is: display, place, alignment and turn.
  case position

  var id: String { rawValue }

  /// The panes a widget of `kind` has: a battery and a month calendar say nothing of their own.
  static func panes(for kind: DesktopWidget.Kind) -> [DesktopWidgetPane] {
    switch kind {
    case .battery, .calendar: [.text, .style, .position]
    default: allCases
    }
  }
}

/// Page state of Settings › Desktop Widgets that must outlive the page being rebuilt: which widget the
/// editor shows, which pane of the inspector is open, and where a widget being dragged, resized or
/// turned on the canvas is before it is let go. It reads the widgets from
/// `controller.desktopWidgets` and acts through the controller's typed actions.
@MainActor
@Observable
final class DesktopWidgetsSettingsModel {
  typealias Screen = DesktopWidgetController.Screen

  /// A widget being dragged on the preview, where the pointer has taken it so far, and the guides
  /// it snapped to there; or one being resized or turned by its handles, with its size or turn so
  /// far.
  struct Drag: Equatable {
    var id: String
    var x: Double
    var y: Double
    var size: Int? = nil
    var rotation: Int? = nil
    var guides: [DesktopWidgetSnapping.Guide] = []
  }

  /// What a drag keeps from its start: where the widget was, its size and turn, and the frames of
  /// the widgets it can line up with, in the display's points.
  private struct DragStart {
    var id: String
    var x: Double
    var y: Double
    var size: Int
    var rotation: Int
    var others: [CGRect]
  }

  /// The inspector's pane the person chose last; a widget without it shows its first pane.
  var pane = DesktopWidgetPane.content

  /// The pane the inspector shows for `widget`.
  func pane(for widget: DesktopWidget) -> DesktopWidgetPane {
    let panes = DesktopWidgetPane.panes(for: widget.kind)
    return panes.contains(pane) ? pane : panes.first ?? .text
  }

  unowned let controller: PanelController
  private var chosenID: String?
  /// The drag in progress on the preview; nil when none is.
  var drag: Drag?
  @ObservationIgnored private var dragStart: DragStart?
  @ObservationIgnored private let formatters = DesktopWidgetRendering.Formatters()

  init(controller: PanelController) { self.controller = controller }

  var widgets: [DesktopWidget] { controller.desktopWidgets.widgets }

  /// Whether a click on the canvas's backdrop has put the selection away, so the canvas shows the
  /// widgets as the desktop will, with no outline or handles over them. Picking a widget ends it.
  private(set) var isSelectionCleared = false

  /// The widget the editor shows: the one chosen, else the first; none while the selection is
  /// cleared.
  var selected: DesktopWidget? { isSelectionCleared ? nil : lastChosen }

  /// The one chosen, else the first, also while the selection is cleared: the canvas stays on its
  /// display, and the search results keep editing it.
  var lastChosen: DesktopWidget? {
    let widgets = widgets
    return widgets.first { $0.id == chosenID } ?? widgets.first
  }

  var selectedID: String? { selected?.id }

  func select(_ id: String?) {
    chosenID = id
    isSelectionCleared = false
  }

  /// Selects nothing, to see the widgets without the selection drawn over them.
  func clearSelection() { isSelectionCleared = true }

  /// `widget` where the preview draws it: where a drag has it, at the size and turn its handles
  /// have it, or as it was let go while that is being saved.
  func shown(_ widget: DesktopWidget) -> DesktopWidget {
    var moved = widget
    moved.size = value(widget.id, "size", saved: widget.size)
    moved.rotation = value(widget.id, "rotation", saved: widget.rotation)
    if let drag, drag.id == widget.id {
      moved.x = drag.x
      moved.y = drag.y
      if let size = drag.size { moved.size = size }
      if let rotation = drag.rotation { moved.rotation = rotation }
    } else {
      let position = value(widget.id, "position", saved: [widget.x, widget.y])
      moved.x = position[0]
      moved.y = position[1]
    }
    return moved
  }

  // MARK: Displays

  /// The connected displays, the main one first.
  func screens() -> [Screen] {
    controller.desktopWidgetScreens().sorted { $0.isMain && !$1.isMain }
  }

  /// The display the preview shows for `widget`: its own when it has one and it is connected, else
  /// the main one.
  func previewScreen(for widget: DesktopWidget, among screens: [Screen]) -> Screen? {
    if case .display(let uuid, _) = widget.placement,
      let own = screens.first(where: { $0.uuid?.caseInsensitiveCompare(uuid) == .orderedSame }) {
      return own
    }
    return screens.first(where: \.isMain) ?? screens.first
  }

  /// The widgets the preview of `screen` draws, back to front as the desktop stacks them. The
  /// selected one is drawn while it is hidden too, so it can still be arranged; the picture fades
  /// it.
  func widgets(on screen: Screen) -> [DesktopWidget] {
    let selectedID = selectedID
    return widgets.reversed()
      .filter {
        ($0.isShown || $0.id == selectedID) && $0.isPlaced(onDisplayUUID: screen.uuid, isMain: screen.isMain)
      }
  }

  /// The Display menu: the main display, every display, each connected one by name, and the
  /// widget's own display when it is not connected.
  func placementOptions(for widget: DesktopWidget, among screens: [Screen]) -> [SettingsMenuOption<DesktopWidget.Placement>] {
    var options: [SettingsMenuOption<DesktopWidget.Placement>] = [
      .init(value: .main, title: L("Main display")),
      .init(value: .all, title: L("All displays")),
    ]
    for screen in screens {
      guard let uuid = screen.uuid else { continue }
      options.append(.init(value: .display(uuid: uuid, name: screen.name), title: screen.name))
    }
    if case .display(let uuid, let name) = widget.placement,
      !screens.contains(where: { $0.uuid?.caseInsensitiveCompare(uuid) == .orderedSame }) {
      options.append(.init(value: widget.placement, title: L("\(name) (not connected)")))
    }
    return options
  }

  /// The menu's value for the widget's display: a display chosen under an earlier name still
  /// selects its entry.
  func placementValue(for widget: DesktopWidget, among screens: [Screen]) -> DesktopWidget.Placement {
    guard case .display(let uuid, _) = widget.placement,
      let screen = screens.first(where: { $0.uuid?.caseInsensitiveCompare(uuid) == .orderedSame }),
      let own = screen.uuid
    else { return widget.placement }
    return .display(uuid: own, name: screen.name)
  }

  /// Where the widget is shown, for its line in the list.
  func placementTitle(for widget: DesktopWidget, among screens: [Screen]) -> String {
    let value = placementValue(for: widget, among: screens)
    return placementOptions(for: widget, among: screens).first { $0.value == value }?.title ?? ""
  }

  // MARK: Words

  /// What the widgets are drawn from now: this Mac's clock, language and region, the battery
  /// level the panel last read, and the sunrise and sunset settings.
  func inputs(at date: Date = Date()) -> DesktopWidgetRendering.Inputs {
    .init(
      date: date, calendar: .autoupdatingCurrent, locale: .autoupdatingCurrent,
      battery: controller.batteryPercent.map { BatteryReading(percent: $0, isDischarging: true) },
      solar: controller.automations.solar)
  }

  /// What the widget shows at `date`, as the desktop draws it, at `scale` times its size.
  func content(for widget: DesktopWidget, at date: Date = Date(), scale: CGFloat = 1)
    -> DesktopWidgetRendering.Content
  {
    DesktopWidgetRendering.content(for: widget, inputs: inputs(at: date), formatters: formatters, scale: scale)
  }

  /// What the widget says at `date`, on one line: the first line of a text widget, the month of
  /// a calendar, the time a clock face shows.
  func text(for widget: DesktopWidget, at date: Date = Date()) -> String {
    let text = DesktopWidgetRendering.text(for: widget, inputs: inputs(at: date), formatters: formatters)
    return text.split(whereSeparator: \.isNewline).first.map(String.init) ?? ""
  }

  /// The Date format menu, each style written out for today.
  func dateStyleOptions(for widget: DesktopWidget, at date: Date = Date()) -> [SettingsMenuOption<DesktopWidget.DateStyle>] {
    DesktopWidget.DateStyle.allCases.map { style in
      var sample = widget
      sample.dateStyle = style
      sample.text = ""
      return .init(value: style, title: text(for: sample, at: date))
    }
  }

  /// The Calendar menu: the region's own calendar, then the others by their names in the panel's
  /// language.
  func calendarOptions() -> [SettingsMenuOption<DesktopWidget.CalendarSystem>] {
    let locale = PanelLocale.shared.locale
    return DesktopWidget.CalendarSystem.allCases.map { system in
      guard let identifier = system.identifier else { return .init(value: system, title: L("Follow system")) }
      return .init(value: system, title: locale.localizedString(for: identifier) ?? "\(identifier)")
    }
  }

  /// The time zones the Time zone menu offers: one for each offset people live at, by a city in it.
  static let timeZones = [
    "Pacific/Honolulu", "America/Anchorage", "America/Los_Angeles", "America/Denver", "America/Chicago",
    "America/Mexico_City", "America/New_York", "America/Toronto", "America/Bogota", "America/Halifax",
    "America/Sao_Paulo", "America/Argentina/Buenos_Aires", "Atlantic/Reykjavik", "UTC", "Europe/London",
    "Europe/Lisbon", "Africa/Lagos", "Europe/Paris", "Europe/Berlin", "Europe/Madrid", "Europe/Rome",
    "Europe/Amsterdam", "Europe/Stockholm", "Europe/Athens", "Africa/Cairo", "Africa/Johannesburg",
    "Europe/Istanbul", "Europe/Moscow", "Africa/Nairobi", "Asia/Tehran", "Asia/Dubai", "Asia/Karachi",
    "Asia/Kolkata", "Asia/Kathmandu", "Asia/Dhaka", "Asia/Bangkok", "Asia/Jakarta", "Asia/Ho_Chi_Minh",
    "Asia/Shanghai", "Asia/Hong_Kong", "Asia/Taipei", "Asia/Singapore", "Asia/Manila", "Asia/Seoul",
    "Asia/Tokyo", "Australia/Perth", "Australia/Adelaide", "Australia/Brisbane", "Australia/Sydney",
    "Pacific/Auckland",
  ]

  /// The Time zone menu: this Mac's own, then each city by its offset from GMT now, and the
  /// widget's own zone when the list does not have it.
  func timeZoneOptions(for widget: DesktopWidget, at date: Date = Date()) -> [SettingsMenuOption<String?>] {
    var identifiers = Self.timeZones
    if let own = widget.timeZone, !identifiers.contains(own), DesktopWidget.validTimeZone(own) {
      identifiers.append(own)
    }
    let zones = identifiers.compactMap(TimeZone.init(identifier:))
      .sorted { ($0.secondsFromGMT(for: date), city($0.identifier)) < ($1.secondsFromGMT(for: date), city($1.identifier)) }
    return [.init(value: nil, title: L("Follow system"))]
      + zones.map { zone in
        .init(value: zone.identifier, title: "\(city(zone.identifier)) (\(offset(zone, at: date)))")
      }
  }

  /// A time zone's city in the panel's language, such as Tokyo for Asia/Tokyo.
  func city(_ identifier: String) -> String {
    guard identifier != "UTC", let zone = TimeZone(identifier: identifier) else { return identifier }
    let formatter = zoneFormatter
    formatter.locale = PanelLocale.shared.locale
    formatter.timeZone = zone
    formatter.dateFormat = "VVV"
    let name = formatter.string(from: Date())
    return name.isEmpty ? identifier : name
  }

  private func offset(_ zone: TimeZone, at date: Date) -> String {
    let formatter = zoneFormatter
    formatter.locale = PanelLocale.shared.locale
    formatter.timeZone = zone
    formatter.dateFormat = "O"
    return formatter.string(from: date)
  }

  @ObservationIgnored private let zoneFormatter = DateFormatter()

  /// The font families installed on this Mac, by name, without the system's hidden ones. The
  /// font manager is asked the first time the menu is drawn, not on every redraw; a font installed
  /// after that is offered once the app is opened again.
  func fontFamilies() -> [String] {
    if let families { return families }
    let found = NSFontManager.shared.availableFontFamilies
      .filter { !$0.hasPrefix(".") }
      .sorted { $0.localizedStandardCompare($1) == .orderedAscending }
    families = found
    return found
  }

  @ObservationIgnored private var families: [String]?

  /// A countdown's day as a date for the date picker: its start in this Mac's time zone, or
  /// today's for an unreadable day.
  func targetDate(_ day: String) -> Date {
    DesktopWidget.start(ofDay: day, in: .autoupdatingCurrent) ?? Calendar.autoupdatingCurrent.startOfDay(for: Date())
  }

  /// The still of the wallpaper on a display, for the preview's background; nil when it shows none.
  func wallpaperStill(on displayID: UInt32) -> PanelImageSource? {
    let row = controller.store.monitorInformationSnapshot.rows.first {
      $0.mirrorTargetDisplayId == nil
        && ResolvedDisplayTitles.liveDisplayID($0.displayId, title: $0.title) == displayID
    }
    guard let id = row?.wallpaperId, !id.isEmpty else { return nil }
    return controller.libraryRow(id: id)?.still
  }

  /// What the preview asks of a display's wallpaper for its frame. A new wallpaper or new files
  /// make a new request.
  struct FrameRequest: Hashable {
    var displayID: UInt32
    var wallpaperID: String
    var contentRevision: UInt64
  }

  /// What the preview has from a display's wallpaper for the request it answers: a frame or none,
  /// and whether it waits for the wallpaper to play past its intro for a settled one.
  struct WallpaperFrame {
    var request: FrameRequest
    var image: CGImage?
    var waitsToSettle = false
  }

  /// The longest edge, in pixels, of a frame the preview keeps: the canvas grows with the window, and
  /// this keeps it sharp on a Retina display up to about 1,000 points wide.
  static let framePixels = 2048

  /// What each display's wallpaper last gave the preview.
  private(set) var wallpaperFrames: [UInt32: WallpaperFrame] = [:]
  /// Waits before the wallpaper is asked again; tests pass one that does not wait.
  @ObservationIgnored var sleep: @Sendable (Duration) async throws -> Void = { try await Task.sleep(for: $0) }

  /// The request for the frame of the wallpaper on a display; nil while it shows none.
  func frameRequest(on displayID: UInt32) -> FrameRequest? {
    let rows = controller.store.monitorInformationSnapshot.rows.filter {
      ResolvedDisplayTitles.liveDisplayID($0.displayId, title: $0.title) == displayID
    }
    let row = rows.first { $0.mirrorTargetDisplayId == nil } ?? rows.first
    guard let id = row?.wallpaperId, !id.isEmpty else { return nil }
    return FrameRequest(
      displayID: displayID, wallpaperID: id, contentRevision: controller.store.wallpaperContentRevision)
  }

  /// What the preview of a display has from the wallpaper it shows now; nil before it answered,
  /// or when its answer was for the wallpaper before.
  private func currentFrame(on displayID: UInt32) -> WallpaperFrame? {
    guard let frame = wallpaperFrames[displayID],
      frame.request.wallpaperID == frameRequest(on: displayID)?.wallpaperID
    else { return nil }
    return frame
  }

  /// The frame the preview of a display draws behind its widgets: one of the wallpaper it shows
  /// now, its first until a settled one comes; nil otherwise, and the still stands in.
  func wallpaperFrame(on displayID: UInt32) -> CGImage? { currentFrame(on: displayID)?.image }

  /// Whether the preview of a display shows the still because its wallpaper has not played long
  /// enough for a frame past its intro or fade-in, and gave no first frame (or a blank one).
  func waitsForWallpaperToSettle(on displayID: UInt32) -> Bool {
    currentFrame(on: displayID).map { $0.image == nil && $0.waitsToSettle } ?? false
  }

  /// Asks the display's wallpaper for a frame: the preview's background is the desktop as it is,
  /// not the author's preview image. A wallpaper still in its intro shows its first frame at once
  /// and is asked again when it can have settled: after the rest of the settle window while it
  /// plays, else when it next starts playing where it can be seen (a wallpaper paused because the
  /// panel covers the desktop does not move on). The caller's task ends with the row, and the wait
  /// with it.
  func loadWallpaperFrame(_ request: FrameRequest) async {
    guard let read = controller.store.wallpaperFrame else { return }
    while !Task.isCancelled {
      let answer = await read(request.displayID, Self.framePixels)
      guard !Task.isCancelled else { return }
      switch answer {
      case .frame(let image):
        wallpaperFrames[request.displayID] = WallpaperFrame(request: request, image: image)
        return
      case .unavailable:
        wallpaperFrames[request.displayID] = WallpaperFrame(request: request, image: nil)
        return
      case .unsettled(let first, let retryAfter):
        // A later first frame replaces an earlier one; none keeps it.
        let shown = wallpaperFrames[request.displayID].flatMap { $0.request == request ? $0.image : nil }
        wallpaperFrames[request.displayID] = WallpaperFrame(
          request: request, image: first ?? shown, waitsToSettle: true)
        if let retryAfter {
          // A moment past the window, so the wallpaper has settled when it is asked.
          do { try await sleep(retryAfter + .milliseconds(250)) } catch { return }
        } else if let change = controller.store.wallpaperSettleChange {
          await change(request.displayID)
        } else {
          return
        }
      }
    }
  }

  // MARK: Editing

  /// The key a widget's control tracks its change under, for its draft and `isBusy`.
  static func key(_ id: String, _ control: String) -> String { "widget.\(id).\(control)" }

  /// Sends the change a control made, showing `value` until it has run. Returns the change's task,
  /// nil when a repeat was dropped.
  @discardableResult
  func commit<Value: Hashable>(
    _ id: String, _ control: String, to value: Value, policy: PanelActionCoordinator.Policy = .latestWins,
    _ change: @escaping (Value) -> DesktopWidgetChange
  ) -> Task<Void, Never>? {
    controller.settings.commit(Self.key(id, control), to: value, policy: policy) { [controller] value in
      try await controller.changeDesktopWidget(id, change(value))
    }
  }

  /// The value a control shows: what it just sent while that is on its way, otherwise `saved`.
  func value<Value: Hashable>(_ id: String, _ control: String, saved: Value) -> Value {
    controller.settings.value(Self.key(id, control), saved: saved)
  }

  /// Ends a drag on the preview where it was let go, and saves that position, or the size or turn
  /// a handle gave it. The draft shows it until it is saved, so the widget does not jump back
  /// meanwhile.
  @discardableResult
  func endDrag() -> Task<Void, Never>? {
    dragStart = nil
    guard let drag else { return nil }
    self.drag = nil
    if let size = drag.size { return commit(drag.id, "size", to: size) { .size($0) } }
    if let rotation = drag.rotation { return commit(drag.id, "rotation", to: rotation) { .rotation($0) } }
    return commit(drag.id, "position", to: [drag.x, drag.y]) { .position(x: $0[0], y: $0[1]) }
  }

  // MARK: Resizing and turning

  /// Keeps what a handle's drag starts from, and selects the widget.
  private func beginTransform(_ widget: DesktopWidget) -> DragStart {
    if let start = dragStart, start.id == widget.id, drag?.id == widget.id { return start }
    let shown = shown(widget)
    let start = DragStart(
      id: widget.id, x: shown.x, y: shown.y, size: shown.size, rotation: shown.rotation, others: [])
    dragStart = start
    if selectedID != widget.id { select(widget.id) }
    return start
  }

  /// Resizes a widget by a corner handle: its size at the start of the drag times `factor`, the
  /// pointer's distance from the widget's middle over its distance there at the start.
  func resize(_ widget: DesktopWidget, by factor: CGFloat) {
    let start = beginTransform(widget)
    drag = Drag(id: widget.id, x: start.x, y: start.y, size: Self.size(start.size, scaledBy: factor))
  }

  /// Turns a widget by its turn handle: its turn at the start of the drag plus `degrees`. With
  /// `snaps` the turn settles on a multiple of 15° within a few degrees of one.
  func rotate(_ widget: DesktopWidget, by degrees: CGFloat, snaps: Bool) {
    let start = beginTransform(widget)
    drag = Drag(
      id: widget.id, x: start.x, y: start.y,
      rotation: Self.rotation(CGFloat(start.rotation) + degrees, snaps: snaps))
  }

  /// Moves a widget by `points` of its display, as an arrow key on the canvas does, and saves it.
  @discardableResult
  func nudge(_ widget: DesktopWidget, by points: CGSize, on screen: Screen) -> Task<Void, Never>? {
    let display = screen.frame.size
    guard display.width > 0, display.height > 0 else { return nil }
    let shown = shown(widget)
    let x = min(max(shown.x + points.width / display.width, 0), 1)
    let y = min(max(shown.y + points.height / display.height, 0), 1)
    if selectedID != widget.id { select(widget.id) }
    return commit(widget.id, "position", to: [x, y]) { .position(x: $0[0], y: $0[1]) }
  }

  /// A size `factor` times `start`, in whole points inside the size's range.
  static func size(_ start: Int, scaledBy factor: CGFloat) -> Int {
    let range = DesktopWidget.sizeRange
    guard factor.isFinite, factor > 0 else { return start }
    return min(max(Int((CGFloat(start) * factor).rounded()), range.lowerBound), range.upperBound)
  }

  /// The snap of a turn: within this many degrees of a multiple of 15°, it goes there.
  static let rotationSnap: CGFloat = 4

  /// A turn of `degrees`, brought into −180° to 180° and whole degrees; with `snaps` it settles on
  /// a multiple of 15° within `rotationSnap` of one.
  static func rotation(_ degrees: CGFloat, snaps: Bool) -> Int {
    guard degrees.isFinite else { return 0 }
    var turn = degrees.truncatingRemainder(dividingBy: 360)
    if turn > 180 { turn -= 360 } else if turn < -180 { turn += 360 }
    if snaps {
      let nearest = (turn / 15).rounded() * 15
      if abs(nearest - turn) <= rotationSnap { turn = nearest }
    }
    let range = DesktopWidget.rotationRange
    return min(max(Int(turn.rounded()), range.lowerBound), range.upperBound)
  }

  /// The direction of `point` from `center` in a picture whose y grows downwards, in degrees
  /// clockwise from straight up, as a widget's turn is measured.
  static func angle(of point: CGPoint, around center: CGPoint) -> CGFloat {
    atan2(point.x - center.x, center.y - point.y) * 180 / .pi
  }

  // MARK: Ready-made widgets

  /// The display a ready-made widget is laid out for: the main one, or a common laptop's when none
  /// is known.
  func presetDisplay() -> CGSize {
    let screens = screens()
    let size = (screens.first(where: \.isMain) ?? screens.first)?.frame.size ?? .zero
    return size.width > 0 && size.height > 0 ? size : CGSize(width: 1512, height: 982)
  }

  /// A ready-made preset's widgets, placed on the main display as the desktop will draw them.
  func widgets(of preset: DesktopWidgetPreset, at date: Date = Date()) -> [DesktopWidget] {
    let display = presetDisplay()
    return preset.widgets(
      on: display, measure: { self.frame(of: $0, in: display, scale: 1).size }, city: { self.city($0) },
      today: date)
  }

  // MARK: Arranging

  /// Where `widget` lies in a picture of `size` drawn at `scale` times the display: its frame in
  /// the picture's points, top-left origin.
  func frame(of widget: DesktopWidget, in size: CGSize, scale: CGFloat) -> CGRect {
    let content = content(for: widget, scale: scale)
    let frame = DesktopWidgetRendering.frame(
      for: content, widget: widget, display: NSRect(origin: .zero, size: size))
    return CGRect(x: frame.minX, y: size.height - frame.maxY, width: frame.width, height: frame.height)
  }

  /// Moves a widget being dragged on the preview of `screen` (a picture of `size`, at `scale`
  /// times the display) by `translation` from where the drag started, and selects it. With `snaps`
  /// it lines up with the display's centre, thirds and margins and with the other widgets there
  /// when it comes within a few of the picture's points of one (`DesktopWidgetSnapping`). The lines
  /// are worked out on the display itself, where text is laid out at its own size, so a widget
  /// snapped to the centre is centred on the desktop to the point; the guides are scaled to the
  /// picture.
  func drag(
    _ widget: DesktopWidget, by translation: CGSize, in size: CGSize, scale: CGFloat, on screen: Screen,
    snaps: Bool
  ) {
    let display = screen.frame.size
    guard size.width > 0, size.height > 0, display.width > 0, display.height > 0, scale > 0 else { return }
    if dragStart?.id != widget.id || drag?.id != widget.id {
      let start = shown(widget)
      let others = widgets(on: screen).filter { $0.id != widget.id && $0.isShown }
        .map { frame(of: shown($0), in: display, scale: 1) }
      dragStart = DragStart(
        id: widget.id, x: start.x, y: start.y, size: start.size, rotation: start.rotation, others: others)
      if selectedID != widget.id { select(widget.id) }
    }
    guard let start = dragStart else { return }
    var moved = widget
    moved.size = start.size
    moved.rotation = start.rotation
    moved.x = min(max(start.x + translation.width / size.width, 0), 1)
    moved.y = min(max(start.y + translation.height / size.height, 0), 1)
    var guides: [DesktopWidgetSnapping.Guide] = []
    if snaps {
      let snapped = DesktopWidgetSnapping.snap(
        frame(of: moved, in: display, scale: 1), in: display, others: start.others,
        threshold: DesktopWidgetSnapping.threshold / scale)
      moved.x = min(max(moved.x + snapped.offset.width / display.width, 0), 1)
      moved.y = min(max(moved.y + snapped.offset.height / display.height, 0), 1)
      guides = snapped.guides.map { guide in
        var scaled = guide
        scaled.position *= scale
        scaled.start *= scale
        scaled.end *= scale
        return scaled
      }
    }
    drag = Drag(id: widget.id, x: moved.x, y: moved.y, guides: guides)
  }

  /// The position that centres `widget` on `screen` across (`horizontally`) or down: the middle of
  /// what it shows on the display's centre line, whichever edge its alignment holds.
  func centered(_ widget: DesktopWidget, on screen: Screen, horizontally: Bool) -> Double {
    guard horizontally else { return 0.5 }
    let display = screen.frame.size
    guard display.width > 0 else { return widget.x }
    let content = content(for: widget)
    let width = DesktopWidgetRendering.frame(
      for: content, widget: widget, display: NSRect(origin: .zero, size: display)
    ).width
    // A turned widget's frame is its turned box, which the position places without padding.
    let padding = content.look.rotation == 0 ? content.padding : 0
    let anchor: CGFloat =
      switch widget.alignment {
      case .leading: (display.width - width) / 2 + padding
      case .center: display.width / 2
      case .trailing: (display.width + width) / 2 - padding
      }
    return min(max(Double(anchor / display.width), 0), 1)
  }

  /// Whether `widget` is centred on `screen` across or down, to the display's point.
  func isCentered(_ widget: DesktopWidget, on screen: Screen, horizontally: Bool) -> Bool {
    let extent = horizontally ? screen.frame.width : screen.frame.height
    let position = horizontally ? widget.x : widget.y
    return abs(position - centered(widget, on: screen, horizontally: horizontally)) * extent < 1
  }
}
