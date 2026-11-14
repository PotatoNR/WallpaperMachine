import Foundation

/// A ready-made widget, or a few widgets that belong together (a clock over its date, three world
/// clocks in a row), finished and placed, so a person can put one on the desktop in a click and
/// change anything about it afterwards. Adding one adds ordinary widgets: nothing remembers the
/// preset they came from.
enum DesktopWidgetPreset: String, CaseIterable, Sendable {
    case bigClock, clockAndDate, neonClock, clockFace, worldClocks, lunarDate, monthCalendar, countdown
    case greeting, note, status

    /// How the preset's widgets sit together around the group's place.
    enum Arrangement: Equatable, Sendable {
        /// One under another, `gap` display points apart, the group's middle at the place.
        case column(gap: CGFloat)
        /// Side by side, `gap` display points apart, the group's middle at the place.
        case row(gap: CGFloat)
    }

    /// The preset's widgets, front first, before they are placed, and where the group goes.
    struct Layout {
        var widgets: [DesktopWidget]
        var arrangement: Arrangement
        /// The group's place, as fractions of the display: `x` is where each widget's alignment
        /// edge goes in a column, the row's middle in a row; `y` is the group's vertical middle.
        var x: Double
        var y: Double
    }

    /// The cities of the world clocks, west to east.
    static let worldClockZones = ["America/New_York", "Europe/London", "Asia/Tokyo"]

    /// The preset's widgets and their place. `city` names a time zone's city in the panel's
    /// language, for the world clocks' labels; `today` and `calendar` choose a countdown's day.
    func layout(
        city: (String) -> String, today: Date = Date(), calendar: Calendar = .autoupdatingCurrent
    ) -> Layout {
        func widget(_ kind: DesktopWidget.Kind, _ change: (inout DesktopWidget) -> Void) -> DesktopWidget {
            var widget = DesktopWidget(kind: kind, today: today, calendar: calendar)
            change(&widget)
            return widget
        }
        switch self {
        case .bigClock:
            let clock = widget(.time) {
                $0.size = 160
                $0.weight = 200
            }
            return Layout(widgets: [clock], arrangement: .column(gap: 0), x: 0.5, y: 0.28)
        case .clockAndDate:
            let clock = widget(.time) {
                $0.size = 128
                $0.weight = 200
            }
            let date = widget(.date) {
                $0.size = 22
                $0.weight = 600
                $0.textCase = .uppercase
                $0.letterSpacing = 12
            }
            return Layout(widgets: [clock, date], arrangement: .column(gap: 0), x: 0.5, y: 0.3)
        case .neonClock:
            let clock = widget(.time) {
                $0.size = 120
                $0.weight = 300
                $0.typeface = .rounded
                DesktopWidget.StylePreset.neon.apply(to: &$0)
            }
            return Layout(widgets: [clock], arrangement: .column(gap: 0), x: 0.5, y: 0.3)
        case .clockFace:
            let face = widget(.analog) {
                $0.size = 110
                $0.dialMarks = .minutes
                DesktopWidget.StylePreset.glass.apply(to: &$0)
            }
            return Layout(widgets: [face], arrangement: .column(gap: 0), x: 0.5, y: 0.32)
        case .worldClocks:
            let clocks = Self.worldClockZones.map { zone in
                widget(.time) {
                    $0.size = 22
                    $0.weight = 500
                    $0.timeZone = zone
                    $0.text = city(zone)
                    DesktopWidget.StylePreset.badge.apply(to: &$0)
                }
            }
            return Layout(widgets: clocks, arrangement: .row(gap: 16), x: 0.5, y: 0.86)
        case .lunarDate:
            let date = widget(.date) {
                $0.size = 30
                $0.weight = 400
                $0.typeface = .serif
                $0.calendarSystem = .chinese
            }
            return Layout(widgets: [date], arrangement: .column(gap: 0), x: 0.5, y: 0.36)
        case .monthCalendar:
            let month = widget(.calendar) {
                $0.size = 15
                $0.alignment = .trailing
                DesktopWidget.StylePreset.badge.apply(to: &$0)
            }
            return Layout(widgets: [month], arrangement: .column(gap: 0), x: 0.95, y: 0.24)
        case .countdown:
            let countdown = widget(.countdown) {
                $0.size = 28
                $0.weight = 600
                DesktopWidget.StylePreset.glass.apply(to: &$0)
            }
            return Layout(widgets: [countdown], arrangement: .column(gap: 0), x: 0.5, y: 0.8)
        case .greeting:
            let greeting = widget(.greeting) {
                $0.size = 56
                $0.weight = 300
                $0.typeface = .serif
                $0.isItalic = true
            }
            let date = widget(.date) {
                $0.size = 20
                $0.weight = 500
            }
            return Layout(widgets: [greeting, date], arrangement: .column(gap: 4), x: 0.5, y: 0.45)
        case .note:
            let note = widget(.text) {
                $0.size = 40
                $0.weight = 500
                $0.typeface = .serif
                $0.isItalic = true
                DesktopWidget.StylePreset.sunset.apply(to: &$0)
            }
            return Layout(widgets: [note], arrangement: .column(gap: 0), x: 0.5, y: 0.62)
        case .status:
            let battery = widget(.battery) {
                $0.size = 18
                $0.weight = 600
                $0.alignment = .leading
            }
            let sun = widget(.sun) {
                $0.size = 18
                $0.sunStyle = .both
                $0.alignment = .leading
            }
            return Layout(widgets: [battery, sun], arrangement: .column(gap: 2), x: 0.04, y: 0.9)
        }
    }

    /// The preset's widgets placed on a display of `display` size, front first. `measure` gives a
    /// widget's frame size on that display, which the arrangement spaces them by; every position
    /// stays on the display.
    func widgets(
        on display: CGSize, measure: (DesktopWidget) -> CGSize, city: (String) -> String,
        today: Date = Date(), calendar: Calendar = .autoupdatingCurrent
    ) -> [DesktopWidget] {
        Self.place(layout(city: city, today: today, calendar: calendar), on: display, measure: measure)
    }

    /// Places a layout's widgets on a display of `display` size.
    static func place(_ layout: Layout, on display: CGSize, measure: (DesktopWidget) -> CGSize) -> [DesktopWidget] {
        guard display.width > 0, display.height > 0 else { return layout.widgets }
        var widgets = layout.widgets
        let sizes = widgets.map(measure)
        switch layout.arrangement {
        case .column(let gap):
            let total = sizes.map(\.height).reduce(0, +) + gap * CGFloat(max(widgets.count - 1, 0))
            var top = CGFloat(layout.y) * display.height - total / 2
            for index in widgets.indices {
                widgets[index].x = layout.x
                widgets[index].y = Double((top + sizes[index].height / 2) / display.height)
                top += sizes[index].height + gap
            }
        case .row(let gap):
            let total = sizes.map(\.width).reduce(0, +) + gap * CGFloat(max(widgets.count - 1, 0))
            var left = CGFloat(layout.x) * display.width - total / 2
            for index in widgets.indices {
                widgets[index].alignment = .center
                widgets[index].x = Double((left + sizes[index].width / 2) / display.width)
                widgets[index].y = layout.y
                left += sizes[index].width + gap
            }
        }
        return widgets.map { $0.clamped() }
    }
}
