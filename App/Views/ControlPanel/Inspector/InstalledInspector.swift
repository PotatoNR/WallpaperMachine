import AppKit
import SwiftUI

/// The inspector beside the Installed page: the selected wallpaper's preview, actions and options.
///
/// Top to bottom: the header (preview, name, facts, Apply, favorite, the menu, tags), what the app
/// has to say about the wallpaper, the Compatibility check, Black bars (video) and Position on
/// screen (a still image the app packaged), then the wallpaper's own settings: General
/// configuration, Displays, Collections, Wallpaper Engine options, Presets and the authored
/// properties. While an edit waits to be applied, a footer holds Revert and Apply changes, and
/// Apply changes is the accent button in place of Apply wallpaper (`InspectorPolicy.primaryAction`).
struct InstalledInspector: View {
  @Environment(PanelController.self) private var controller
  @Environment(\.panelTheme) private var theme

  var body: some View {
    Group {
      // The row is nil for a wallpaper that is not installed (a stale selection).
      if let id = controller.selectedWallpaperID, let row = controller.libraryRow(id: id) {
        // Keyed by the wallpaper: another one starts at the top, with the sections open as they
        // are by default and nothing typed or picked left over.
        InspectorContent(row: row).id(id)
      } else {
        PanelEmptyState(
          "Select a wallpaper", systemImage: "photo",
          description: "Preview, details and options appear here.")
      }
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .background(theme.surface.background.color)
    // Every link in the inspector goes through the panel's allowlist.
    .environment(
      \.openURL, OpenURLAction { url in ExternalLink.open(url) ? .handled : .discarded }
    )
    .onChange(of: controller.imagePlacementState, initial: true) { _, state in
      controller.inspector.placement.observe(state)
    }
    .accessibilityElement(children: .contain)
    .accessibilityLabel(L("Wallpaper details"))
  }
}

private struct InspectorContent: View {
  let row: LibraryRow

  @Environment(PanelController.self) private var controller
  @Environment(\.panelTheme) private var theme
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  /// The row the last edit came from, which the footer that edit brings in scrolls clear of itself.
  @State private var editedRow = InspectorEditedRow()
  /// Counts the times Apply wallpaper is asked to take the focus that Apply changes or Revert held
  /// when it went away with the footer.
  @State private var applyFocusRequests = 0

  var body: some View {
    let id = row.id
    let options = controller.inspectorOptions(for: id)
    let showsFooter = InspectorPolicy.showsFooter(options)
    ScrollViewReader { proxy in
      scrollingContent(id: id, options: options, showsFooter: showsFooter)
        // The footer comes in over the bottom of the content, often over the row whose edit
        // brought it in: that row is scrolled clear of it, as little as it takes, once the footer
        // has taken its room. A footer that comes in with a wallpaper scrolls nothing.
        .onChange(of: showsFooter) { _, shows in
          guard shows, let edited = editedRow.take() else { return }
          Task { @MainActor in
            await Task.yield()
            withAnimation(reduceMotion ? nil : .easeOut(duration: 0.18)) { proxy.scrollTo(edited) }
          }
        }
    }
    .environment(\.inspectorEditedRow, editedRow)
    // A status line: the edit that leaves something to apply is said aloud, not only drawn. It is
    // said from here, which exists in both states: a footer inserted with its line already set
    // never sees the line change.
    .announcing(showsFooter ? L("You have unapplied changes.") : nil)
  }

  private func scrollingContent(id: String, options: InspectorOptions?, showsFooter: Bool) -> some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 16) {
        InspectorHeader(
          row: row, applyIsPrimary: InspectorPolicy.primaryAction(options) == .applyWallpaper,
          applyFocusRequests: applyFocusRequests)
        InspectorNotices(row: row)
        if let compatibility = controller.compatibilityState, compatibility.wallpaperID == id {
          CompatibilityCard(state: compatibility, row: row)
        }
        if let letterbox = controller.letterboxState, letterbox.wallpaperID == id {
          LetterboxCard(state: letterbox)
        }
        if InspectorPolicy.isPackagedStill(id), let placement = controller.imagePlacementState,
          placement.wallpaperID == id
        {
          PlacementCard(state: placement, row: row)
        }
        if let options {
          if !options.isSupported {
            InspectorNotice(tone: .warning) {
              Text("This wallpaper cannot be rendered on this Mac.")
            }
          }
          GeneralConfigurationCard(options: options)
          PropertiesCards(options: options)
          DisplaysCard(options: options)
          CollectionsCard(wallpaperID: id)
          EngineOptionsCard(options: options)
        } else {
          LoadingOptions()
          CollectionsCard(wallpaperID: id)
        }
      }
      .padding(16)
    }
    .background(alignment: .top) { InspectorWash(row: row) }
    .safeAreaInset(edge: .bottom, spacing: 0) {
      // Only the footer fades; the content above it does not slide.
      VStack(spacing: 0) {
        if let options, showsFooter {
          InspectorFooter(options: options) { applyFocusRequests += 1 }.transition(.opacity)
        }
      }
      .animation(reduceMotion ? nil : .easeOut(duration: 0.18), value: showsFooter)
    }
  }
}

/// The inspector row the last edit came from (`note`), which the footer that edit brings in
/// scrolls clear of itself. The row carries the same id (`.id(_:)`), so the scroll view finds it.
/// Noting an edit redraws nothing.
@MainActor
final class InspectorEditedRow {
  private var noted: (id: String, at: ContinuousClock.Instant)?

  func note(_ id: String) { noted = (id, .now) }

  /// The row edited in the last two seconds, once: an older edit did not bring the footer in.
  func take() -> String? {
    defer { noted = nil }
    guard let noted, ContinuousClock.now - noted.at < .seconds(2) else { return nil }
    return noted.id
  }
}

extension EnvironmentValues {
  /// Nil outside the Installed inspector, whose rows then note nothing.
  @Entry var inspectorEditedRow: InspectorEditedRow? = nil
}

/// Shown until the bridge answers for this wallpaper.
private struct LoadingOptions: View {
  @Environment(\.panelTheme) private var theme

  var body: some View {
    HStack(spacing: 8) {
      ProgressRing(value: nil, lineWidth: 1.5).frame(width: 12, height: 12)
      Text("Loading wallpaper options…")
        .font(.panel(.callout))
        .foregroundStyle(theme.surface.muted.color)
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .padding(.horizontal, 12)
    .accessibilityElement(children: .combine)
  }
}

/// Revert and Apply changes, drawn only while something waits to be applied
/// (`InspectorPolicy.showsFooter`), over a line saying so and which settings never wait. Apply
/// changes takes the accent from Apply wallpaper while it is drawn.
///
/// Both buttons leave with the footer once they have done their work, so it is said aloud, and the
/// keyboard or VoiceOver focus one of them held goes to Apply wallpaper (`onFocusLeaves`).
struct InspectorFooter: View {
  let options: InspectorOptions
  var onFocusLeaves: () -> Void = {}

  @Environment(PanelController.self) private var controller
  @Environment(\.panelTheme) private var theme
  @Environment(\.panelAnnouncer) private var announcer
  @FocusState private var focused: Action?
  @AccessibilityFocusState private var voiceOverFocused: Action?
  /// Off until a double click's second click could have come: the footer comes in under the pointer
  /// that made the edit, and must not take that click for Apply changes or Revert.
  @State private var takesClicks = false

  private enum Action: Hashable { case revert, apply }

  var body: some View {
    let id = options.wallpaperID
    let applyKey = InspectorAction.apply(id)
    let revertKey = InspectorAction.revert(id)
    VStack(alignment: .leading, spacing: 8) {
      VStack(alignment: .leading, spacing: 2) {
        Text("You have unapplied changes.")
          .font(.system(size: 11.5, weight: .medium))
          .foregroundStyle(theme.surface.text.color)
        Text("Audio, scaling mode, position and frame rate take effect immediately.")
          .font(.panel(.caption))
          .foregroundStyle(theme.surface.muted.color)
      }
      .frame(maxWidth: .infinity, alignment: .leading)
      .accessibilityElement(children: .combine)
      HStack(spacing: 8) {
        Button("Revert") {
          run(.revert, key: revertKey, saying: L("Changes reverted.")) { try await controller.revert(id) }
        }
        .buttonStyle(.panelSecondary(size: .regular, expands: true))
        .disabled(!options.canRevert || controller.isBusy(revertKey))
        .focused($focused, equals: .revert)
        .accessibilityFocused($voiceOverFocused, equals: .revert)
        .accessibilityIdentifier("inspector.revert")
        Button("Apply changes") {
          run(.apply, key: applyKey, saying: L("Changes applied.")) { try await controller.apply(id) }
        }
        .buttonStyle(.panelPrimary(size: .regular, expands: true))
        .disabled(!options.canApply || controller.isBusy(applyKey))
        .focused($focused, equals: .apply)
        .accessibilityFocused($voiceOverFocused, equals: .apply)
        .accessibilityIdentifier("inspector.applyChanges")
      }
      .allowsHitTesting(takesClicks)
    }
    .padding(.horizontal, 16)
    .padding(.vertical, 10)
    .background(.bar)
    .overlay(alignment: .top) {
      Rectangle().fill(theme.surface.divider.color).frame(height: 0.5)
    }
    .task {
      try? await Task.sleep(for: .seconds(NSEvent.doubleClickInterval))
      takesClicks = true
    }
  }

  /// Runs Apply changes or Revert. Once nothing waits any more, the footer is about to go: that is
  /// said, and the focus the button held is handed on.
  private func run(
    _ action: Action, key: String, saying done: String,
    _ work: @escaping @MainActor () async throws -> Void
  ) {
    let heldFocus = focused == action || voiceOverFocused == action
    let id = options.wallpaperID
    controller.launch(key) { [controller, announcer, onFocusLeaves] in
      try await work()
      guard controller.inspectorOptions(for: id)?.hasChanges != true else { return }
      announcer.post(done)
      if heldFocus { onFocusLeaves() }
    }
  }
}
