import Foundation

/// One change a Settings › Desktop Widgets control makes to a widget.
enum DesktopWidgetChange: Hashable, Sendable {
  case shown(Bool)
  case placement(DesktopWidget.Placement)
  case size(Int)
  case position(x: Double, y: Double)
  case x(Double)
  case y(Double)
  case alignment(DesktopWidget.Alignment)
  case typeface(DesktopWidget.Typeface)
  case weight(Int)
  case color(String)
  case opacity(Int)
  case shadow(Bool)
  case timeFormat(DesktopWidget.TimeFormat)
  case showsSeconds(Bool)
  case dateStyle(DesktopWidget.DateStyle)
  case calendarSystem(DesktopWidget.CalendarSystem)
  case text(String)
  case targetDay(String)
  case sunStyle(DesktopWidget.SunStyle)
  case font(DesktopWidget.FontChoice)
  case italic(Bool)
  case letterSpacing(Int)
  case lineHeight(Int)
  case textCase(DesktopWidget.TextCase)
  case fill(DesktopWidget.Fill)
  case gradientColor(String)
  case gradientAngle(Int)
  case accentColor(String?)
  case outlineWidth(Int)
  case outlineColor(String)
  case glowSize(Int)
  case glowColor(String)
  case shadowColor(String)
  case shadowOpacity(Int)
  case shadowBlur(Int)
  case shadowDistance(Int)
  case shadowAngle(Int)
  case background(DesktopWidget.Background)
  case backgroundColor(String)
  case backgroundOpacity(Int)
  case backgroundPadding(Int)
  case rotation(Int)
  case padsHour(Bool)
  case showsPeriod(Bool)
  case clockLayout(DesktopWidget.ClockLayout)
  case dialMarks(DesktopWidget.DialMarks)
  case showsDialRing(Bool)
  /// A finished look from the Style menu.
  case style(DesktopWidget.StylePreset)
  /// The effects back to a new widget's.
  case resetEffects

  func apply(to widget: inout DesktopWidget) {
    switch self {
    case .shown(let value): widget.isShown = value
    case .placement(let value): widget.placement = value
    case .size(let value): widget.size = value
    case .position(let x, let y):
      widget.x = x
      widget.y = y
    case .x(let value): widget.x = value
    case .y(let value): widget.y = value
    case .alignment(let value): widget.alignment = value
    case .typeface(let value): widget.typeface = value
    case .weight(let value): widget.weight = value
    case .color(let value): widget.color = value
    case .opacity(let value): widget.opacity = value
    case .shadow(let value): widget.hasShadow = value
    case .timeFormat(let value): widget.timeFormat = value
    case .showsSeconds(let value): widget.showsSeconds = value
    case .dateStyle(let value): widget.dateStyle = value
    case .calendarSystem(let value): widget.calendarSystem = value
    case .text(let value): widget.text = value
    case .targetDay(let value): widget.targetDay = value
    case .sunStyle(let value): widget.sunStyle = value
    case .font(let value): widget.font = value
    case .italic(let value): widget.isItalic = value
    case .letterSpacing(let value): widget.letterSpacing = value
    case .lineHeight(let value): widget.lineHeight = value
    case .textCase(let value): widget.textCase = value
    case .fill(let value): widget.fill = value
    case .gradientColor(let value): widget.gradientColor = value
    case .gradientAngle(let value): widget.gradientAngle = value
    case .accentColor(let value): widget.accentColor = value
    case .outlineWidth(let value): widget.outlineWidth = value
    case .outlineColor(let value): widget.outlineColor = value
    case .glowSize(let value): widget.glowSize = value
    case .glowColor(let value): widget.glowColor = value
    case .shadowColor(let value): widget.shadowColor = value
    case .shadowOpacity(let value): widget.shadowOpacity = value
    case .shadowBlur(let value): widget.shadowBlur = value
    case .shadowDistance(let value): widget.shadowDistance = value
    case .shadowAngle(let value): widget.shadowAngle = value
    case .background(let value): widget.background = value
    case .backgroundColor(let value): widget.backgroundColor = value
    case .backgroundOpacity(let value): widget.backgroundOpacity = value
    case .backgroundPadding(let value): widget.backgroundPadding = value
    case .rotation(let value): widget.rotation = value
    case .padsHour(let value): widget.padsHour = value
    case .showsPeriod(let value): widget.showsPeriod = value
    case .clockLayout(let value): widget.clockLayout = value
    case .dialMarks(let value): widget.dialMarks = value
    case .showsDialRing(let value): widget.showsDialRing = value
    case .style(let preset): preset.apply(to: &widget)
    case .resetEffects: widget.resetEffects()
    }
  }
}

/// Settings › Desktop Widgets' actions. A widget belongs to no wallpaper and the renderer never draws it,
/// so none of them waits for a wallpaper command or clears an older banner.
extension PanelController {
  /// Adds a widget of `kind` on the main display, in front of the others, and opens it in the editor.
  func addDesktopWidget(_ kind: DesktopWidget.Kind) async throws {
    _ = try await run(.immediate) {
      let widget = try desktopWidgets.add(kind)
      widgetsSettings.select(widget.id)
    }
  }

  /// Adds a ready-made preset's widgets on the main display, in front of the others, and opens the
  /// first of them in the editor.
  func addDesktopWidgetPreset(_ preset: DesktopWidgetPreset) async throws {
    _ = try await run(.immediate) {
      let added = try desktopWidgets.add(widgetsSettings.widgets(of: preset))
      if let first = added.first { widgetsSettings.select(first.id) }
    }
  }

  func changeDesktopWidget(_ id: String, _ change: DesktopWidgetChange) async throws {
    _ = try await run(.immediate) {
      try desktopWidgets.update(id) { change.apply(to: &$0) }
    }
  }

  /// Moves a clock or a date to another time zone (nil for this Mac's own). A clock or a date
  /// without a label takes `label`, the city's name, so a world clock says whose time it tells.
  func setDesktopWidgetTimeZone(_ id: String, _ zone: String?, label: String?) async throws {
    _ = try await run(.immediate) {
      try desktopWidgets.update(id) { widget in
        widget.timeZone = zone
        if zone != nil, let label, widget.text.isEmpty, [.time, .date].contains(widget.kind) {
          widget.text = label
        }
      }
    }
  }

  /// Adds a copy of a widget in front of it and opens the copy in the editor.
  func duplicateDesktopWidget(_ id: String) async throws {
    _ = try await run(.immediate) {
      let copy = try desktopWidgets.duplicate(id)
      widgetsSettings.select(copy.id)
    }
  }

  /// Moves a widget to `index` of the layers, 0 being the front. `expected` is the order the list
  /// showed, so a drop on a list that changed since changes nothing.
  func moveDesktopWidget(_ id: String, to index: Int, expected: [String]? = nil) async throws {
    _ = try await run(.immediate) {
      try desktopWidgets.move(id, to: index, expected: expected)
    }
  }

  /// Removes a widget; the editor moves to the one listed after it, or before it when it was last.
  func removeDesktopWidget(_ id: String) async throws {
    _ = try await run(.immediate) {
      let ids = desktopWidgets.widgets.map(\.id)
      let wasSelected = widgetsSettings.selectedID == id
      try desktopWidgets.remove(id)
      if wasSelected, let index = ids.firstIndex(of: id) {
        let remaining = ids.filter { $0 != id }
        widgetsSettings.select(remaining.isEmpty ? nil : remaining[min(index, remaining.count - 1)])
      }
    }
  }
}
