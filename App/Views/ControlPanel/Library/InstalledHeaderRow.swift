import SwiftUI

/// How much room either bar above the Library grid has (this header row and the views row,
/// `InstalledScopeBar`): room for all the words, for fewer, or for the fewest and closer together
/// (the page beside an inspector in the smallest window). Each bar picks its tier with a
/// `ViewThatFits` around the whole row and says in its own documentation what each tier drops;
/// this header row keeps only its icons from `compact` on.
enum HeaderTier {
  case regular, compact, tight

  var showsLabels: Bool { self == .regular }

  /// The room inside a capsule (`ToolbarCapsuleButtonStyle`): less in the tight tier, so the
  /// controls stay on one row.
  var capsulePadding: CGFloat { self == .tight ? 7 : 10 }
}

/// The slim row under the toolbar: Filter and the sort on the left; Select, Refresh and Import on
/// the right. When the page column is too narrow for the words, every control keeps its place and
/// loses its label, which stays as its help and accessibility name.
struct InstalledHeaderRow: View {
  var body: some View {
    ViewThatFits(in: .horizontal) {
      row(.regular).padding(.horizontal, 20)
      row(.compact).padding(.horizontal, 20)
      row(.tight).padding(.horizontal, 12)
    }
    .frame(height: 44)
  }

  private func row(_ tier: HeaderTier) -> some View {
    HStack(spacing: tier == .tight ? 4 : 6) {
      FilterButton(tier: tier)
      SortControls(tier: tier)
      Spacer(minLength: 8)
      SelectButton(tier: tier)
      RefreshButton(tier: tier)
      ImportButton(tier: tier)
    }
  }
}

// MARK: - Filter

/// The Filter capsule: tinted while any filter applies or the Filters sidebar is open, with the
/// number of filters in effect beside it. It opens and closes the sidebar.
private struct FilterButton: View {
  let tier: HeaderTier

  @Environment(PanelController.self) private var controller

  var body: some View {
    let model = controller.library
    let shell = controller.shell
    let count = model.filterCount
    Button {
      shell.toggleFilters()
    } label: {
      HStack(spacing: 5) {
        Image(systemName: "line.3.horizontal.decrease")
          .font(.system(size: 11.5, weight: .semibold))
        if tier.showsLabels { Text("Filter") }
        if count > 0 { CountBadge(count: count, style: .attention) }
      }
    }
    .buttonStyle(.panelCapsule(
        isActive: count > 0 || shell.areFiltersShown, horizontalPadding: tier.capsulePadding))
    .help(shell.areFiltersShown ? L("Hide filters") : L("Show filters"))
    .accessibilityLabel(Text("Filter"))
    .accessibilityValue(Text(verbatim: model.filterButtonValue))
    .accessibilityIdentifier("installed-filter")
  }
}

// MARK: - Sort

/// The sort: with room, a menu named for the sort key and the direction button beside it. Without
/// it, one menu that holds both, since two arrow glyphs side by side would not say which is which.
private struct SortControls: View {
  let tier: HeaderTier

  @Environment(PanelController.self) private var controller

  var body: some View {
    let model = controller.library
    HStack(spacing: 4) {
      Menu {
        sortPicker(model)
        if !tier.showsLabels {
          Divider()
          directionPicker(model)
        }
      } label: {
        HStack(spacing: 4) {
          if tier.showsLabels {
            Text(verbatim: model.sort.name)
            Image(systemName: "chevron.down").font(.system(size: 8.5, weight: .bold))
          } else {
            Image(systemName: "arrow.up.arrow.down")
              .font(.system(size: 11.5, weight: .semibold))
          }
        }
      }
      .menuStyle(.button)
      .menuIndicator(.hidden)
      .buttonStyle(.panelCapsule(horizontalPadding: tier.capsulePadding))
      .fixedSize()
      .help(L("Sort wallpapers"))
      .accessibilityLabel(Text("Sort wallpapers"))
      .accessibilityValue(Text(verbatim: sortState(model)))
      .accessibilityIdentifier("installed-sort")

      if tier.showsLabels {
        Button {
          model.toggleSortDirection()
        } label: {
          Image(systemName: model.descending ? "arrow.down" : "arrow.up")
            .font(.system(size: 11.5, weight: .semibold))
            .frame(width: 14)
        }
        .buttonStyle(.panelCapsule(horizontalPadding: tier.capsulePadding))
        .help(directionHelp(model))
        .accessibilityLabel(Text(verbatim: directionHelp(model)))
        .accessibilityIdentifier("installed-sort-direction")
      }
    }
  }

  private func sortPicker(_ model: InstalledBrowserModel) -> some View {
    Picker(selection: Binding(get: { model.sort }, set: { model.setSort($0) })) {
      ForEach(LibrarySort.allCases) { sort in
        Text(verbatim: sort.name).tag(sort)
      }
    } label: {
      Text("Sort wallpapers")
    }
    .pickerStyle(.inline)
  }

  /// Ascending and Descending, ticked as the list runs; choosing one is the direction button.
  private func directionPicker(_ model: InstalledBrowserModel) -> some View {
    Picker(selection: Binding(get: { model.descending }, set: { model.setDescending($0) })) {
      Text("Ascending").tag(false)
      Text("Descending").tag(true)
    } label: {
      Text("Sort wallpapers")
    }
    .pickerStyle(.inline)
    .labelsHidden()
  }

  /// What VoiceOver reads after "Sort wallpapers": the key, and the direction too once the menu
  /// holds it (the direction button says it otherwise).
  private func sortState(_ model: InstalledBrowserModel) -> String {
    guard !tier.showsLabels else { return model.sort.name }
    return [model.sort.name, model.descending ? L("Descending") : L("Ascending")]
      .joined(separator: ", ")
  }

  private func directionHelp(_ model: InstalledBrowserModel) -> String {
    model.descending
      ? L("\(model.sort.name), descending. Click to sort ascending")
      : L("\(model.sort.name), ascending. Click to sort descending")
  }
}

// MARK: - Select, Refresh, Import

private struct SelectButton: View {
  let tier: HeaderTier

  @Environment(PanelController.self) private var controller

  var body: some View {
    let model = controller.library
    Button {
      model.toggleSelecting()
    } label: {
      HStack(spacing: 5) {
        Image(systemName: model.isSelecting ? "xmark" : "checkmark.circle")
          .font(.system(size: 11.5, weight: .semibold))
        if tier.showsLabels {
          if model.isSelecting { Text("Done") } else { Text("Select") }
        }
      }
    }
    .buttonStyle(.panelCapsule(
        isActive: model.isSelecting, horizontalPadding: tier.capsulePadding))
    .help(
      model.isSelecting
        ? L("Leave selection mode")
        : L(
          "Select wallpapers to add to a playlist or a collection, or to move to Trash. Holding a tile and dragging across others selects them too."
        )
    )
    .accessibilityLabel(model.isSelecting ? Text("Done") : Text("Select"))
    .accessibilityAddTraits(model.isSelecting ? .isSelected : [])
    .accessibilityIdentifier("installed-select")
  }
}

private struct RefreshButton: View {
  let tier: HeaderTier

  @Environment(PanelController.self) private var controller

  var body: some View {
    // The rescan can take a while on a large library: the button shows it is running, and the bar
    // under the grid says what it found (`InstalledBrowserModel.refreshLibrary`).
    let isRefreshing = controller.isBusy(PanelActionCoordinator.key("refresh"))
    Button {
      controller.library.refreshLibrary()
    } label: {
      Group {
        if isRefreshing {
          ProgressRing(value: nil, lineWidth: 1.75).frame(width: 12, height: 12)
        } else {
          Image(systemName: "arrow.clockwise")
            .font(.system(size: 11.5, weight: .semibold))
        }
      }
      .frame(width: 14)
    }
    .buttonStyle(.panelCapsule(horizontalPadding: tier.capsulePadding))
    .disabled(controller.isLibraryLoading || isRefreshing)
    .help(isRefreshing ? L("Refreshing your library…") : L("Refresh library"))
    .accessibilityLabel(Text("Refresh library"))
    .accessibilityIdentifier("installed-refresh")
  }
}

/// The Import button, which hangs the Import popover. It waits while an import runs: the pill in
/// the toolbar is where that one is followed.
private struct ImportButton: View {
  let tier: HeaderTier

  @Environment(PanelController.self) private var controller

  var body: some View {
    let model = controller.library
    Button {
      model.toggleImport(from: .page)
    } label: {
      HStack(spacing: 5) {
        Image(systemName: "plus").font(.system(size: 11.5, weight: .semibold))
        if tier.showsLabels { Text("Import") }
      }
    }
    .buttonStyle(.panelCapsule(
        isActive: model.importAnchor == .page, horizontalPadding: tier.capsulePadding))
    .disabled(controller.importState.isBusy)
    .popover(
      isPresented: Binding(
        get: { model.importAnchor == .page },
        set: { if !$0 { model.closeImport() } }),
      arrowEdge: .bottom
    ) {
      ImportPopover().panelPresentationLocale()
    }
    .help(L("Import wallpapers"))
    .accessibilityLabel(Text("Import"))
    .accessibilityIdentifier("installed-import")
  }
}
