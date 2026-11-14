import AppKit
import Foundation

/// What a desktop widget shows and where: its words or clock face at a moment, its font, its frame
/// on a display, and when what it shows next changes. Pure, so the desktop and the panel's arranging
/// preview draw the same widget the same way.
enum DesktopWidgetRendering {
    /// What the widgets are drawn from: the moment, this Mac's calendar and time zone, the language
    /// and region, and the readings some kinds show.
    struct Inputs {
        var date: Date
        /// This Mac's calendar, in its time zone.
        var calendar: Calendar
        var locale: Locale
        /// The internal battery; nil on a Mac without one.
        var battery: BatteryReading?
        /// Where and how the automatic wallpapers plan sunrise and sunset; nil when nothing is set.
        var solar: WallpaperSolarSettings?

        init(
            date: Date, calendar: Calendar, locale: Locale, battery: BatteryReading? = nil,
            solar: WallpaperSolarSettings? = nil
        ) {
            self.date = date
            self.calendar = calendar
            self.locale = locale
            self.battery = battery
            self.solar = solar
        }
    }

    /// A clock face: its size, its ink, and where its hands point, each as a fraction of a turn
    /// from twelve o'clock.
    struct AnalogFace: Equatable {
        var diameter: CGFloat
        /// The ring, marks and hands, opaque: the widget's opacity is the look's.
        var color: NSColor
        /// The second hand's.
        var accent: NSColor
        /// The minute hand's width; the others are drawn in proportion.
        var lineWidth: CGFloat
        var hour: Double
        var minute: Double
        /// Nil without a second hand.
        var second: Double?
        var marks: DesktopWidget.DialMarks = .hours
        var showsRing = true
        /// The numbers' font, for a face with numbers.
        var numeralFont: NSFont?
        /// Slanted numbers, for an italic face whose font has no italic of its own.
        var slantsNumerals = false
    }

    /// How a widget is drawn.
    enum Drawing: Equatable {
        case text(NSAttributedString)
        case analog(AnalogFace)
    }

    /// What is done to the whole drawing: its opacity and turn, the gradient that fills it, its
    /// outline, glow and shadow, and the plate behind it. Every length is in points at the scale
    /// drawn.
    struct Look: Equatable {
        var opacity: CGFloat = 1
        /// The drawing's own size, before any turn.
        var size: NSSize = .zero
        /// Degrees clockwise.
        var rotation: CGFloat = 0
        var gradient: Gradient?
        var outline: Outline?
        var glow: Glow?
        var shadow: Shadow?
        var background: Plate?

        struct Gradient: Equatable {
            var from: NSColor
            var to: NSColor
            /// Degrees clockwise from upwards.
            var angle: CGFloat
        }

        struct Outline: Equatable {
            var width: CGFloat
            var color: NSColor
        }

        struct Glow: Equatable {
            var radius: CGFloat
            var color: NSColor
        }

        struct Shadow: Equatable {
            var blur: CGFloat
            /// Up is positive, as AppKit counts.
            var offset: NSSize
            var color: NSColor
        }

        struct Plate: Equatable {
            var shape: DesktopWidget.Background
            var color: NSColor
            /// How far it reaches past the drawing on every side.
            var inset: CGFloat
        }
    }

    /// Everything one widget shows at a moment.
    struct Content: Equatable {
        /// What it says, as plain text: the words, or the time a clock face shows.
        var text: String
        var drawing: Drawing
        /// The size of what is drawn, without the padding.
        var size: NSSize
        /// The room left around it so the effects and the background are not cut off.
        var padding: CGFloat
        var look = Look()

        /// The size the padded drawing takes once turned: its own when it is not.
        var boxSize: NSSize {
            let width = size.width + 2 * padding, height = size.height + 2 * padding
            guard look.rotation != 0 else { return NSSize(width: width, height: height) }
            let angle = look.rotation * .pi / 180
            let cosine = abs(cos(angle)), sine = abs(sin(angle))
            // Rounded up, but not by a rounding error: a quarter turn swaps the sides exactly.
            return NSSize(
                width: ceil(width * cosine + height * sine - 1e-6), height: ceil(width * sine + height * cosine - 1e-6))
        }
    }

    // MARK: Formatters

    /// Date formatters by template, locale, calendar and time zone. Making one costs far more than
    /// using it, and a clock with seconds asks every second.
    @MainActor
    final class Formatters {
        private var cache: [String: DateFormatter] = [:]
        private var symbols: [String: [String]] = [:]

        init() {}

        func string(_ date: Date, template: String, locale: Locale, calendar: Calendar) -> String {
            formatter(template: template, locale: locale, calendar: calendar).string(from: date)
        }

        /// The pattern the locale makes of `template`, such as "h:mm a" for "jmm" in the US.
        func pattern(template: String, locale: Locale, calendar: Calendar) -> String {
            formatter(template: template, locale: locale, calendar: calendar).dateFormat ?? ""
        }

        /// `date` written with an explicit pattern, in the locale's digits and words.
        func string(_ date: Date, format: String, locale: Locale, calendar: Calendar) -> String {
            formatter(template: format, locale: locale, calendar: calendar, isPattern: true).string(from: date)
        }

        /// The one-letter weekday names of `locale`, Sunday first.
        func weekdaySymbols(locale: Locale) -> [String] {
            if let found = symbols[locale.identifier] { return found }
            let formatter = DateFormatter()
            formatter.locale = locale
            let found = formatter.veryShortStandaloneWeekdaySymbols ?? []
            symbols[locale.identifier] = found
            return found
        }

        private func formatter(
            template: String, locale: Locale, calendar: Calendar, isPattern: Bool = false
        ) -> DateFormatter {
            let key = [
                isPattern ? "=" : "~", template, locale.identifier, "\(calendar.identifier)", calendar.timeZone.identifier,
                "\(calendar.firstWeekday)", "\(calendar.minimumDaysInFirstWeek)",
            ].joined(separator: "|")
            if let formatter = cache[key] { return formatter }
            let formatter = DateFormatter()
            // The locale first: setting it gives the formatter the locale's calendar. Another
            // calendar is asked for through the locale, so the date is written in that calendar's
            // own patterns ("九月三十" in the Chinese calendar, not "9月30日"); the region's own
            // calendar keeps the locale as it is, with the person's 12- or 24-hour choice.
            if calendar.identifier == locale.calendar.identifier {
                formatter.locale = locale
            } else {
                var components = Locale.Components(locale: locale)
                components.calendar = calendar.identifier
                formatter.locale = Locale(components: components)
            }
            formatter.calendar = calendar
            formatter.timeZone = calendar.timeZone
            if isPattern {
                formatter.dateFormat = template
            } else {
                formatter.setLocalizedDateFormatFromTemplate(template)
            }
            if cache.count >= 48 { cache.removeAll() }
            cache[key] = formatter
            return formatter
        }
    }

    // MARK: Words

    /// The calendar a widget counts in: this Mac's, or the one a date is written in, in the
    /// widget's time zone.
    static func calendar(for widget: DesktopWidget, inputs: Inputs) -> Calendar {
        var calendar = inputs.calendar
        if widget.kind == .date, let identifier = widget.calendarSystem.identifier {
            calendar = Calendar(identifier: identifier)
            calendar.locale = inputs.locale
        }
        calendar.timeZone = widget.zone(or: inputs.calendar.timeZone)
        return calendar
    }

    /// The hour and minute (and second) of a clock, in the hour cycle chosen.
    static func timeTemplate(_ format: DesktopWidget.TimeFormat, seconds: Bool) -> String {
        let hour = switch format {
        case .system: "j"
        case .twelveHour: "h"
        case .twentyFourHour: "H"
        }
        return hour + (seconds ? "mmss" : "mm")
    }

    /// The Unicode date template of a clock's or a date's words.
    static func template(for widget: DesktopWidget) -> String {
        switch widget.kind {
        case .date: widget.dateStyle.template
        case .analog: timeTemplate(.twentyFourHour, seconds: widget.showsSeconds)
        default: timeTemplate(widget.timeFormat, seconds: widget.showsSeconds)
        }
    }

    /// What the widget says at the moment of `inputs`, as plain text.
    @MainActor
    static func text(for widget: DesktopWidget, inputs: Inputs, formatters: Formatters) -> String {
        let calendar = calendar(for: widget, inputs: inputs)
        let now = inputs.date
        func format(_ template: String, _ date: Date = now) -> String {
            formatters.string(date, template: template, locale: inputs.locale, calendar: calendar)
        }
        switch widget.kind {
        case .time:
            let words = clock(widget, at: now, locale: inputs.locale, calendar: calendar, formatters: formatters)
            if widget.clockLayout == .stacked {
                let label = line(widget.text)
                return label.isEmpty ? words : "\(label)\n\(words)"
            }
            return labelled(words, widget: widget)
        case .analog:
            return labelled(format(template(for: widget)), widget: widget)
        case .date:
            let words = switch widget.dateStyle {
            case .weekNumber: String(localized: "Week \(format("w"))")
            case .dayOfYear: String(localized: "Day \(format("D"))")
            default: format(widget.dateStyle.template)
            }
            return labelled(words, widget: widget)
        case .text:
            return widget.text
        case .countdown:
            return countdown(widget, calendar: calendar, now: now, format: format)
        case .greeting:
            return greeting(hour: calendar.component(.hour, from: now), name: line(widget.text))
        case .battery:
            guard let battery = inputs.battery else { return String(localized: "No battery") }
            let percent = (Double(battery.percent) / 100).formatted(.percent.locale(inputs.locale))
            return battery.isCharging ? String(localized: "Charging \(percent)") : String(localized: "Battery \(percent)")
        case .sun:
            return sun(widget, inputs: inputs, calendar: calendar, format: format)
        case .calendar:
            return format("yMMMM")
        }
    }

    /// The same, for tests and callers that have only a moment, a language and a time zone.
    @MainActor
    static func text(
        for widget: DesktopWidget, at date: Date, locale: Locale, timeZone: TimeZone, formatters: Formatters
    ) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        return text(for: widget, inputs: Inputs(date: date, calendar: calendar, locale: locale), formatters: formatters)
    }

    /// A digital clock's time: on one line in the locale's pattern, with or without the hour's
    /// leading zero and AM or PM, or stacked, the hour over the minutes (over the seconds, over AM
    /// or PM).
    @MainActor
    static func clock(
        _ widget: DesktopWidget, at date: Date, locale: Locale, calendar: Calendar, formatters: Formatters
    ) -> String {
        let base = formatters.pattern(
            template: timeTemplate(widget.timeFormat, seconds: widget.showsSeconds), locale: locale,
            calendar: calendar)
        func write(_ pattern: String) -> String {
            formatters.string(date, format: pattern, locale: locale, calendar: calendar)
        }
        guard widget.clockLayout == .stacked else {
            let pattern = adjusted(base, padsHour: widget.padsHour, showsPeriod: widget.showsPeriod)
            return pattern == base
                ? formatters.string(
                    date, template: timeTemplate(widget.timeFormat, seconds: widget.showsSeconds), locale: locale,
                    calendar: calendar)
                : write(pattern)
        }
        // The locale's own hour letter and its digits: "HH" stays two digits in Britain.
        let hourLetter = base.first { "hHkK".contains($0) } ?? "H"
        let localDigits = base.filter { $0 == hourLetter }.count
        let hour = String(repeating: hourLetter, count: max(localDigits, widget.padsHour ? 2 : 1))
        var lines = [write(hour), write("mm")]
        if widget.showsSeconds { lines.append(write("ss")) }
        if widget.showsPeriod, "hK".contains(hourLetter) { lines.append(write("a")) }
        return lines.joined(separator: "\n")
    }

    /// `pattern` with the hour written in at least two digits when `padsHour`, and without AM or
    /// PM (and the space beside it) unless `showsPeriod`. Quoted words are kept as they are.
    static func adjusted(_ pattern: String, padsHour: Bool, showsPeriod: Bool) -> String {
        let characters = Array(pattern)
        var result = ""
        var quoted = false
        var index = 0
        while index < characters.count {
            let character = characters[index]
            if character == "'" {
                quoted.toggle()
                result.append(character)
                index += 1
                continue
            }
            if quoted || !character.isLetter {
                result.append(character)
                index += 1
                continue
            }
            var end = index
            while end < characters.count, characters[end] == character { end += 1 }
            let run = end - index
            if "hHkK".contains(character) {
                result += String(repeating: character, count: padsHour ? max(run, 2) : run)
            } else if showsPeriod || !"abB".contains(character) {
                result += String(repeating: character, count: run)
            }
            index = end
        }
        guard !showsPeriod else { return result }
        let spaces = CharacterSet.whitespaces.union(CharacterSet(charactersIn: "\u{202F}\u{00A0}"))
        return result.trimmingCharacters(in: spaces)
            .replacingOccurrences(of: "  ", with: " ")
    }

    /// `words` after the widget's label, when it has one.
    private static func labelled(_ words: String, widget: DesktopWidget) -> String {
        let label = line(widget.text)
        return label.isEmpty ? words : "\(label) \(words)"
    }

    /// Text on one line, without the spaces around it.
    private static func line(_ text: String) -> String {
        text.split(whereSeparator: \.isNewline).joined(separator: " ").trimmingCharacters(in: .whitespaces)
    }

    private static func countdown(
        _ widget: DesktopWidget, calendar: Calendar, now: Date, format: (String, Date) -> String
    ) -> String {
        let target = DesktopWidget.start(ofDay: widget.targetDay, in: calendar) ?? calendar.startOfDay(for: now)
        let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: now), to: target).day ?? 0
        let sameYear = calendar.component(.year, from: target) == calendar.component(.year, from: now)
        let name = line(widget.text).isEmpty ? format(sameYear ? "MMMMd" : "yMMMMd", target) : line(widget.text)
        switch days {
        case 0: return String(localized: "\(name) is today")
        case 1: return String(localized: "1 day until \(name)")
        case 2...: return String(localized: "\(days) days until \(name)")
        case -1: return String(localized: "1 day since \(name)")
        default: return String(localized: "\(-days) days since \(name)")
        }
    }

    /// Morning from 5, afternoon from 12, evening from 18, night from 22.
    static let greetingHours = [5, 12, 18, 22]

    private static func greeting(hour: Int, name: String) -> String {
        switch (hour, name.isEmpty) {
        case (5..<12, true): String(localized: "Good morning")
        case (5..<12, false): String(localized: "Good morning, \(name)")
        case (12..<18, true): String(localized: "Good afternoon")
        case (12..<18, false): String(localized: "Good afternoon, \(name)")
        case (18..<22, true): String(localized: "Good evening")
        case (18..<22, false): String(localized: "Good evening, \(name)")
        case (_, true): String(localized: "Good night")
        case (_, false): String(localized: "Good night, \(name)")
        }
    }

    private static func sun(
        _ widget: DesktopWidget, inputs: Inputs, calendar: Calendar, format: (String, Date) -> String
    ) -> String {
        guard let solar = inputs.solar, solar.source == .fixed || solar.location != nil else {
            return String(localized: "No location for sunrise and sunset")
        }
        let template = timeTemplate(widget.timeFormat, seconds: false)
        func words(_ event: WallpaperAutomationRule.Event, _ date: Date) -> String {
            let time = format(template, date)
            return event == .sunrise ? String(localized: "Sunrise \(time)") : String(localized: "Sunset \(time)")
        }
        switch widget.sunStyle {
        case .next:
            guard let (event, date) = nextSunEvent(after: inputs.date, solar: solar, calendar: calendar) else {
                return String(localized: "No sunrise or sunset today")
            }
            return words(event, date)
        case .both:
            let today = [WallpaperAutomationRule.Event.sunrise, .sunset].compactMap { event in
                sunEvent(event, on: inputs.date, solar: solar, calendar: calendar).map { words(event, $0) }
            }
            return today.isEmpty ? String(localized: "No sunrise or sunset today") : today.joined(separator: "  ·  ")
        }
    }

    /// Today's sunrise or sunset as the automatic wallpapers plan it: at the clock time fixed for
    /// it, or worked out from the coordinates. Nil without coordinates, and on a polar day or night.
    static func sunEvent(
        _ event: WallpaperAutomationRule.Event, on day: Date, solar: WallpaperSolarSettings, calendar: Calendar
    ) -> Date? {
        if solar.source == .fixed {
            let minute = event == .sunrise ? solar.fixedSunriseMinute : solar.fixedSunsetMinute
            return calendar.date(bySettingHour: minute / 60, minute: minute % 60, second: 0, of: day)
        }
        guard let location = solar.location else { return nil }
        return WallpaperSolarTimes.event(event, on: day, location: location, calendar: calendar)
    }

    /// The first sunrise or sunset after `date`, looking two days ahead.
    static func nextSunEvent(
        after date: Date, solar: WallpaperSolarSettings, calendar: Calendar
    ) -> (WallpaperAutomationRule.Event, Date)? {
        for offset in 0...2 {
            guard let day = calendar.date(byAdding: .day, value: offset, to: date) else { continue }
            let events = [WallpaperAutomationRule.Event.sunrise, .sunset].compactMap { event in
                sunEvent(event, on: day, solar: solar, calendar: calendar).map { (event, $0) }
            }
            if let next = events.filter({ $0.1 > date }).min(by: { $0.1 < $1.1 }) { return next }
        }
        return nil
    }

    // MARK: Content

    /// What `widget` shows at the moment of `inputs`, at `scale` times its size.
    @MainActor
    static func content(
        for widget: DesktopWidget, inputs: Inputs, formatters: Formatters, scale: CGFloat = 1
    ) -> Content {
        let text = text(for: widget, inputs: inputs, formatters: formatters)
        let padding = padding(for: widget, scale: scale)
        let drawing: Drawing
        let size: NSSize
        switch widget.kind {
        case .analog:
            let face = analogFace(for: widget, inputs: inputs, scale: scale)
            drawing = .analog(face)
            size = NSSize(width: face.diameter, height: face.diameter)
        case .calendar:
            let grid = calendarGrid(for: widget, inputs: inputs, formatters: formatters, scale: scale)
            drawing = .text(grid)
            size = measure(grid)
        default:
            let attributed = attributedText(cased(text, widget, inputs.locale), for: widget, scale: scale)
            drawing = .text(attributed)
            size = measure(attributed)
        }
        var look = look(for: widget, scale: scale)
        look.size = size
        return Content(text: text, drawing: drawing, size: size, padding: padding, look: look)
    }

    /// The size text takes, line breaks included.
    static func measure(_ text: NSAttributedString) -> NSSize {
        let bounds = text.boundingRect(
            with: NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading])
        return NSSize(width: ceil(bounds.width), height: ceil(bounds.height))
    }

    /// `text` in the widget's case, by the rules of `locale`.
    static func cased(_ text: String, _ widget: DesktopWidget, _ locale: Locale) -> String {
        switch widget.textCase {
        case .asWritten: text
        case .uppercase: text.uppercased(with: locale)
        case .lowercase: text.lowercased(with: locale)
        }
    }

    /// A clock face's diameter for each point of the widget's size.
    static let analogScale: CGFloat = 1.5

    static func analogFace(for widget: DesktopWidget, inputs: Inputs, scale: CGFloat = 1) -> AnalogFace {
        let calendar = calendar(for: widget, inputs: inputs)
        let parts = calendar.dateComponents([.hour, .minute, .second], from: inputs.date)
        let hour = Double(parts.hour ?? 0)
        let minute = Double(parts.minute ?? 0)
        let second = Double(parts.second ?? 0)
        let diameter = max(CGFloat(widget.size) * analogScale * scale, 1)
        var numeralFont: NSFont?
        var slants = false
        if widget.dialMarks == .numbers || widget.dialMarks == .quarters {
            let font = font(for: widget, pointSize: max(diameter * 0.14, 1))
            numeralFont = font
            slants = needsSlant(widget, font)
        }
        return AnalogFace(
            diameter: diameter, color: widget.textColor, accent: widget.accent,
            lineWidth: diameter * (0.012 + 0.03 * CGFloat(widget.weight) / 900),
            hour: (hour.truncatingRemainder(dividingBy: 12) + minute / 60) / 12,
            minute: (minute + (widget.showsSeconds ? second / 60 : 0)) / 60,
            second: widget.showsSeconds ? second / 60 : nil, marks: widget.dialMarks,
            showsRing: widget.showsDialRing, numeralFont: numeralFont, slantsNumerals: slants)
    }

    /// This month's grid: its name, the weekdays, then a line for each week, the days under their
    /// weekdays and today in bold, underlined and in the accent colour. The weeks start on the
    /// region's first weekday.
    @MainActor
    static func calendarGrid(
        for widget: DesktopWidget, inputs: Inputs, formatters: Formatters, scale: CGFloat = 1
    ) -> NSAttributedString {
        let calendar = calendar(for: widget, inputs: inputs)
        let now = inputs.date
        let font = font(for: widget, scale: scale)
        var bold = widget
        bold.weight = min(widget.weight + 300, DesktopWidget.weightRange.upperBound)
        let boldFont = self.font(for: bold, scale: scale)
        let column = ceil(font.pointSize * 2.2)
        let grid = NSMutableParagraphStyle()
        grid.tabStops = (1...7).map { NSTextTab(textAlignment: .right, location: column * CGFloat($0)) }
        let header = NSMutableParagraphStyle()
        header.alignment = .center
        header.paragraphSpacing = font.pointSize * 0.3
        let base = textAttributes(for: widget, font: font, scale: scale)

        let result = NSMutableAttributedString()
        func append(_ string: String, _ extra: [NSAttributedString.Key: Any]) {
            result.append(
                NSAttributedString(string: cased(string, widget, inputs.locale), attributes: base.merging(extra) { $1 }))
        }
        append(
            formatters.string(now, template: "yMMMM", locale: inputs.locale, calendar: calendar) + "\n",
            [.paragraphStyle: header, .font: boldFont])

        let first = calendar.firstWeekday
        let symbols = formatters.weekdaySymbols(locale: inputs.locale)
        let faded = widget.textColor.withAlphaComponent(0.6)
        if symbols.count == 7 {
            let ordered = (0..<7).map { symbols[(first - 1 + $0) % 7] }
            append(ordered.map { "\t\($0)" }.joined() + "\n", [.paragraphStyle: grid, .foregroundColor: faded])
        }
        guard let month = calendar.dateInterval(of: .month, for: now),
              let days = calendar.range(of: .day, in: .month, for: now) else { return result }
        let today = calendar.component(.day, from: now)
        var column0 = (calendar.component(.weekday, from: month.start) - first + 7) % 7
        append(String(repeating: "\t", count: column0), [.paragraphStyle: grid])
        for day in days {
            guard let date = calendar.date(byAdding: .day, value: day - days.lowerBound, to: month.start) else { continue }
            let number = formatters.string(date, template: "d", locale: inputs.locale, calendar: calendar)
            append("\t", [.paragraphStyle: grid])
            append(
                number,
                day == today
                    ? [
                        .paragraphStyle: grid, .font: boldFont, .foregroundColor: widget.accent,
                        .underlineStyle: NSUnderlineStyle.single.rawValue,
                    ]
                    : [.paragraphStyle: grid])
            column0 += 1
            if column0 == 7, day != days.upperBound - 1 {
                append("\n", [.paragraphStyle: grid])
                column0 = 0
            }
        }
        return result
    }

    // MARK: Look

    /// The widget's font at `scale` times its size. Digits keep one width, so a clock does not
    /// shift as its numbers change.
    static func font(for widget: DesktopWidget, scale: CGFloat = 1) -> NSFont {
        font(for: widget, pointSize: max(CGFloat(widget.size) * scale, 1))
    }

    /// The weights AppKit's font manager counts, 0 to 15, for each hundred of the 100 to 900 scale.
    private static let managerWeights = [100: 2, 200: 3, 300: 4, 400: 5, 500: 6, 600: 8, 700: 9, 800: 10, 900: 11]

    /// The widget's font at `pointSize`: its installed family when it has one and the Mac still
    /// does, else the system font in its design; italic when asked and the font has an italic.
    static func font(for widget: DesktopWidget, pointSize size: CGFloat) -> NSFont {
        let weight: NSFont.Weight = switch widget.weight {
        case ...100: .ultraLight
        case ...200: .thin
        case ...300: .light
        case ...400: .regular
        case ...500: .medium
        case ...600: .semibold
        case ...700: .bold
        case ...800: .heavy
        default: .black
        }
        var chosen: NSFont?
        if let family = widget.fontFamily {
            let manager = NSFontManager.shared
            let managerWeight = managerWeights[min(max(widget.weight / 100 * 100, 100), 900)] ?? 5
            if widget.isItalic {
                chosen = manager.font(withFamily: family, traits: .italicFontMask, weight: managerWeight, size: size)
            }
            if chosen == nil {
                chosen = manager.font(withFamily: family, traits: [], weight: managerWeight, size: size)
            }
        }
        var descriptor: NSFontDescriptor
        if let chosen {
            descriptor = chosen.fontDescriptor
        } else {
            descriptor = NSFont.systemFont(ofSize: size, weight: weight).fontDescriptor
            let design: NSFontDescriptor.SystemDesign? = switch widget.typeface {
            case .standard: nil
            case .rounded: .rounded
            case .serif: .serif
            case .monospaced: .monospaced
            }
            if let design, let designed = descriptor.withDesign(design) { descriptor = designed }
            if widget.isItalic {
                descriptor = descriptor.withSymbolicTraits(descriptor.symbolicTraits.union(.italic))
            }
        }
        descriptor = descriptor.addingAttributes([
            .featureSettings: [[
                NSFontDescriptor.FeatureKey.typeIdentifier: kNumberSpacingType,
                NSFontDescriptor.FeatureKey.selectorIdentifier: kMonospacedNumbersSelector,
            ]],
        ])
        return NSFont(descriptor: descriptor, size: size) ?? chosen ?? .systemFont(ofSize: size, weight: weight)
    }

    /// Whether an italic widget's font has no italic of its own, so its letters are slanted instead.
    static func needsSlant(_ widget: DesktopWidget, _ font: NSFont) -> Bool {
        widget.isItalic && !font.fontDescriptor.symbolicTraits.contains(.italic)
    }

    /// The slant given to letters whose font has no italic.
    static let slant: CGFloat = 0.2

    /// The soft shadow that keeps light text readable on a light wallpaper; nil without one.
    static func shadow(for widget: DesktopWidget, scale: CGFloat = 1) -> Look.Shadow? {
        guard widget.hasShadow else { return nil }
        let size = CGFloat(widget.size) * scale
        let distance = size * CGFloat(widget.shadowDistance) / 100
        let angle = CGFloat(widget.shadowAngle) * .pi / 180
        return Look.Shadow(
            blur: size * CGFloat(widget.shadowBlur) / 100,
            offset: NSSize(width: sin(angle) * distance, height: cos(angle) * distance),
            color: DesktopWidget.color(widget.shadowColor, alpha: CGFloat(widget.shadowOpacity) / 100))
    }

    /// Everything done to the whole drawing, at `scale` times the widget's size; the drawing's
    /// size is the caller's.
    static func look(for widget: DesktopWidget, scale: CGFloat = 1) -> Look {
        let size = CGFloat(widget.size) * scale
        var look = Look(opacity: CGFloat(widget.opacity) / 100, rotation: CGFloat(widget.rotation))
        if widget.fill == .gradient {
            look.gradient = .init(
                from: widget.textColor, to: DesktopWidget.color(widget.gradientColor),
                angle: CGFloat(widget.gradientAngle))
        }
        if widget.outlineWidth > 0 {
            look.outline = .init(
                width: max(size * CGFloat(widget.outlineWidth) / 100, 0.5),
                color: DesktopWidget.color(widget.outlineColor))
        }
        if widget.glowSize > 0 {
            look.glow = .init(
                radius: max(size * CGFloat(widget.glowSize) / 100, 1), color: DesktopWidget.color(widget.glowColor))
        }
        look.shadow = shadow(for: widget, scale: scale)
        if widget.background != .off {
            look.background = .init(
                shape: widget.background,
                color: DesktopWidget.color(widget.backgroundColor, alpha: CGFloat(widget.backgroundOpacity) / 100),
                inset: size * CGFloat(widget.backgroundPadding) / 100)
        }
        return look
    }

    /// The room left around the drawing so its shadow, glow, outline and background are not cut
    /// off.
    static func padding(for widget: DesktopWidget, scale: CGFloat = 1) -> CGFloat {
        let look = look(for: widget, scale: scale)
        var reach: CGFloat = 0
        if let shadow = look.shadow {
            reach = shadow.blur + max(abs(shadow.offset.width), abs(shadow.offset.height))
        }
        if let glow = look.glow { reach = max(reach, glow.radius * 1.5) }
        reach += look.outline?.width ?? 0
        if let plate = look.background { reach = max(reach, plate.inset) }
        return reach > 0 ? ceil(reach) + 1 : 1
    }

    /// The text in the widget's font, colour, spacing and line height. Lines of a text widget line
    /// up on the edge the widget is aligned on.
    static func attributedText(_ text: String, for widget: DesktopWidget, scale: CGFloat = 1) -> NSAttributedString {
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = switch widget.alignment {
        case .leading: .left
        case .center: .center
        case .trailing: .right
        }
        if widget.lineHeight != 100 { paragraph.lineHeightMultiple = CGFloat(widget.lineHeight) / 100 }
        let font = font(for: widget, scale: scale)
        var attributes = textAttributes(for: widget, font: font, scale: scale)
        attributes[.paragraphStyle] = paragraph
        return NSAttributedString(string: text, attributes: attributes)
    }

    /// The font, colour, letter spacing and any slant of a widget's text.
    private static func textAttributes(
        for widget: DesktopWidget, font: NSFont, scale: CGFloat
    ) -> [NSAttributedString.Key: Any] {
        var attributes: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: widget.textColor]
        if widget.letterSpacing != 0 {
            attributes[.kern] = CGFloat(widget.size) * scale * CGFloat(widget.letterSpacing) / 100
        }
        if needsSlant(widget, font) { attributes[.obliqueness] = slant }
        return attributes
    }

    // MARK: Place

    /// The tallest a widget's frame gets, as a fraction of its display's height. However large its
    /// text, a widget so never covers the whole working area, which would make the display count
    /// as covered.
    static let heightLimit: CGFloat = 0.6

    /// The widget's frame on a display whose frame is `display`, for content of `textSize` with
    /// `padding` around it. The position names the content's left edge, centre or right edge
    /// (`alignment`) and its vertical centre; the frame is then moved, never shrunk below the
    /// content, to lie on the display, and is cut only when the content is wider than the display
    /// or taller than `heightLimit` of it. Whole points, rounded down so a display that moves moves
    /// its widgets by exactly as much, and the text is not blurred by a fractional origin.
    static func frame(
        textSize: NSSize, padding: CGFloat, widget: DesktopWidget, display: NSRect
    ) -> NSRect {
        let width = min(ceil(textSize.width) + 2 * padding, display.width)
        let height = min(ceil(textSize.height) + 2 * padding, floor(display.height * heightLimit))
        let anchorX = display.minX + widget.x * display.width
        let anchorY = display.maxY - widget.y * display.height
        let x: CGFloat = switch widget.alignment {
        case .leading: anchorX - padding
        case .center: anchorX - width / 2
        case .trailing: anchorX - width + padding
        }
        let y = anchorY - height / 2
        return NSRect(
            x: min(max(x, display.minX), display.maxX - width).rounded(.down),
            y: min(max(y, display.minY), display.maxY - height).rounded(.down),
            width: width, height: height)
    }

    /// The frame of `content` on a display: as `frame(textSize:padding:widget:display:)` for a
    /// drawing that is not turned, else the box the turned drawing takes, placed the same way.
    static func frame(for content: Content, widget: DesktopWidget, display: NSRect) -> NSRect {
        guard content.look.rotation != 0 else {
            return frame(textSize: content.size, padding: content.padding, widget: widget, display: display)
        }
        return frame(textSize: content.boxSize, padding: 0, widget: widget, display: display)
    }

    // MARK: Time

    /// When what any of `widgets` shows next changes after the moment of `inputs`: the next second
    /// for a clock with seconds, the next minute for any other clock, the next hour a greeting
    /// changes at, the next sunrise or sunset (or midnight) for the sun, the next midnight for
    /// dates, countdowns and the month, each in the widget's own time zone. Text and the battery
    /// never change on a timer. Nil when none of them does.
    static func nextChange(after inputs: Inputs, widgets: [DesktopWidget]) -> Date? {
        let now = inputs.date
        return widgets.compactMap { widget -> Date? in
            let calendar = calendar(for: widget, inputs: inputs)
            func end(of component: Calendar.Component) -> Date? {
                calendar.dateInterval(of: component, for: now)?.end
            }
            switch widget.kind {
            case .time, .analog:
                return end(of: widget.showsSeconds ? .second : .minute)
            case .date, .countdown, .calendar:
                return end(of: .day)
            case .greeting:
                return greetingHours.compactMap {
                    calendar.nextDate(
                        after: now, matching: DateComponents(hour: $0, minute: 0, second: 0),
                        matchingPolicy: .nextTime)
                }.min()
            case .sun:
                guard let solar = inputs.solar else { return nil }
                let event = nextSunEvent(after: now, solar: solar, calendar: calendar)?.1
                return [event, end(of: .day)].compactMap { $0 }.min()
            case .text, .battery:
                return nil
            }
        }.min()
    }

    /// The same, for widgets drawn in this Mac's own language.
    static func nextChange(after date: Date, widgets: [DesktopWidget], calendar: Calendar) -> Date? {
        nextChange(after: Inputs(date: date, calendar: calendar, locale: .autoupdatingCurrent), widgets: widgets)
    }
}
