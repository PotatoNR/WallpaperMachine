import SwiftUI

/// The first-run guide over the window: the window dimmed, one card in the middle with the progress
/// at the top, the page in the middle and the navigation pinned at the bottom.
///
/// It ends with one of the Start page's three closing choices, or with **Skip setup** at the top
/// right of every other page; Escape is **Skip setup**. A click outside the card does nothing: a
/// stray click is no sign of wanting to leave. The pages behind it are disabled and hidden from
/// VoiceOver by the root.
struct WelcomeGuide: View {
  @Environment(\.panelTheme) private var theme
  @Environment(\.colorScheme) private var colorScheme
  @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

  var body: some View {
    GeometryReader { proxy in
      let size = WelcomeLayout.cardSize(in: proxy.size)
      ZStack {
        Rectangle()
          .fill(.black.opacity(scrimOpacity))
          .ignoresSafeArea()
          .contentShape(Rectangle())
          // The scrim takes clicks so nothing behind it can be reached, and does nothing with them.
          .onTapGesture {}
          .accessibilityHidden(true)
        WelcomeCard()
          .environment(\.welcomeIsCompact, WelcomeLayout.isCompact(cardHeight: size.height))
          .frame(width: size.width, height: size.height)
      }
      .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    .accessibilityAddTraits(.isModal)
  }

  private var scrimOpacity: Double {
    if reduceTransparency { return colorScheme == .dark ? 0.7 : 0.42 }
    return colorScheme == .dark ? 0.5 : 0.28
  }
}

/// The card: progress, page, footer.
private struct WelcomeCard: View {
  @Environment(FirstRunModel.self) private var model
  @Environment(\.panelTheme) private var theme
  @Environment(\.welcomeIsCompact) private var compact
  @Environment(\.accessibilityReduceMotion) private var reduceMotion

  var body: some View {
    VStack(spacing: 0) {
      // Skip setup sits apart from the progress element, so VoiceOver reaches it as its own button,
      // and apart from the footer's Skip, which only leaves one page.
      WelcomeProgress()
        .overlay(alignment: .topTrailing) { WelcomeSkipSetupButton() }
      pageArea
      WelcomeFooter()
    }
    .foregroundStyle(theme.surface.text.color)
    .background(theme.surface.background.color)
    .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
    .overlay {
      RoundedRectangle(cornerRadius: 18, style: .continuous)
        .strokeBorder(theme.surface.line.color, lineWidth: 0.5)
    }
    .shadow(color: .black.opacity(0.28), radius: 36, y: 14)
    .shadow(color: .black.opacity(0.12), radius: 3, y: 1)
    .accessibilityElement(children: .contain)
  }

  /// The page scrolls on its own so the footer is always in reach. Every page starts at the same
  /// height under the progress, so the title stays put as the person moves through the guide.
  private var pageArea: some View {
    // The page has a definite width: it is laid out at the width of the card, never at a width
    // it makes up for itself.
    GeometryReader { proxy in
      let padding: CGFloat = compact ? 24 : 32
      let width = min(WelcomeLayout.contentWidth, max(0, proxy.size.width - 2 * padding))
      ScrollView {
        page
          .frame(width: width)
          .padding(.horizontal, padding)
          .padding(.top, compact ? 10 : 14)
          .padding(.bottom, compact ? 16 : 24)
          .frame(maxWidth: .infinity)
      }
      .id(model.step)
      .scrollBounceBehavior(.basedOnSize)
    }
  }

  @ViewBuilder private var page: some View {
    switch model.step {
    case .language: WelcomeLanguagePage()
    case .performance: WelcomePerformancePage()
    case .preferences: WelcomePreferencesPage()
    case .tips: WelcomeTipsPage()
    case .start: WelcomeStartPage()
    }
  }
}

// MARK: - Progress

/// The five steps as a row of dots joined by a line, with the name of the one on show under it. Any
/// dot jumps to its page, forward or back; they wait while a choice is being committed.
private struct WelcomeProgress: View {
  @Environment(FirstRunModel.self) private var model
  @Environment(\.panelTheme) private var theme
  @Environment(\.welcomeIsCompact) private var compact

  var body: some View {
    VStack(spacing: compact ? 4 : 6) {
      HStack(spacing: 0) {
        ForEach(WelcomeStep.allCases) { step in
          if !step.isFirst {
            Rectangle()
              .fill(step.rawValue <= model.step.rawValue ? accent : theme.surface.line.color)
              .frame(width: 16, height: 1.5)
              .accessibilityHidden(true)
          }
          WelcomeProgressDot(step: step)
        }
      }
      // The dots carry the names for VoiceOver; this line is for the eye.
      model.step.name.asText
        .foregroundStyle(theme.surface.muted.color)
        .font(.system(size: 11.5, weight: .medium))
        .lineLimit(1)
        .accessibilityHidden(true)
    }
    .padding(.top, compact ? 12 : 16)
    .padding(.bottom, compact ? 4 : 8)
    .frame(maxWidth: .infinity)
    .accessibilityElement(children: .contain)
    .accessibilityLabel(L("Setup progress"))
  }

  private var accent: Color { theme.accent.primary.color }
}

/// **Skip setup**: ends the guide from any page but the last (`FirstRunModel.skipSetup`), a quiet
/// text button at the card's top right. Escape presses it. It waits, like the footer, while a choice
/// is being committed.
private struct WelcomeSkipSetupButton: View {
  @Environment(FirstRunModel.self) private var model
  @Environment(\.welcomeIsCompact) private var compact

  var body: some View {
    if model.offersSkipSetup {
      Button("Skip setup") { model.skipSetup() }
        .buttonStyle(.welcomeQuiet)
        .keyboardShortcut(.cancelAction)
        .disabled(model.navigationBusy)
        .help(L("You can open this guide again from Settings → General."))
        .accessibilityIdentifier("welcome-skip-setup")
        .padding(.top, compact ? 8 : 12)
        .padding(.trailing, compact ? 12 : 16)
    }
  }
}

private extension String {
  /// A runtime string as `Text`, never read as a catalog key.
  var asText: Text { Text(verbatim: self) }
}

private struct WelcomeProgressDot: View {
  let step: WelcomeStep

  @Environment(FirstRunModel.self) private var model
  @Environment(\.panelTheme) private var theme
  @Environment(\.accessibilityReduceMotion) private var reduceMotion

  private var isCurrent: Bool { step == model.step }
  private var isDone: Bool { step.rawValue < model.step.rawValue }

  var body: some View {
    Button {
      model.go(to: step)
    } label: {
      dot
        .frame(width: 26, height: 26)
        .contentShape(Circle())
    }
    .buttonStyle(.plain)
    .disabled(model.navigationBusy)
    .help(step.name)
    .accessibilityLabel(step.name)
    .accessibilityAddTraits(isCurrent ? [.isSelected] : [])
    .animation(reduceMotion ? nil : .easeOut(duration: 0.18), value: isCurrent)
  }

  @ViewBuilder private var dot: some View {
    let accent = theme.accent
    if isDone {
      Image(systemName: "checkmark")
        .font(.system(size: 8, weight: .heavy))
        .foregroundStyle(accent.onPrimary.color)
        .frame(width: 16, height: 16)
        .background(accent.primary.color, in: Circle())
    } else if isCurrent {
      Circle()
        .strokeBorder(accent.primaryLine.color, lineWidth: 2)
        .frame(width: 16, height: 16)
        .overlay { Circle().fill(accent.primary.color).frame(width: 6, height: 6) }
    } else {
      Circle()
        .strokeBorder(theme.surface.line.color, lineWidth: 1.5)
        .frame(width: 16, height: 16)
    }
  }
}

// MARK: - Footer

/// Back on the left, the way forward on the right. Which buttons there are, and when they wait,
/// depends on the page.
private struct WelcomeFooter: View {
  @Environment(FirstRunModel.self) private var model
  @Environment(\.panelTheme) private var theme
  @Environment(\.welcomeIsCompact) private var compact

  var body: some View {
    HStack(spacing: 8) {
      if !model.step.isFirst {
        Button { model.back() } label: {
          Label {
            Text("Back")
          } icon: {
            Image(systemName: "chevron.left").font(.system(size: 11, weight: .bold))
          }
        }
        .buttonStyle(.welcomeQuiet)
        .disabled(model.navigationBusy)
      }
      Spacer(minLength: 8)
      actions
    }
    .padding(.horizontal, compact ? 16 : 20)
    .padding(.vertical, compact ? 10 : 14)
    .background(theme.surface.surface.color.opacity(0.7))
    .overlay(alignment: .top) {
      Rectangle().fill(theme.surface.divider.color).frame(height: 0.5)
    }
  }

  @ViewBuilder private var actions: some View {
    switch model.step {
    case .language:
      let waiting = !model.pending.isEmpty
      Button("Skip") { Task { await model.skipLanguage() } }
        .buttonStyle(.welcomeQuiet)
        .disabled(waiting)
      forward(Text("Continue")) { model.next() }.disabled(waiting)
    case .performance:
      Button("Skip") { model.skipPerformance() }
        .buttonStyle(.welcomeQuiet)
        .disabled(model.navigationBusy)
      forward(Text("Continue")) { Task { await model.continuePerformance() } }
        .disabled(model.navigationBusy)
    case .preferences:
      Button("Skip") { Task { await model.skipPreferences() } }
        .buttonStyle(.welcomeQuiet)
        .disabled(model.navigationBusy)
      forward(Text("Continue")) { Task { await model.continuePreferences() } }
        .disabled(model.navigationBusy)
    case .tips:
      forward(Text("Continue")) { model.next() }
    case .start:
      Button { model.finish() } label: {
        Label {
          Text("Start using the app")
        } icon: {
          Image(systemName: "checkmark").font(.system(size: 11, weight: .bold))
        }
      }
      .buttonStyle(.welcomePrimary)
      .keyboardShortcut(.defaultAction)
    }
  }

  private func forward(_ title: Text, action: @escaping () -> Void) -> some View {
    Button(action: action) {
      HStack(spacing: 6) {
        title
        Image(systemName: "arrow.right").font(.system(size: 11, weight: .bold))
      }
    }
    .buttonStyle(.welcomePrimary)
    .keyboardShortcut(.defaultAction)
  }
}
