import AppKit
import SwiftUI

/// The window that introduces desktop widgets once, after an update into them
/// (`FeatureIntroductionStore`): a picture of a desktop with widgets on it, what they do, and
/// **Set Up Desktop Widgets**, which opens Settings › Desktop Widgets, or **Not now**.
@MainActor
enum FeatureIntroWindow {
  static let contentSize = NSSize(width: 560, height: 680)

  /// What the buttons do; `AppDelegate` owns the window and the panel.
  struct Actions {
    let open: () -> Void
    let close: () -> Void
  }

  static func make(actions: Actions) -> NSWindow {
    let window = NSWindow(
      contentRect: NSRect(origin: .zero, size: contentSize),
      styleMask: [.titled, .closable, .fullSizeContentView],
      backing: .buffered, defer: false)
    window.title = String(localized: "Desktop Widgets")
    window.titleVisibility = .hidden
    window.titlebarAppearsTransparent = true
    window.isMovableByWindowBackground = true
    window.isReleasedWhenClosed = false
    let hosting = NSHostingController(
      rootView: DesktopWidgetsIntroView(actions: actions)
        .panelTheme(theme: AppThemeStore.shared, locale: PanelLocale.shared))
    hosting.sizingOptions = []
    window.contentViewController = hosting
    // Installing a controller can resize the window to its content view's fitting size.
    window.setContentSize(contentSize)
    return window
  }
}

/// The introduction's content: the picture over the top, then the words and the two buttons.
struct DesktopWidgetsIntroView: View {
  let actions: FeatureIntroWindow.Actions
  @Environment(\.panelTheme) private var theme

  var body: some View {
    VStack(spacing: 0) {
      DesktopWidgetsIntroPicture()
        .frame(height: 276)
        .accessibilityHidden(true)
      VStack(alignment: .leading, spacing: 0) {
        CapsuleBadge(style: .accent) {
          Image(systemName: "sparkles")
          Text("New Feature")
        }
        Text("Desktop Widgets")
          .font(.panel(.pageTitle))
          .foregroundStyle(theme.surface.text.color)
          .accessibilityAddTraits(.isHeader)
          .padding(.top, 10)
        Text("Put clocks, dates, a calendar and your own notes right on the desktop, above any wallpaper.")
          .font(.panel(.body))
          .foregroundStyle(theme.surface.muted.color)
          .fixedSize(horizontal: false, vertical: true)
          .padding(.top, 4)
        VStack(alignment: .leading, spacing: 14) {
          feature(
            "square.grid.2x2", color: SettingsSection.widgets.tileColor,
            title: Text("Nine kinds of widgets"),
            detail: Text("Time, date, an analog clock, a month calendar, countdowns, greetings, battery, sun times and text."))
          feature(
            "paintpalette", color: SettingsSection.performance.tileColor,
            title: Text("Make them your own"),
            detail: Text("Pick the font, color, style and effects of each widget."))
          feature(
            "hand.draw", color: SettingsSection.appearance.tileColor,
            title: Text("Snap into place"),
            detail: Text("Drag widgets where you like: they snap to the center and to each other, on any display."))
        }
        .padding(.top, 20)
        Text("You can find them any time in Settings › Desktop Widgets.")
          .font(.panel(.footnote))
          .foregroundStyle(theme.surface.muted.color)
          .fixedSize(horizontal: false, vertical: true)
          .padding(.top, 18)
      }
      .padding(.horizontal, 28)
      .padding(.top, 20)
      .frame(maxWidth: .infinity, alignment: .leading)
      Spacer(minLength: 12)
      footer
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .background(theme.surface.background.color)
    .ignoresSafeArea(.container, edges: .top)
  }

  private func feature(_ symbol: String, color: Color, title: Text, detail: Text) -> some View {
    HStack(alignment: .top, spacing: 12) {
      SymbolTile(systemImage: symbol, color: color, size: .medium)
      VStack(alignment: .leading, spacing: 2) {
        title
          .font(.panel(.sectionHeader))
          .foregroundStyle(theme.surface.text.color)
        detail
          .font(.panel(.callout))
          .foregroundStyle(theme.surface.muted.color)
          .fixedSize(horizontal: false, vertical: true)
      }
    }
    .accessibilityElement(children: .combine)
  }

  private var footer: some View {
    VStack(spacing: 0) {
      Divider().overlay(theme.surface.divider.color)
      HStack(spacing: 10) {
        Spacer(minLength: 0)
        Button("Not now", action: actions.close)
          .buttonStyle(.panelSecondary)
          .keyboardShortcut(.cancelAction)
        Button("Set Up Desktop Widgets", action: actions.open)
          .buttonStyle(.panelPrimary)
          .keyboardShortcut(.defaultAction)
          .accessibilityIdentifier("feature-intro-open-widgets")
      }
      .padding(.horizontal, 28)
      .padding(.vertical, 16)
    }
  }
}

/// A desktop at dusk with widgets on it, as the feature draws them: a clock and the date, an
/// analog clock, a month calendar being dragged onto the display's centre line, the battery and a
/// greeting. Still, and drawn once: the hands and the words are of a fixed evening, written in the
/// panel's language.
struct DesktopWidgetsIntroPicture: View {
  @Environment(\.panelTheme) private var theme
  @Environment(\.locale) private var locale

  /// The picture's own colours: a wallpaper, the same in every tone and appearance.
  private enum Palette {
    static let skyTop = PanelColor(rgb: 0x161a46)
    static let skyMiddle = PanelColor(rgb: 0x4b3489)
    static let skyLow = PanelColor(rgb: 0xc4669b)
    static let horizon = PanelColor(rgb: 0xf5a66b)
    static let sun = PanelColor(rgb: 0xffd9a0)
    static let farHills = PanelColor(rgb: 0x5a3a7e)
    static let nearHills = PanelColor(rgb: 0x2b2154)
    static let ground = PanelColor(rgb: 0x16122f)
    static let ink = PanelColor(rgb: 0xffffff)
    static let glass = PanelColor(rgb: 0xffffff, alpha: 0.16)
    static let glassRim = PanelColor(rgb: 0xffffff, alpha: 0.32)
    static let star = PanelColor(rgb: 0xfff4dc)
    static let shade = PanelColor(rgb: 0x0b0820, alpha: 0.35)
  }

  /// The evening every word and hand shows.
  private static let evening: Date = {
    let parts = DateComponents(year: 2026, month: 11, day: 18, hour: 22, minute: 9)
    return Calendar(identifier: .gregorian).date(from: parts) ?? Date(timeIntervalSince1970: 0)
  }()

  var body: some View {
    GeometryReader { proxy in
      let size = proxy.size
      ZStack(alignment: .topLeading) {
        wallpaper(size)
        centerGuide(size)
        clock.position(x: 30 + 85, y: 82)
        analogClock.frame(width: 92, height: 92).position(x: size.width - 30 - 46, y: 84)
        calendarCard.frame(width: 156, height: 118).position(x: size.width / 2, y: size.height - 24 - 59)
        battery.frame(width: 92, height: 92).position(x: 30 + 46, y: size.height - 30 - 46)
        greeting.frame(width: 120, height: 92).position(x: size.width - 30 - 60, y: size.height - 30 - 46)
      }
      .frame(width: size.width, height: size.height)
      .clipped()
    }
  }

  // MARK: Wallpaper

  private func wallpaper(_ size: CGSize) -> some View {
    ZStack {
      LinearGradient(
        stops: [
          .init(color: Palette.skyTop.color, location: 0),
          .init(color: Palette.skyMiddle.color, location: 0.45),
          .init(color: Palette.skyLow.color, location: 0.72),
          .init(color: Palette.horizon.color, location: 0.9),
        ], startPoint: .top, endPoint: .bottom)
      RadialGradient(
        colors: [Palette.sun.color.opacity(0.95), Palette.sun.color.opacity(0)],
        center: UnitPoint(x: 0.62, y: 0.8), startRadius: 4, endRadius: size.width * 0.4)
      stars(size)
      hills(size, base: 0.74, amplitude: 0.09, phase: 0.6, color: Palette.farHills.color)
      hills(size, base: 0.84, amplitude: 0.07, phase: 2.1, color: Palette.nearHills.color)
      hills(size, base: 0.93, amplitude: 0.04, phase: 4.0, color: Palette.ground.color)
    }
  }

  private func stars(_ size: CGSize) -> some View {
    let points: [(CGFloat, CGFloat, CGFloat)] = [
      (0.04, 0.08, 1.2), (0.24, 0.06, 1.1), (0.47, 0.1, 1.8), (0.58, 0.22, 1.0), (0.66, 0.06, 1.3),
      (0.74, 0.36, 1.1), (0.97, 0.12, 1.2), (0.98, 0.5, 1.0), (0.44, 0.3, 1.2), (0.52, 0.16, 0.9),
      (0.62, 0.4, 0.9), (0.38, 0.05, 1.0),
    ]
    return Canvas { context, _ in
      for (x, y, radius) in points {
        let rect = CGRect(x: x * size.width - radius, y: y * size.height - radius, width: radius * 2, height: radius * 2)
        context.fill(Path(ellipseIn: rect), with: .color(Palette.star.color.opacity(0.85)))
      }
    }
  }

  /// A ridge of rolling hills from `base` (a share of the height) to the bottom edge.
  private func hills(_ size: CGSize, base: CGFloat, amplitude: CGFloat, phase: CGFloat, color: Color) -> some View {
    Path { path in
      let steps = 48
      path.move(to: CGPoint(x: 0, y: size.height))
      for step in 0...steps {
        let x = CGFloat(step) / CGFloat(steps)
        let wave = sin(x * 5.2 + phase) * 0.6 + sin(x * 11.3 + phase * 1.7) * 0.4
        path.addLine(to: CGPoint(x: x * size.width, y: (base - amplitude * wave) * size.height))
      }
      path.addLine(to: CGPoint(x: size.width, y: size.height))
      path.closeSubpath()
    }
    .fill(color)
  }

  /// The display's centre line, drawn while a widget is dragged onto it.
  private func centerGuide(_ size: CGSize) -> some View {
    Path { path in
      path.move(to: CGPoint(x: size.width / 2, y: 40))
      path.addLine(to: CGPoint(x: size.width / 2, y: size.height - 10))
    }
    .stroke(theme.accent.accent.color.opacity(0.9), style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
  }

  // MARK: Widgets

  private func glass<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
    content()
      .frame(maxWidth: .infinity, maxHeight: .infinity)
      .background(Palette.glass.color, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
      .overlay(
        RoundedRectangle(cornerRadius: 16, style: .continuous)
          .strokeBorder(Palette.glassRim.color, lineWidth: 0.75))
      .shadow(color: Palette.shade.color, radius: 10, y: 4)
  }

  private var clock: some View {
    VStack(alignment: .leading, spacing: 0) {
      Text(verbatim: "10:09")
        .font(.panel(.proportional(to: 100, ratio: 0.46, weight: .light), design: .rounded))
        .monospacedDigit()
      Text(verbatim: formatted("EEEEMMMMd"))
        .font(.panel(.headline))
        .opacity(0.85)
    }
    .foregroundStyle(Palette.ink.color)
    .shadow(color: Palette.shade.color, radius: 6, y: 2)
    .lineLimit(1)
    .minimumScaleFactor(0.7)
    .frame(width: 170, alignment: .leading)
  }

  private var analogClock: some View {
    glass {
      Canvas { context, size in
        let center = CGPoint(x: size.width / 2, y: size.height / 2)
        let radius = min(size.width, size.height) / 2 - 12
        for tick in 0..<12 {
          let angle = Double(tick) / 12 * 2 * .pi
          let inner = radius - (tick % 3 == 0 ? 7 : 4)
          var mark = Path()
          mark.move(to: point(center, inner, angle))
          mark.addLine(to: point(center, radius, angle))
          context.stroke(mark, with: .color(Palette.ink.color.opacity(0.75)), lineWidth: tick % 3 == 0 ? 1.6 : 1)
        }
        // 10:09: the hour hand just past ten, the minute hand on nine minutes.
        let hour = (10 + 9.0 / 60) / 12 * 2 * .pi
        let minute = 9.0 / 60 * 2 * .pi
        var hands = Path()
        hands.move(to: center)
        hands.addLine(to: point(center, radius * 0.5, hour))
        context.stroke(hands, with: .color(Palette.ink.color), style: StrokeStyle(lineWidth: 3, lineCap: .round))
        var long = Path()
        long.move(to: center)
        long.addLine(to: point(center, radius * 0.8, minute))
        context.stroke(long, with: .color(Palette.ink.color), style: StrokeStyle(lineWidth: 2, lineCap: .round))
        context.fill(
          Path(ellipseIn: CGRect(x: center.x - 3, y: center.y - 3, width: 6, height: 6)),
          with: .color(theme.accent.accent.color))
      }
    }
  }

  private func point(_ center: CGPoint, _ length: CGFloat, _ angle: Double) -> CGPoint {
    CGPoint(x: center.x + length * CGFloat(sin(angle)), y: center.y - length * CGFloat(cos(angle)))
  }

  /// The month of the evening, its day ringed in the accent colour, outlined as the widget being
  /// moved is in Settings.
  private var calendarCard: some View {
    var calendar = Calendar(identifier: .gregorian)
    calendar.locale = locale
    let today = calendar.component(.day, from: Self.evening)
    let start = calendar.date(from: calendar.dateComponents([.year, .month], from: Self.evening)) ?? Self.evening
    let days = calendar.range(of: .day, in: .month, for: Self.evening)?.count ?? 30
    let lead = (calendar.component(.weekday, from: start) - calendar.firstWeekday + 7) % 7
    let symbols = calendar.veryShortStandaloneWeekdaySymbols
    let weekdays = (0..<7).map { symbols[($0 + calendar.firstWeekday - 1) % 7] }
    let cells: [Int?] = Array(repeating: nil, count: lead) + (1...days).map { $0 }
    let rows = stride(from: 0, to: cells.count, by: 7).map { Array(cells[$0..<min($0 + 7, cells.count)]) }
    let small = Font.panel(.proportional(to: 100, ratio: 0.075, weight: .medium))
    return glass {
      VStack(alignment: .leading, spacing: 3) {
        Text(verbatim: formatted("LLLL"))
          .font(.panel(.calloutStrong))
          .foregroundStyle(theme.accent.accent.color)
          .padding(.bottom, 1)
        grid(weekdays.map { Optional($0) }, today: nil, font: small).opacity(0.6)
        ForEach(rows.indices, id: \.self) { index in
          grid(rows[index].map { $0.map(String.init) }, today: today.description, font: small)
        }
      }
      .foregroundStyle(Palette.ink.color)
      .padding(.horizontal, 10)
      .padding(.vertical, 8)
      .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
    .overlay(
      RoundedRectangle(cornerRadius: 19, style: .continuous)
        .strokeBorder(theme.accent.accent.color, lineWidth: 2)
        .padding(-3))
  }

  private func grid(_ cells: [String?], today: String?, font: Font) -> some View {
    HStack(spacing: 0) {
      ForEach(0..<7, id: \.self) { index in
        let cell = index < cells.count ? cells[index] : nil
        Text(verbatim: cell ?? "")
          .font(font)
          .monospacedDigit()
          .frame(maxWidth: .infinity)
          .foregroundStyle(cell == today && today != nil ? theme.accent.onPrimary.color : Palette.ink.color)
          .background {
            if cell == today, today != nil {
              Circle().fill(theme.accent.primary.color).frame(width: 13, height: 13)
            }
          }
      }
    }
  }

  private var battery: some View {
    glass {
      ZStack {
        Circle()
          .stroke(Palette.ink.color.opacity(0.22), lineWidth: 6)
        Circle()
          .trim(from: 0, to: 0.8)
          .stroke(theme.surface.markApproved.color, style: StrokeStyle(lineWidth: 6, lineCap: .round))
          .rotationEffect(.degrees(-90))
        VStack(spacing: 1) {
          Image(systemName: "bolt.fill")
            .font(.panel(.caption))
          Text(verbatim: (0.8).formatted(.percent.locale(locale)))
            .font(.panel(.headline))
            .monospacedDigit()
        }
        .foregroundStyle(Palette.ink.color)
      }
      .padding(16)
    }
  }

  private var greeting: some View {
    glass {
      VStack(alignment: .leading, spacing: 6) {
        Image(systemName: "moon.stars.fill")
          .font(.panel(.headline))
          .foregroundStyle(Palette.sun.color)
        Text("Good evening")
          .font(.panel(.calloutStrong))
          .foregroundStyle(Palette.ink.color)
          .lineLimit(2)
          .minimumScaleFactor(0.8)
        Capsule().fill(Palette.ink.color.opacity(0.35)).frame(width: 56, height: 4)
        Capsule().fill(Palette.ink.color.opacity(0.25)).frame(width: 38, height: 4)
      }
      .padding(12)
      .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
  }

  private func formatted(_ template: String) -> String {
    let formatter = DateFormatter()
    formatter.locale = locale
    formatter.setLocalizedDateFormatFromTemplate(template)
    return formatter.string(from: Self.evening)
  }
}
