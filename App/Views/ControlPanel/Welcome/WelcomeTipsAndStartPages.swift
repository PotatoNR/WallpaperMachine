import SwiftUI

// MARK: - Tips

/// Page four: the things to know, what a Steam download needs with where to get it, and the honest
/// word about wallpapers that do not run yet.
struct WelcomeTipsPage: View {
  @Environment(PanelController.self) private var controller
  @Environment(\.panelTheme) private var theme
  @Environment(\.welcomeIsCompact) private var compact

  var body: some View {
    WelcomeColumn(spacing: compact ? 18 : 22) {
      WelcomePageHeader(title: Text("The basics"))
      DividedRows(separatorInset: 54) {
        tip("magnifyingglass", .blue, Text("Browse wallpapers in Steam Workshop. No account needed."))
        tip("arrow.down.circle", .green, Text("Download one, then double-click it to apply."))
        tip(
          "display", .orange,
          Text("Each display plays its own wallpaper. Pick the display in the top bar."))
        // The guide asks for no Steam account, so this is where it first says what a download needs.
        tip(
          "person.crop.circle", .purple,
          Text("Downloading from Steam needs a Steam account that owns Wallpaper Engine."))
      }
      .welcomeSurface()
      // Where to get an account and the app, by the download dialog's rule: only while no Steam
      // account is signed in on this Mac, so a replayed guide does not sell them to an owner.
      if controller.downloads.showsAccountRequirement { WelcomeSteamLinks() }
      WelcomeStatusCard(
        systemImage: "chevron.left.forwardslash.chevron.right",
        title: Text("Not every wallpaper works yet"),
        detail: Text(
          "Videos usually play. Scenes are experimental, and Application wallpapers can’t run on macOS. If one doesn’t work, use “Report on GitHub” in its details. Pull requests are welcome too."
        )
      ) {
        HStack(spacing: 18) {
          WelcomeLinkButton(title: Text("Report an issue"), url: ExternalLink.repositoryIssues)
          WelcomeLinkButton(title: Text("Contribute on GitHub"), url: ExternalLink.repository)
        }
      }
    }
  }

  private func tip(_ symbol: String, _ color: Color, _ text: Text) -> some View {
    HStack(spacing: 12) {
      SymbolTile(systemImage: symbol, color: color, size: .medium)
      text
        .font(.system(size: 13))
        .foregroundStyle(theme.surface.text.color)
        .frame(maxWidth: .infinity, alignment: .leading)
        .textSelection(.enabled)
    }
    .padding(.horizontal, 14)
    .padding(.vertical, 12)
    .accessibilityElement(children: .combine)
  }
}

// MARK: - Steam links

/// Where to get an account and the app.
struct WelcomeSteamLinks: View {
  @Environment(\.panelTheme) private var theme

  var body: some View {
    HStack(alignment: .top, spacing: 24) {
      column(
        Text("No Steam account yet?"), Text("Creating one is free."),
        link: WelcomeLinkButton(title: Text("Create a Steam account"), url: ExternalLink.steamJoin)
          .accessibilityIdentifier("welcome-steam-join"))
      column(
        Text("Don’t own Wallpaper Engine?"), Text("It is a one-time purchase on Steam."),
        link: WelcomeLinkButton(
          title: Text("Buy Wallpaper Engine"), url: ExternalLink.wallpaperEngineStore))
    }
  }

  private func column(_ title: Text, _ detail: Text, link: some View) -> some View {
    WelcomeColumn(spacing: 3) {
      title.font(.system(size: 12, weight: .semibold))
      detail.font(.system(size: 12)).foregroundStyle(theme.surface.muted.color)
      link.padding(.top, 2)
    }
    .frame(maxWidth: .infinity, alignment: .leading)
  }
}

// MARK: - Start

/// Page five: what the guide set, what it left unsaved, and the ways to begin. Nothing on the
/// desktop changes until a wallpaper is applied. **Skip setup** with unsaved drafts lands here, so
/// they are shown before the guide ends; the lead then says so, since VoiceOver starts at the
/// title and the rows that list them come later.
struct WelcomeStartPage: View {
  @Environment(FirstRunModel.self) private var model
  @Environment(\.panelTheme) private var theme
  @Environment(\.welcomeIsCompact) private var compact

  var body: some View {
    let recap = model.recap
    WelcomeColumn(spacing: compact ? 16 : 20) {
      WelcomePageHeader(
        title: Text("Setup complete"),
        lead: recap.unsaved.isEmpty
          ? Text("Your desktop won’t change until you apply a wallpaper.")
          : Text("Some changes aren’t saved yet. Review them, or start without them."))
        // Selectable Text can keep its old AppKit accessibility value when only its
        // content changes. Replace the header when its saved/unsaved meaning changes.
        .id(recap.unsaved.isEmpty)
      DividedRows(separatorInset: 14) {
        recapRow(Text("Language"), value: language(recap), action: nil)
        recapRow(Text("Appearance"), value: appearance(recap), action: nil)
        recapRow(Text("Steam"), value: Text(verbatim: recap.steam), action: nil)
        ForEach(recap.unsaved) { unsaved in
          recapRow(
            unsaved.step == .performance ? Text("Performance") : Text("Preferences"),
            value: unsaved.count == 1
              ? Text("\(unsaved.count) change not saved") : Text("\(unsaved.count) changes not saved"),
            action: (Text("Review"), { model.go(to: unsaved.step) }))
        }
      }
      .welcomeSurface()
      WelcomeColumn(spacing: 8) {
        // The guide hides the toolbar, so the note says where the tab is once it ends, and the row
        // wears the tab's own symbol: in a narrow window the tab shows nothing else.
        WelcomeActionRow(
          symbol: PanelTabs.symbol(of: .workshop), color: theme.accent.control.color,
          title: Text("Browse the Workshop"),
          note: Text(
            "After this guide, find wallpapers from Steam any time in the Steam Workshop tab at the top of the window."
          ),
          trailingSymbol: "chevron.right", isSuggested: true
        ) { model.browse() }
        WelcomeActionRow(
          symbol: "plus", color: .gray, title: Text("Import wallpapers"),
          note: Text("Bring in wallpaper folders or files you already have."),
          trailingSymbol: "chevron.right"
        ) { model.importWallpapers() }
      }
      // Where the guide lives: Settings › General › Help.
      WelcomeNote(text: Text("You can open this guide again from Settings → General."))
    }
  }

  private func language(_ recap: WelcomeRecap) -> Text {
    // A language is named in itself; following macOS has a name of its own.
    recap.languageName.map { Text(verbatim: $0) } ?? Text("System (Auto)")
  }

  private func appearance(_ recap: WelcomeRecap) -> Text {
    switch recap.appearance {
    case .system: Text("System (Auto)")
    case .light: Text("Light")
    case .dark: Text("Dark")
    }
  }

  /// Every label a recap row can have, so the values line up at the longest in the language on
  /// show (`ColumnLabel`). A computed property, so no `Text` is kept in a static.
  private var recapLabels: [Text] {
    [Text("Language"), Text("Appearance"), Text("Steam"), Text("Performance"), Text("Preferences")]
  }

  private func recapRow(_ label: Text, value: Text, action: (Text, () -> Void)?) -> some View {
    HStack(spacing: 12) {
      ColumnLabel(text: label, column: recapLabels)
        .font(.system(size: 13))
        .foregroundStyle(theme.surface.muted.color)
        .layoutPriority(1)
      value
        .font(.system(size: 13, weight: .medium))
        .frame(maxWidth: .infinity, alignment: .leading)
        .textSelection(.enabled)
      if let (title, run) = action {
        Button(action: run) { title }
          .buttonStyle(.welcomeCapsule(isActive: true))
      }
    }
    .padding(.horizontal, 14)
    .padding(.vertical, 10)
    .accessibilityElement(children: .combine)
  }
}
