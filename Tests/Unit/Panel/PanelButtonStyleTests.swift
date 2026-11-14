import AppKit
import SwiftUI
import XCTest

@testable import WallpaperMachine

/// The panel's buttons with words: the quiet button beside the main one is the same size for the
/// same words, the inspector's Apply keeps its size when it gives up the accent, a card's own link
/// sets the label type and is tall enough to click, and a button or link that removes something
/// takes the theme's danger colour from its role.
@MainActor
final class PanelButtonStyleTests: XCTestCase {
  private let theme = PanelTheme(appearance: .light)

  private func fitting<V: View>(_ view: V) -> CGSize {
    NSHostingController(rootView: view.environment(\.panelTheme, theme))
      .sizeThatFits(in: NSSize(width: 1000, height: 1000))
  }

  func testTheQuietButtonIsAsLargeAsTheMainOneBesideItForTheSameWords() {
    for size in [PrimaryButtonStyle.Size.regular, .compact, .small] {
      for words in ["Revert", "Apply changes", "Pause download"] {
        let primary = fitting(Button(words) {}.buttonStyle(.panelPrimary(size: size)))
        let secondary = fitting(Button(words) {}.buttonStyle(.panelSecondary(size: size)))
        XCTAssertEqual(secondary.width, primary.width, accuracy: 0.5, "\(size) \(words)")
        XCTAssertEqual(secondary.height, primary.height, accuracy: 0.5, "\(size) \(words)")
      }
    }
  }

  /// Apply wallpaper gives the accent to Apply changes while edits wait; it changes its look, not
  /// its size, so nothing beside or under it moves.
  func testTheInspectorsApplyKeepsItsSizeWhenItGivesUpTheAccent() {
    let label = Label("Apply wallpaper", systemImage: ApplyOffer.symbol)
    let accent = fitting(Button {} label: { label }.buttonStyle(.inspectorAction(isPrimary: true)))
    let plain = fitting(Button {} label: { label }.buttonStyle(.inspectorAction(isPrimary: false)))
    XCTAssertEqual(plain.width, accent.width, accuracy: 0.5)
    XCTAssertEqual(plain.height, accent.height, accuracy: 0.5)
  }

  /// A link on its own in an inspector card (Center, Delete…) is set in the card's label type,
  /// whatever type is around it, and answers clicks over the card link's height however short its
  /// words; a link in a notice or a column of links keeps the line it is set on.
  func testACardsOwnLinkSetsTheLabelTypeAndIsTallEnoughToClick() {
    let card = fitting(Button("Center") {}.buttonStyle(.panelCardLink).font(.panel(.caption)))
    let label = fitting(Button("Center") {}.buttonStyle(.panelLink).font(.panel(.label)))
    let inText = fitting(Button("Center") {}.buttonStyle(.panelLink).font(.panel(.callout)))
    XCTAssertEqual(card.width, label.width, accuracy: 0.5, "the card's label type, not the caption")
    XCTAssertGreaterThanOrEqual(card.height, DiscoverLinkButtonStyle.cardLinkHeight - 0.5)
    XCTAssertLessThan(inText.height, DiscoverLinkButtonStyle.cardLinkHeight - 1, "a line of text")
  }

  /// Move to Trash and Delete… say what they do by their role: a quiet button or a link with the
  /// destructive role takes the theme's danger colour in every tone and appearance, any other quiet
  /// button the text colour and any other link the accent, and the accent button keeps the label
  /// colour fitted to its fill whatever its role.
  func testAButtonOrLinkThatRemovesSomethingIsDrawnInTheDangerColour() {
    for appearance in [PanelAppearance.light, .dark] {
      for tone in [AppThemePreferences.Tone.neutral, .warm, .cool] {
        var preferences = AppThemePreferences()
        preferences.tone = tone
        let theme = PanelTheme(preferences: preferences, appearance: appearance)
        let context = "\(tone) \(appearance)"
        XCTAssertNotEqual(theme.surface.danger, theme.surface.text, "precondition: \(context)")
        XCTAssertEqual(
          PanelButtonBody.foreground(look: .quiet, role: .destructive, in: theme),
          theme.surface.danger, "Move to Trash: \(context)")
        for role in [nil, ButtonRole.cancel] {
          XCTAssertEqual(
            PanelButtonBody.foreground(look: .quiet, role: role, in: theme), theme.surface.text,
            "Revert, Cancel: \(context)")
          XCTAssertEqual(
            DiscoverLinkButtonStyle.foreground(role: role, in: theme), theme.accent.accent,
            "Center: \(context)")
        }
        XCTAssertEqual(
          DiscoverLinkButtonStyle.foreground(role: .destructive, in: theme), theme.surface.danger,
          "Delete…: \(context)")
        XCTAssertEqual(
          PanelButtonBody.foreground(look: .accent, role: .destructive, in: theme),
          theme.accent.onPrimary, "the accent button's label: \(context)")
      }
    }
  }
}
