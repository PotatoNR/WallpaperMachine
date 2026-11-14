import AppKit

/// What `DesktopWidgetController` puts a widget on: a window in production, a recorder in tests.
@MainActor
protocol DesktopWidgetSurface: AnyObject {
    /// Shows `drawing` with `look` and `padding` around it, in `frame` (global screen coordinates).
    func show(
        _ drawing: DesktopWidgetRendering.Drawing, look: DesktopWidgetRendering.Look, padding: CGFloat, frame: NSRect)
    /// Whether any of it can be seen now: false while windows cover it, the display sleeps or the
    /// screen is locked.
    var isOnScreen: Bool { get }
    /// Puts it in front of the other widgets' surfaces, still behind Finder's icons.
    func raise()
    func remove()
}

/// One desktop widget's window: transparent, the size of its text or clock face, just above the wallpaper windows
/// and below Finder's desktop icons, on every Space, ignoring the mouse. Its Objective-C name is not
/// one of `WallpaperPresentationPolicy.wallpaperWindowClassNames`, so occlusion tracking, the
/// window audit and the desktop-picture posters never take it for a wallpaper.
@objc(MWEDesktopWidgetWindow)
final class DesktopWidgetWindow: NSWindow, DesktopWidgetSurface {
    private let widgetView = DesktopWidgetView()

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    /// A widget may sit under the menu bar, out of which AppKit would otherwise move a window.
    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect {
        frameRect
    }

    /// A widget window that is not yet on screen.
    static func make() -> DesktopWidgetWindow {
        let window = DesktopWidgetWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1, height: 1), styleMask: .borderless,
            backing: .buffered, defer: false)
        // Just above the wallpaper windows, as the coverage probes and the notch strip are, and below
        // Finder's icons. Being transparent and smaller than a display's working area, it never
        // makes a display count as covered.
        window.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.desktopWindow)) + 1)
        window.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenAuxiliary]
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = false
        window.ignoresMouseEvents = true
        window.isMovable = false
        window.isReleasedWhenClosed = false
        window.isRestorable = false
        // Hiding the app hides the panel, never the desktop.
        window.canHide = false
        window.hidesOnDeactivate = false
        window.isExcludedFromWindowsMenu = true
        window.animationBehavior = .none
        window.contentView = window.widgetView
        return window
    }

    /// A widget window, put on screen.
    static func present() -> any DesktopWidgetSurface {
        let window = make()
        window.orderFrontRegardless()
        return window
    }

    func show(
        _ drawing: DesktopWidgetRendering.Drawing, look: DesktopWidgetRendering.Look, padding: CGFloat, frame: NSRect
    ) {
        if self.frame != frame { setFrame(frame, display: false) }
        widgetView.update(drawing: drawing, look: look, padding: padding)
    }

    var isOnScreen: Bool { occlusionState.contains(.visible) }

    func raise() { orderFrontRegardless() }

    func remove() {
        orderOut(nil)
        close()
    }

    /// The words the window shows; empty for a clock face.
    var shownText: String {
        if case .text(let text) = widgetView.drawing { return text.string }
        return ""
    }
}

/// Draws a widget's text or clock face with its look, and redraws only when one of them changes:
/// on the desktop, and in the panel's preview, which so draws it the same way. It never takes the
/// mouse; the preview's drag is the panel's own.
///
/// The drawing is put together in transparency layers, so its parts never show through each other:
/// the letters (or the face) are filled, a gradient takes their place where they are, the outline
/// goes behind them, and that group casts the glow and then the shadow. The background plate sits
/// under it all, and the widget's opacity applies to the whole.
final class DesktopWidgetView: NSView {
    private(set) var drawing = DesktopWidgetRendering.Drawing.text(NSAttributedString())
    private(set) var look = DesktopWidgetRendering.Look()
    private var padding: CGFloat = 0

    override var isOpaque: Bool { false }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    func update(drawing: DesktopWidgetRendering.Drawing, look: DesktopWidgetRendering.Look, padding: CGFloat) {
        guard drawing != self.drawing || look != self.look || padding != self.padding else { return }
        self.drawing = drawing
        self.look = look
        self.padding = padding
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        guard let context = NSGraphicsContext.current?.cgContext else { return }
        NSGraphicsContext.saveGraphicsState()
        defer { NSGraphicsContext.restoreGraphicsState() }
        var content = bounds.insetBy(dx: padding, dy: padding)
        if look.rotation != 0 {
            // Turned about the middle; the frame is the turned drawing's box.
            context.translateBy(x: bounds.midX, y: bounds.midY)
            context.rotate(by: -look.rotation * .pi / 180)
            context.translateBy(x: -bounds.midX, y: -bounds.midY)
            content = NSRect(
                x: bounds.midX - look.size.width / 2, y: bounds.midY - look.size.height / 2,
                width: look.size.width, height: look.size.height)
        }
        context.setAlpha(look.opacity)
        context.beginTransparencyLayer(auxiliaryInfo: nil)
        defer { context.endTransparencyLayer() }
        if let plate = look.background { Self.draw(plate, around: content) }

        if let shadow = look.shadow {
            let value = NSShadow()
            value.shadowBlurRadius = shadow.blur
            value.shadowOffset = shadow.offset
            value.shadowColor = shadow.color
            value.set()
        }
        context.beginTransparencyLayer(auxiliaryInfo: nil)
        if let glow = look.glow {
            // A shadow without offset is a glow; drawn twice, it reads as light, not as haze.
            for _ in 0..<2 {
                NSGraphicsContext.saveGraphicsState()
                let value = NSShadow()
                value.shadowBlurRadius = glow.radius
                value.shadowOffset = .zero
                value.shadowColor = glow.color
                value.set()
                drawInk(in: content, context: context)
                NSGraphicsContext.restoreGraphicsState()
            }
        } else {
            drawInk(in: content, context: context)
        }
        context.endTransparencyLayer()
    }

    /// The letters or the face, filled with the colour or the gradient, with the outline behind.
    private func drawInk(in rect: NSRect, context: CGContext) {
        context.beginTransparencyLayer(auxiliaryInfo: nil)
        defer { context.endTransparencyLayer() }
        drawShapes(in: rect, outline: nil)
        if let gradient = look.gradient {
            context.saveGState()
            context.setBlendMode(.sourceIn)
            Self.draw(gradient, over: rect.insetBy(dx: -padding, dy: -padding))
            context.restoreGState()
        }
        if let outline = look.outline {
            context.saveGState()
            context.setBlendMode(.destinationOver)
            context.setLineJoin(.round)
            drawShapes(in: rect, outline: outline)
            context.restoreGState()
        }
    }

    /// The drawing itself; with `outline`, its outline alone, in the outline's colour.
    private func drawShapes(in rect: NSRect, outline: DesktopWidgetRendering.Look.Outline?) {
        switch drawing {
        case .text(let text):
            // Laid out from the top, so a widget cut to its display keeps its first lines.
            let shown = outline.map { Self.outlined(text, $0) } ?? text
            shown.draw(with: rect, options: [.usesLineFragmentOrigin, .usesFontLeading])
        case .analog(let face):
            Self.draw(face, in: rect, outline: outline)
        }
    }

    /// `text` as its outline only: each run stroked as wide as the outline on both sides of the
    /// letters' edge, so as much shows outside them.
    private static func outlined(
        _ text: NSAttributedString, _ outline: DesktopWidgetRendering.Look.Outline
    ) -> NSAttributedString {
        let result = NSMutableAttributedString(attributedString: text)
        let whole = NSRange(location: 0, length: result.length)
        result.enumerateAttribute(.font, in: whole) { value, range, _ in
            let size = (value as? NSFont)?.pointSize ?? 12
            // Percent of the point size; positive strokes without filling.
            result.addAttribute(.strokeWidth, value: 200 * outline.width / max(size, 1), range: range)
        }
        result.addAttribute(.strokeColor, value: outline.color, range: whole)
        result.addAttribute(.foregroundColor, value: outline.color, range: whole)
        result.removeAttribute(.underlineStyle, range: whole)
        return result
    }

    private static func draw(_ gradient: DesktopWidgetRendering.Look.Gradient, over rect: NSRect) {
        guard let fill = NSGradient(starting: gradient.from, ending: gradient.to) else { return }
        let angle = gradient.angle * .pi / 180
        // The way from the first colour to the second, upwards positive, across the whole rect.
        let direction = CGVector(dx: sin(angle), dy: cos(angle))
        let reach = (abs(direction.dx) * rect.width + abs(direction.dy) * rect.height) / 2
        let start = NSPoint(x: rect.midX - direction.dx * reach, y: rect.midY - direction.dy * reach)
        let end = NSPoint(x: rect.midX + direction.dx * reach, y: rect.midY + direction.dy * reach)
        fill.draw(from: start, to: end, options: [.drawsBeforeStartingLocation, .drawsAfterEndingLocation])
    }

    private static func draw(_ plate: DesktopWidgetRendering.Look.Plate, around rect: NSRect) {
        let area = rect.insetBy(dx: -plate.inset, dy: -plate.inset)
        let short = min(area.width, area.height)
        let radius: CGFloat = switch plate.shape {
        case .off, .rectangle: 0
        case .rounded: short * 0.22
        case .capsule: short / 2
        }
        plate.color.setFill()
        NSBezierPath(roundedRect: area, xRadius: radius, yRadius: radius).fill()
    }

    /// The ring, the hour marks (or ticks, or numbers), the hands and a dot at the centre. With
    /// `outline`, every line is drawn that much wider on each side, in the outline's colour.
    private static func draw(
        _ face: DesktopWidgetRendering.AnalogFace, in rect: NSRect, outline: DesktopWidgetRendering.Look.Outline?
    ) {
        let extra = (outline?.width ?? 0) * 2
        let ink = outline?.color ?? face.color
        ink.set()
        let radius = min(rect.width, rect.height) / 2
        let center = NSPoint(x: rect.midX, y: rect.midY)
        let width = face.lineWidth
        func point(_ turn: Double, _ length: CGFloat) -> NSPoint {
            let angle = turn * 2 * .pi
            return NSPoint(x: center.x + CGFloat(sin(angle)) * length, y: center.y + CGFloat(cos(angle)) * length)
        }
        func line(from start: NSPoint, to end: NSPoint, width: CGFloat) {
            let path = NSBezierPath()
            path.move(to: start)
            path.line(to: end)
            path.lineWidth = width + extra
            path.lineCapStyle = .round
            path.stroke()
        }
        let ringWidth = max(width * 0.5, 0.5)
        if face.showsRing {
            let ring = NSBezierPath(
                ovalIn: NSRect(x: center.x - radius, y: center.y - radius, width: 2 * radius, height: 2 * radius)
                    .insetBy(dx: ringWidth / 2, dy: ringWidth / 2))
            ring.lineWidth = ringWidth + extra
            ring.stroke()
        }
        let outer = radius - ringWidth - radius * 0.04
        func mark(_ turn: Double, long: Bool) {
            let length = radius * (long ? 0.14 : 0.08)
            line(from: point(turn, outer), to: point(turn, outer - length), width: width * (long ? 0.9 : 0.6))
        }
        func numeral(_ hour: Int, at spot: NSPoint) {
            guard let font = face.numeralFont else { return }
            var attributes: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: ink]
            if face.slantsNumerals { attributes[.obliqueness] = DesktopWidgetRendering.slant }
            if let outline {
                attributes[.strokeWidth] = 200 * outline.width / max(font.pointSize, 1)
                attributes[.strokeColor] = outline.color
            }
            let text = NSAttributedString(string: String(hour), attributes: attributes)
            let size = text.size()
            text.draw(at: NSPoint(x: spot.x - size.width / 2, y: spot.y - size.height / 2))
        }
        switch face.marks {
        case .bare:
            break
        case .hours:
            for hour in 0..<12 { mark(Double(hour) / 12, long: hour % 3 == 0) }
        case .minutes:
            for minute in 0..<60 {
                let turn = Double(minute) / 60
                if minute % 5 == 0 {
                    mark(turn, long: true)
                } else {
                    line(from: point(turn, outer), to: point(turn, outer - radius * 0.04), width: width * 0.35)
                }
            }
        case .numbers, .quarters:
            for hour in 1...12 {
                let turn = Double(hour % 12) / 12
                if face.marks == .numbers || hour % 3 == 0 {
                    numeral(hour, at: point(turn, outer - radius * 0.13))
                } else {
                    mark(turn, long: false)
                }
            }
        }
        line(from: center, to: point(face.hour, radius * 0.5), width: width * 1.6)
        line(from: center, to: point(face.minute, radius * 0.76), width: width)
        if let second = face.second {
            if outline == nil { face.accent.set() }
            line(from: point(second + 0.5, radius * 0.12), to: point(second, radius * 0.84), width: max(width * 0.35, 0.5))
            ink.set()
        }
        let dot = width * 1.3 + extra / 2
        NSBezierPath(ovalIn: NSRect(x: center.x - dot, y: center.y - dot, width: 2 * dot, height: 2 * dot)).fill()
    }
}
