import AppKit
import SwiftUI

/// Settings › Desktop Widgets without a search: a workspace rather than a scrolling page of rows,
/// because a widget is arranged and styled by looking at it. A large canvas of the display
/// (`DesktopWidgetPreview`) moves, resizes and turns the widgets; the layers list under it picks
/// one; an inspector beside it shows the selected widget's controls a pane at a time
/// (`DesktopWidgetPane`), so a control is never a long scroll from the picture it changes. Neither
/// the canvas nor the layers move when the inspector scrolls. In a narrow window the inspector goes
/// under the canvas instead, which stays on show above it. With no widget yet, or none selected (a
/// click on the canvas's backdrop puts the selection away to see the widgets as the desktop will),
/// the inspector offers the ready-made widgets (`DesktopWidgetPreset`); the Ready-made button
/// offers them at any time.
///
/// The page takes the size it is offered and asks for none of its own, as every Settings page does
/// (`SettingsDetail`).
struct WidgetsWorkspace: View {
  /// The inspector's width beside the canvas.
  static let inspectorWidth: CGFloat = 340
  /// From this width of the page the inspector stands beside the canvas; below it, under it.
  static let sideBySideWidth: CGFloat = 800
  private static let margin: CGFloat = 24
  private static let gap: CGFloat = 18
  /// The room the header and the bar under the canvas take, for sizing the canvas.
  private static let chrome: CGFloat = 104

  @Environment(PanelController.self) private var controller
  @Environment(\.panelTheme) private var theme

  var body: some View {
    let model = controller.widgetsSettings
    let screens = model.screens()
    let selected = model.selected
    let screen =
      model.lastChosen.flatMap { model.previewScreen(for: $0, among: screens) }
      ?? screens.first(where: \.isMain) ?? screens.first
    let display = screen?.frame.size ?? .zero
    let aspect = display.width > 0 && display.height > 0 ? display.width / display.height : 16 / 10
    GeometryReader { proxy in
      let width = max(proxy.size.width - 2 * Self.margin, 0)
      let height = max(proxy.size.height - 2 * Self.margin, 0)
      let sideBySide = proxy.size.width >= Self.sideBySideWidth
      VStack(alignment: .leading, spacing: 14) {
        header
        if sideBySide {
          let left = max(width - Self.inspectorWidth - Self.gap, 0)
          let canvas = min(left / aspect, max(height - Self.chrome, 0) * 0.66)
          HStack(alignment: .top, spacing: Self.gap) {
            VStack(alignment: .leading, spacing: 12) {
              stage(screen, selected: selected, height: canvas)
              ScrollView {
                layers(screens: screens)
                  .padding(.bottom, 8)
              }
              .frame(maxHeight: .infinity)
            }
            .frame(minWidth: 0, maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            inspector(selected, screens: screens)
              .frame(width: Self.inspectorWidth)
              .frame(maxHeight: .infinity, alignment: .top)
          }
        } else {
          let canvas = min(width / aspect, max(height - Self.chrome, 0) * 0.45)
          stage(screen, selected: selected, height: canvas)
          ScrollView {
            // The inspector first: a widget is picked on the canvas as well as in the layers.
            VStack(alignment: .leading, spacing: 18) {
              inspectorContent(selected, screens: screens, scrolls: false)
              layers(screens: screens)
            }
            .padding(.bottom, 8)
          }
          .frame(maxHeight: .infinity)
        }
      }
      .padding(Self.margin)
      .frame(width: proxy.size.width, height: proxy.size.height, alignment: .topLeading)
    }
  }

  // MARK: Header

  private var header: some View {
    let settings = controller.settings
    let section = SettingsSection.widgets
    return HStack(spacing: 12) {
      SymbolTile(systemImage: section.systemImage, color: section.tileColor, size: .medium)
      VStack(alignment: .leading, spacing: 1) {
        Text(verbatim: settings.text(section.title))
          .font(.panel(.headline))
          .accessibilityAddTraits(.isHeader)
        Text(verbatim: settings.text(section.summary))
          .font(.panel(.callout))
          .foregroundStyle(theme.surface.muted.color)
          .lineLimit(1)
      }
      .frame(minWidth: 0, maxWidth: .infinity, alignment: .leading)
      ReadyMadeWidgetsButton()
      WidgetAddMenu()
    }
  }

  // MARK: Canvas

  /// The canvas, the size the page leaves it, and under it how to use it and the Center buttons.
  @ViewBuilder
  private func stage(
    _ screen: DesktopWidgetController.Screen?, selected: DesktopWidget?, height: CGFloat
  ) -> some View {
    VStack(alignment: .leading, spacing: 8) {
      Group {
        if let screen {
          DesktopWidgetPreview(screen: screen)
        } else {
          RoundedRectangle(cornerRadius: 8, style: .continuous)
            .fill(theme.surface.mediaWell.color)
        }
      }
      .frame(maxWidth: .infinity)
      .frame(height: max(height, 0))
      HStack(alignment: .center, spacing: 12) {
        Text(verbatim: L("Drag to move, drag a corner to resize and the knob to turn. Hold Command to turn snapping off. Click the wallpaper to select nothing."))
          .font(.panel(.footnote))
          .foregroundStyle(theme.surface.muted.color)
          .lineLimit(3)
          .frame(minWidth: 0, maxWidth: .infinity, alignment: .leading)
        if let selected, let screen {
          WidgetCenterButtons(widget: selected, screen: screen)
        }
      }
    }
    .layoutPriority(1)
  }

  // MARK: Layers

  private func layers(screens: [DesktopWidgetController.Screen]) -> some View {
    let model = controller.widgetsSettings
    let widgets = model.widgets
    let order = widgets.map(\.id)
    return VStack(alignment: .leading, spacing: 6) {
      HStack(spacing: 8) {
        Text("Layers")
          .font(.panel(.sectionHeader))
          .accessibilityAddTraits(.isHeader)
        Spacer(minLength: 8)
        if widgets.count > 1 {
          Text(verbatim: L("Higher is in front"))
            .font(.panel(.caption))
            .foregroundStyle(theme.surface.muted.color)
            .lineLimit(1)
        }
      }
      .padding(.leading, 12)
      if widgets.isEmpty {
        Text("No widgets yet. Pick a ready-made one or add a blank one.")
          .font(.panel(.callout))
          .foregroundStyle(theme.surface.muted.color)
          .padding(14)
          .frame(maxWidth: .infinity, alignment: .leading)
          .panelCardSurface()
      } else {
        PanelCard {
          ForEach(widgets) { widget in
            WidgetLayerRow(widget: widget, screens: screens, order: order)
          }
        }
      }
    }
  }

  // MARK: Inspector

  private func inspector(_ selected: DesktopWidget?, screens: [DesktopWidgetController.Screen]) -> some View {
    inspectorContent(selected, screens: screens, scrolls: true)
  }

  /// The selected widget's name and kind, the panes' tabs and the pane chosen; without a widget, the
  /// ready-made ones. `scrolls` gives the pane a scroll of its own, as it has beside the canvas.
  @ViewBuilder
  private func inspectorContent(
    _ selected: DesktopWidget?, screens: [DesktopWidgetController.Screen], scrolls: Bool
  ) -> some View {
    let model = controller.widgetsSettings
    if let widget = selected {
      let pane = model.pane(for: widget)
      VStack(alignment: .leading, spacing: 12) {
        editing(widget, screens: screens)
        SettingsSegmentedControl(
          segments: DesktopWidgetPane.panes(for: widget.kind).map { .init(value: $0, title: Self.title(of: $0)) },
          selection: pane
        ) { model.pane = $0 }
        .accessibilityIdentifier("widgets.panes")
        if scrolls {
          ScrollView {
            WidgetEditor(widget: widget, screens: screens, panes: [pane], compact: true)
              .padding(.bottom, 12)
          }
          .frame(maxHeight: .infinity)
        } else {
          WidgetEditor(widget: widget, screens: screens, panes: [pane], compact: true)
        }
      }
    } else {
      let gallery = VStack(alignment: .leading, spacing: 10) {
        if !model.widgets.isEmpty {
          Text("No widget selected")
            .font(.panel(.sectionHeader))
            .accessibilityAddTraits(.isHeader)
          Text(verbatim: L("Click a widget on the canvas or in Layers to change it."))
            .font(.panel(.callout))
            .foregroundStyle(theme.surface.muted.color)
            .padding(.bottom, 8)
        }
        Text("Start with a ready-made widget")
          .font(.panel(.sectionHeader))
          .accessibilityAddTraits(.isHeader)
        Text(verbatim: L("Add a finished widget in one click, then change anything about it."))
          .font(.panel(.callout))
          .foregroundStyle(theme.surface.muted.color)
        ReadyMadeWidgetsGrid(minimumWidth: 140)
      }
      if scrolls {
        ScrollView { gallery.padding(.bottom, 12) }
          .frame(maxHeight: .infinity)
      } else {
        gallery
      }
    }
  }

  /// Which widget the inspector edits: what it says now, its kind and its display.
  private func editing(_ widget: DesktopWidget, screens: [DesktopWidgetController.Screen]) -> some View {
    let model = controller.widgetsSettings
    let text = model.text(for: widget)
    let kind = WidgetsSettingsSection.title(of: widget.kind)
    let place = model.placementTitle(for: widget, among: screens)
    return HStack(spacing: 10) {
      SymbolTile(
        systemImage: WidgetsSettingsSection.symbol(of: widget.kind), color: SettingsSection.widgets.tileColor,
        size: .medium)
      VStack(alignment: .leading, spacing: 1) {
        Text(verbatim: text)
          .font(.panel(.calloutStrong))
          .lineLimit(1)
          .truncationMode(.tail)
        Text(verbatim: widget.isShown ? "\(kind) · \(place)" : "\(kind) · \(place) · \(L("Hidden"))")
          .font(.panel(.caption))
          .foregroundStyle(theme.surface.muted.color)
          .lineLimit(1)
      }
      .frame(minWidth: 0, maxWidth: .infinity, alignment: .leading)
    }
    .accessibilityElement(children: .ignore)
    .accessibilityLabel(Text(verbatim: L("Editing \(text)")))
  }

  static func title(of pane: DesktopWidgetPane) -> String {
    switch pane {
    case .content: L("Content")
    case .text: L("Text")
    case .style: L("Style")
    case .position: L("Position")
    }
  }
}

// MARK: - Ready-made widgets

/// The Ready-made button: a popover of every ready-made widget.
struct ReadyMadeWidgetsButton: View {
  @State private var isPresented = false

  var body: some View {
    Button {
      isPresented = true
    } label: {
      Label("Ready-made", systemImage: "sparkles")
    }
    .buttonStyle(.panelSecondary(size: .small))
    .fixedSize()
    .help(L("Add a finished widget in one click, then change anything about it."))
    .accessibilityIdentifier("widgets.ready-made")
    .popover(isPresented: $isPresented, arrowEdge: .bottom) {
      ReadyMadeWidgetsPopover { isPresented = false }
        .panelPresentationLocale()
    }
  }
}

/// The Ready-made button's popover: every ready-made widget, a click adding it and closing.
private struct ReadyMadeWidgetsPopover: View {
  let close: () -> Void

  @Environment(\.panelTheme) private var theme

  var body: some View {
    VStack(alignment: .leading, spacing: 10) {
      Text("Ready-made widgets")
        .font(.panel(.headline))
        .accessibilityAddTraits(.isHeader)
      Text(verbatim: L("Add a finished widget in one click, then change anything about it."))
        .font(.panel(.callout))
        .foregroundStyle(theme.surface.muted.color)
      ScrollView {
        ReadyMadeWidgetsGrid(minimumWidth: 150, added: close)
          .padding(.bottom, 4)
      }
    }
    .padding(16)
    .frame(width: 540, height: 480)
  }
}

/// The ready-made widgets as cards, each drawn as the desktop would draw it over the wallpaper.
struct ReadyMadeWidgetsGrid: View {
  var minimumWidth: CGFloat
  /// Called once a card's widgets are asked for, so a popover can close.
  var added: () -> Void = {}

  @Environment(PanelController.self) private var controller

  var body: some View {
    let model = controller.widgetsSettings
    let display = model.presetDisplay()
    let backdrop = WidgetSampleBackdrop.image(model)
    LazyVGrid(columns: [GridItem(.adaptive(minimum: minimumWidth), spacing: 10)], alignment: .leading, spacing: 12) {
      ForEach(DesktopWidgetPreset.allCases, id: \.self) { preset in
        ReadyMadeWidgetCard(preset: preset, display: display, backdrop: backdrop, added: added)
      }
    }
  }

  static func title(of preset: DesktopWidgetPreset) -> String {
    switch preset {
    case .bigClock: L("Big clock")
    case .clockAndDate: L("Clock and date")
    case .neonClock: L("Neon clock")
    case .clockFace: L("Clock face")
    case .worldClocks: L("World clocks")
    case .lunarDate: L("Lunar date")
    case .monthCalendar: L("Month calendar")
    case .countdown: L("Countdown")
    case .greeting: L("Greeting and date")
    case .note: L("Gradient note")
    case .status: L("Battery and sun")
    }
  }
}

/// One ready-made widget: its picture and its name. A click adds it to the desktop and opens it in
/// the editor; it is disabled when it would pass the limit of widgets.
private struct ReadyMadeWidgetCard: View {
  let preset: DesktopWidgetPreset
  let display: CGSize
  let backdrop: CGImage?
  let added: () -> Void

  @Environment(PanelController.self) private var controller
  @Environment(\.panelTheme) private var theme
  @State private var isHovering = false

  var body: some View {
    let model = controller.widgetsSettings
    let widgets = model.widgets(of: preset)
    let key = PanelActionCoordinator.key("addDesktopWidgetPreset", detail: preset.rawValue)
    let title = ReadyMadeWidgetsGrid.title(of: preset)
    let fits = model.widgets.count + widgets.count <= DesktopWidgetStore.limit
    let shape = RoundedRectangle(cornerRadius: 8, style: .continuous)
    Button {
      controller.launch(key) { try await controller.addDesktopWidgetPreset(preset) }
      added()
    } label: {
      VStack(alignment: .leading, spacing: 6) {
        ZStack {
          WidgetSampleBackdrop(image: backdrop)
          WidgetSample(widgets: widgets, display: display)
        }
        .aspectRatio(16 / 10, contentMode: .fit)
        .clipShape(shape)
        .overlay {
          shape.strokeBorder(
            isHovering ? theme.accent.accent.color : theme.surface.divider.color, lineWidth: isHovering ? 2 : 0.5)
        }
        Text(verbatim: title)
          .font(.panel(.calloutStrong))
          .foregroundStyle(theme.surface.text.color)
          .lineLimit(1)
      }
      .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    .onHover { isHovering = $0 }
    .disabled(!fits || controller.isBusy(key))
    .panelDisabledOpacity(fits)
    .help(title)
    .accessibilityLabel(Text(verbatim: L("Add \(title)")))
    .accessibilityIdentifier("widgets.ready-made.\(preset.rawValue)")
  }
}

// MARK: - Styles

/// The Style row: every finished look drawn on the selected widget's own words, a click applying it.
struct WidgetStyleSwatches: View {
  let widget: DesktopWidget

  @Environment(PanelController.self) private var controller
  @Environment(\.panelTheme) private var theme

  var body: some View {
    let model = controller.widgetsSettings
    let display = model.presetDisplay()
    let backdrop = WidgetSampleBackdrop.image(model)
    let key = PanelActionCoordinator.key("styleDesktopWidget", id: widget.id)
    let shape = RoundedRectangle(cornerRadius: 6, style: .continuous)
    LazyVGrid(columns: [GridItem(.adaptive(minimum: 84, maximum: 140), spacing: 8)], alignment: .leading, spacing: 8) {
      ForEach(DesktopWidget.StylePreset.allCases, id: \.self) { preset in
        let title = WidgetsSettingsSection.title(of: preset)
        Button {
          let id = widget.id
          controller.launch(key) { try await controller.changeDesktopWidget(id, .style(preset)) }
        } label: {
          VStack(spacing: 4) {
            ZStack {
              WidgetSampleBackdrop(image: backdrop)
              WidgetSample(widgets: [sample(preset, model: model)], display: display, maximumScale: 0.6)
            }
            .frame(height: 48)
            .clipShape(shape)
            .overlay { shape.strokeBorder(theme.surface.divider.color, lineWidth: 0.5) }
            Text(verbatim: title)
              .font(.panel(.caption))
              .foregroundStyle(theme.surface.muted.color)
              .lineLimit(1)
              .minimumScaleFactor(0.8)
          }
          .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(controller.isBusy(key))
        .help(title)
        .accessibilityLabel(Text(verbatim: title))
        .accessibilityIdentifier("widgets.style.\(preset.rawValue)")
      }
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .accessibilityElement(children: .contain)
  }

  /// The widget as the look would leave it, upright, alone in the middle of its display.
  private func sample(_ preset: DesktopWidget.StylePreset, model: DesktopWidgetsSettingsModel) -> DesktopWidget {
    var sample = model.shown(widget)
    sample.rotation = 0
    sample.isShown = true
    sample.alignment = .center
    sample.x = 0.5
    sample.y = 0.5
    preset.apply(to: &sample)
    return sample
  }
}

// MARK: - Samples

/// What a sample is drawn over: the main display's wallpaper as the canvas shows it, filling the
/// card, else a quiet well. The well sets the size and the picture is its overlay, so a wallpaper
/// of another shape than the card is cropped to the card instead of making it larger and spilling
/// over the card beside it.
struct WidgetSampleBackdrop: View {
  let image: CGImage?

  @Environment(\.panelTheme) private var theme

  var body: some View {
    theme.surface.mediaWell.color
      .overlay {
        if let image {
          Image(decorative: image, scale: 1)
            .resizable()
            .interpolation(.medium)
            .aspectRatio(contentMode: .fill)
        }
      }
      .clipped()
  }

  /// The frame of the main display's wallpaper the canvas has; nil before it has one.
  @MainActor
  static func image(_ model: DesktopWidgetsSettingsModel) -> CGImage? {
    let screens = model.screens()
    guard let screen = screens.first(where: \.isMain) ?? screens.first else { return nil }
    return model.wallpaperFrame(on: screen.displayID)
  }
}

/// Widgets drawn by the desktop's own view, zoomed to fill a small box together: a ready-made
/// preset's, laid out on `display` as the desktop will lay them out, or a widget in one of the
/// looks. `maximumScale` keeps a small widget from being drawn larger than a share of its size.
struct WidgetSample: View {
  let widgets: [DesktopWidget]
  let display: CGSize
  var maximumScale: CGFloat = 1

  @Environment(PanelController.self) private var controller

  var body: some View {
    GeometryReader { proxy in
      let model = controller.widgetsSettings
      let box = proxy.size
      let frames = widgets.map { model.frame(of: $0, in: display, scale: 1) }
      let union = frames.reduce(CGRect.null) { $0.union($1) }
      if !union.isNull, union.width > 0, union.height > 0, box.width > 0, box.height > 0 {
        let zoom = min(box.width * 0.86 / union.width, box.height * 0.78 / union.height, maximumScale)
        let scaled = NSRect(x: 0, y: 0, width: display.width * zoom, height: display.height * zoom)
        ZStack(alignment: .topLeading) {
          // Back to front, as the desktop stacks them.
          ForEach(Array(widgets.indices.reversed()), id: \.self) { index in
            let content = model.content(for: widgets[index], scale: zoom)
            let size = DesktopWidgetRendering.frame(for: content, widget: widgets[index], display: scaled).size
            WidgetDrawing(drawing: content.drawing, look: content.look, padding: content.padding)
              .frame(width: size.width, height: size.height)
              .position(
                x: (frames[index].midX - union.midX) * zoom + box.width / 2,
                y: (frames[index].midY - union.midY) * zoom + box.height / 2)
          }
        }
        .frame(width: box.width, height: box.height)
      }
    }
    .allowsHitTesting(false)
    .accessibilityHidden(true)
  }
}
