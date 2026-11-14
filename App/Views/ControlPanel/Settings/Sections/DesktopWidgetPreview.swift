import AppKit
import SwiftUI

/// A picture of a display for arranging its widgets: the workspace's canvas, and the Arrange row of
/// the search results. It shows the frame the display's wallpaper draws (its first at once, then
/// one past any intro or fade-in once it has played a moment) and the widgets shown on it drawn as
/// the desktop draws them, scaled down and stacked in the layers' order. Without a frame the
/// picture shows the wallpaper's still, and a note under it says why when one is to come.
///
/// Dragging a widget moves it; the position is saved when it is let go. While it moves, the
/// display's centre lines show faintly, and the widget snaps to them, to the thirds, to a margin
/// from the edges and to the other widgets' edges and centres, drawing a guide along each line it
/// lies on (`DesktopWidgetSnapping`); holding Command places it freely. The selected widget is
/// outlined above every layer, so it can be found even under another one, with a handle at each
/// corner that resizes it about its middle and a knob that turns it (snapping to every 15°, again
/// unless Command is held; a double click on the knob turns it back upright); its size or turn
/// shows under it meanwhile. The arrow keys move the selected widget a point of the display, ten
/// with Shift. A click on the wallpaper around the widgets, or Escape, selects nothing, so the
/// picture shows the widgets as the desktop will, without the outline and handles. A hidden widget
/// is drawn, faded, only while it is selected. The words are those of when the page was drawn: the
/// preview runs no clock of its own and the frame does not move. The rows of the editor are the
/// keyboard's and VoiceOver's way to the same things, so the picture itself is hidden from
/// VoiceOver.
struct DesktopWidgetPreview: View {
  let screen: DesktopWidgetController.Screen
  /// The largest the picture gets; nil fills what it is offered, as the workspace's canvas does.
  var limit: CGSize?

  /// The Arrange row's picture in the search results.
  static let rowLimit = CGSize(width: 480, height: 270)

  @Environment(PanelController.self) private var controller
  @Environment(\.panelTheme) private var theme
  @FocusState private var isFocused: Bool
  /// The middle of the selected widget when a handle's drag began, which the drag turns or resizes
  /// it about.
  @State private var pivot: CGPoint?

  var body: some View {
    let model = controller.widgetsSettings
    let display = screen.frame.size
    let aspect = display.height > 0 ? display.width / display.height : 16 / 10
    VStack(spacing: 6) {
      GeometryReader { proxy in
        let size = proxy.size
        let scale = display.width > 0 ? size.width / display.width : 1
        let widgets = model.widgets(on: screen)
        let selected = widgets.first { $0.id == model.selectedID }
        ZStack(alignment: .topLeading) {
          backdrop(
            frame: model.wallpaperFrame(on: screen.displayID), still: model.wallpaperStill(on: screen.displayID),
            size: size)
          ForEach(widgets) { widget in
            item(model.shown(widget), saved: widget, in: size, scale: scale)
          }
          guides(in: size)
          if let selected {
            let frame = model.frame(of: model.shown(selected), in: size, scale: scale)
            outline(frame)
            handles(selected, frame: frame, in: size)
            readout(selected, frame: frame, in: size)
          }
        }
        .coordinateSpace(.named(Self.space))
      }
      .aspectRatio(aspect, contentMode: .fit)
      .frame(maxWidth: limit?.width ?? .infinity, maxHeight: limit?.height ?? .infinity)
      if model.waitsForWallpaperToSettle(on: screen.displayID) {
        Text("Showing the wallpaper’s preview image until it has played for a moment.")
          .font(.panel(.footnote))
          .foregroundStyle(theme.surface.muted.color)
          .multilineTextAlignment(.center)
      }
    }
    .task(id: model.frameRequest(on: screen.displayID)) {
      guard let request = model.frameRequest(on: screen.displayID) else { return }
      await model.loadWallpaperFrame(request)
    }
    .frame(maxWidth: .infinity, maxHeight: limit == nil ? .infinity : nil)
    .focusable()
    .focused($isFocused)
    .focusEffectDisabled()
    .onKeyPress(keys: [.upArrow, .downArrow, .leftArrow, .rightArrow], phases: [.down, .repeat]) { press in
      nudge(press)
    }
    .onKeyPress(.escape) {
      guard controller.widgetsSettings.selectedID != nil else { return .ignored }
      controller.widgetsSettings.clearSelection()
      return .handled
    }
    .accessibilityHidden(true)
  }

  private static let space = "desktop-widget-preview"
  /// How far above the selected widget its turn knob sits, in the picture's points.
  private static let knobDistance: CGFloat = 22
  private static let handleSide: CGFloat = 9

  /// The frame the display's wallpaper drew, which has the display's shape and the wallpaper's
  /// placement; else its still, or a quiet well while it has none or it loads: no glyph, which the
  /// widgets would sit on.
  private func backdrop(frame: CGImage?, still: PanelImageSource?, size: CGSize) -> some View {
    let shape = RoundedRectangle(cornerRadius: 8, style: .continuous)
    return ZStack {
      theme.surface.mediaWell.color
      if let frame {
        Image(decorative: frame, scale: 1)
          .resizable()
          .interpolation(.high)
          .aspectRatio(contentMode: .fill)
      } else {
        PanelImage(source: still, pointSize: max(size.width, size.height), contentMode: .fill)
      }
    }
    .frame(width: size.width, height: size.height)
    .clipShape(shape)
    .overlay { shape.strokeBorder(theme.surface.divider.color, lineWidth: 0.5) }
    .contentShape(shape)
    .onTapGesture {
      isFocused = true
      controller.widgetsSettings.clearSelection()
    }
  }

  private func item(_ widget: DesktopWidget, saved: DesktopWidget, in size: CGSize, scale: CGFloat) -> some View {
    let model = controller.widgetsSettings
    let content = model.content(for: widget, scale: scale)
    let frame = model.frame(of: widget, in: size, scale: scale)
    return WidgetDrawing(drawing: content.drawing, look: content.look, padding: content.padding)
      .frame(width: frame.width, height: frame.height)
      .opacity(widget.isShown ? 1 : 0.35)
      .contentShape(Rectangle())
      .pointerStyle(.grabIdle)
      .contextMenu { menu(saved) }
      .position(x: frame.midX, y: frame.midY)
      .gesture(
        DragGesture(minimumDistance: 1, coordinateSpace: .named(Self.space))
          .onChanged { drag in
            isFocused = true
            model.drag(
              saved, by: drag.translation, in: size, scale: scale, on: screen,
              snaps: !NSEvent.modifierFlags.contains(.command))
          }
          .onEnded { _ in model.endDrag() }
      )
      .onTapGesture {
        isFocused = true
        model.select(widget.id)
      }
  }

  /// A widget's context menu on the canvas: the layer and visibility actions of its row in the list.
  @ViewBuilder
  private func menu(_ widget: DesktopWidget) -> some View {
    let model = controller.widgetsSettings
    let order = model.widgets.map(\.id)
    let index = order.firstIndex(of: widget.id) ?? 0
    let id = widget.id
    Button(widget.isShown ? L("Hide on the desktop") : L("Show on the desktop")) {
      model.commit(id, "shown", to: !widget.isShown, policy: .dropDuplicates) { .shown($0) }
    }
    Button("Duplicate") {
      controller.launch(PanelActionCoordinator.key("duplicateDesktopWidget", id: id)) {
        try await controller.duplicateDesktopWidget(id)
      }
    }
    .disabled(order.count >= DesktopWidgetStore.limit)
    Divider()
    Button("Bring to Front") { move(id, to: 0) }.disabled(index == 0)
    Button("Send to Back") { move(id, to: order.count - 1) }.disabled(index >= order.count - 1)
  }

  private func move(_ id: String, to index: Int) {
    controller.launch(PanelActionCoordinator.key("moveDesktopWidget")) {
      try await controller.moveDesktopWidget(id, to: index)
    }
  }

  /// The selected widget's outline, above every layer: a dark hairline under the accent one keeps
  /// it on a light wallpaper as on a dark one.
  private func outline(_ frame: CGRect) -> some View {
    let shape = RoundedRectangle(cornerRadius: 3, style: .continuous)
    return ZStack {
      shape.strokeBorder(theme.surface.markFill.color, lineWidth: 2.5)
      shape.strokeBorder(theme.accent.accent.color, lineWidth: 1.25)
    }
    .frame(width: frame.width + 2, height: frame.height + 2)
    .position(x: frame.midX, y: frame.midY)
    .allowsHitTesting(false)
  }

  // MARK: Handles

  /// The corner handles that resize the selected widget and the knob that turns it. The knob sits
  /// above the widget, or below it when the widget is at the top of the display.
  private func handles(_ widget: DesktopWidget, frame: CGRect, in size: CGSize) -> some View {
    let outer = frame.insetBy(dx: -1, dy: -1)
    let corners: [(FrameResizePosition, CGPoint)] = [
      (.topLeading, CGPoint(x: outer.minX, y: outer.minY)),
      (.topTrailing, CGPoint(x: outer.maxX, y: outer.minY)),
      (.bottomLeading, CGPoint(x: outer.minX, y: outer.maxY)),
      (.bottomTrailing, CGPoint(x: outer.maxX, y: outer.maxY)),
    ]
    let above = outer.minY - Self.knobDistance >= Self.handleSide
    let stem = CGPoint(x: outer.midX, y: above ? outer.minY : outer.maxY)
    let knob = CGPoint(x: outer.midX, y: above ? outer.minY - Self.knobDistance : outer.maxY + Self.knobDistance)
    let center = CGPoint(x: frame.midX, y: frame.midY)
    return ZStack(alignment: .topLeading) {
      Path { path in
        path.move(to: stem)
        path.addLine(to: knob)
      }
      .stroke(theme.accent.accent.color, lineWidth: 1)
      .allowsHitTesting(false)
      ForEach(corners.indices, id: \.self) { index in
        handle(circle: false)
          .pointerStyle(.frameResize(position: corners[index].0))
          .position(corners[index].1)
          .gesture(resizing(widget, around: center))
      }
      handle(circle: true)
        .position(knob)
        .onTapGesture(count: 2) { turnUpright(widget) }
        .gesture(turning(widget, around: center))
    }
    .frame(width: size.width, height: size.height)
  }

  /// A handle: light, with the accent's edge over a dark hairline, readable on any wallpaper; its
  /// click target is larger than what is drawn.
  private func handle(circle: Bool) -> some View {
    let side = Self.handleSide
    let shape = RoundedRectangle(cornerRadius: circle ? side / 2 : 2, style: .continuous)
    return shape.fill(theme.surface.markGlyph.color)
      .overlay { shape.strokeBorder(theme.accent.accent.color, lineWidth: 1.25) }
      .background { shape.stroke(theme.surface.markFill.color, lineWidth: 2.5) }
      .frame(width: side, height: side)
      .frame(width: side + 10, height: side + 10)
      .contentShape(Rectangle())
  }

  private func resizing(_ widget: DesktopWidget, around center: CGPoint) -> some Gesture {
    let model = controller.widgetsSettings
    return DragGesture(minimumDistance: 1, coordinateSpace: .named(Self.space))
      .onChanged { drag in
        isFocused = true
        let pivot = pivot ?? center
        self.pivot = pivot
        let start = hypot(drag.startLocation.x - pivot.x, drag.startLocation.y - pivot.y)
        let now = hypot(drag.location.x - pivot.x, drag.location.y - pivot.y)
        guard start > 1 else { return }
        model.resize(widget, by: now / start)
      }
      .onEnded { _ in
        pivot = nil
        model.endDrag()
      }
  }

  private func turning(_ widget: DesktopWidget, around center: CGPoint) -> some Gesture {
    let model = controller.widgetsSettings
    return DragGesture(minimumDistance: 1, coordinateSpace: .named(Self.space))
      .onChanged { drag in
        isFocused = true
        let pivot = pivot ?? center
        self.pivot = pivot
        let turn =
          DesktopWidgetsSettingsModel.angle(of: drag.location, around: pivot)
          - DesktopWidgetsSettingsModel.angle(of: drag.startLocation, around: pivot)
        model.rotate(widget, by: turn, snaps: !NSEvent.modifierFlags.contains(.command))
      }
      .onEnded { _ in
        pivot = nil
        model.endDrag()
      }
  }

  private func turnUpright(_ widget: DesktopWidget) {
    controller.widgetsSettings.commit(widget.id, "rotation", to: 0) { .rotation($0) }
  }

  /// The size or the turn a handle is giving the selected widget, under it while the handle moves.
  @ViewBuilder
  private func readout(_ widget: DesktopWidget, frame: CGRect, in size: CGSize) -> some View {
    let model = controller.widgetsSettings
    if let drag = model.drag, drag.id == widget.id, drag.size != nil || drag.rotation != nil {
      let text = drag.size.map { L("\($0) pt") } ?? drag.rotation.map { L("\($0)°") } ?? ""
      let below = frame.maxY + Self.knobDistance + 14 <= size.height
      Text(verbatim: text)
        .font(.panel(.badge).monospacedDigit())
        .foregroundStyle(theme.surface.markGlyph.color)
        .padding(.horizontal, 7)
        .padding(.vertical, 3)
        .background(Capsule().fill(theme.surface.markFill.color))
        .fixedSize()
        .position(
          x: min(max(frame.midX, 30), max(size.width - 30, 30)),
          y: below ? frame.maxY + Self.knobDistance + 2 : max(frame.minY - Self.knobDistance - 14, 10))
        .allowsHitTesting(false)
    }
  }

  // MARK: Keyboard

  /// An arrow key moves the selected widget a point of the display, ten with Shift.
  private func nudge(_ press: KeyPress) -> KeyPress.Result {
    let model = controller.widgetsSettings
    guard let widget = model.widgets(on: screen).first(where: { $0.id == model.selectedID }) else {
      return .ignored
    }
    let step: CGFloat = press.modifiers.contains(.shift) ? 10 : 1
    let offset: CGSize =
      switch press.key {
      case .upArrow: CGSize(width: 0, height: -step)
      case .downArrow: CGSize(width: 0, height: step)
      case .leftArrow: CGSize(width: -step, height: 0)
      case .rightArrow: CGSize(width: step, height: 0)
      default: .zero
      }
    guard offset != .zero else { return .ignored }
    model.nudge(widget, by: offset, on: screen)
    return .handled
  }

  // MARK: Guides

  /// While a widget is dragged: the display's centre lines, faint and dashed until the widget lies
  /// on one, and a solid guide along every line it snapped to.
  private func guides(in size: CGSize) -> some View {
    let model = controller.widgetsSettings
    let moving = model.drag.map { $0.size == nil && $0.rotation == nil } ?? false
    let snapped = model.drag?.guides ?? []
    let faint =
      moving
      ? DesktopWidgetSnapping.displayGuides(in: size).filter { line in
        !snapped.contains { $0.axis == line.axis && abs($0.position - line.position) < 1.5 }
      }
      : []
    return ZStack(alignment: .topLeading) {
      ForEach(Array(faint.enumerated()), id: \.offset) { _, guide in
        path(guide).stroke(theme.surface.controlRim.color, style: StrokeStyle(lineWidth: 1, dash: [3, 3]))
      }
      ForEach(Array(snapped.enumerated()), id: \.offset) { _, guide in
        path(guide).stroke(theme.surface.markFill.color, lineWidth: 2.5)
        path(guide).stroke(
          theme.accent.accent.color,
          style: StrokeStyle(lineWidth: 1, dash: guide.kind == .third || guide.kind == .margin ? [4, 2] : []))
      }
    }
    .frame(width: size.width, height: size.height)
    .allowsHitTesting(false)
  }

  private func path(_ guide: DesktopWidgetSnapping.Guide) -> Path {
    Path { path in
      // On the half point, so a one-point line is crisp.
      let position = guide.position.rounded(.down) + 0.5
      switch guide.axis {
      case .vertical:
        path.move(to: CGPoint(x: position, y: guide.start))
        path.addLine(to: CGPoint(x: position, y: guide.end))
      case .horizontal:
        path.move(to: CGPoint(x: guide.start, y: position))
        path.addLine(to: CGPoint(x: guide.end, y: position))
      }
    }
  }
}

/// A widget drawn by the same view the desktop's widget window uses.
struct WidgetDrawing: NSViewRepresentable {
  let drawing: DesktopWidgetRendering.Drawing
  let look: DesktopWidgetRendering.Look
  let padding: CGFloat

  func makeNSView(context: Context) -> DesktopWidgetView { DesktopWidgetView() }

  func updateNSView(_ view: DesktopWidgetView, context: Context) {
    view.update(drawing: drawing, look: look, padding: padding)
  }
}
