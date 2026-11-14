import XCTest

@testable import WallpaperMachine

final class SurfacePaletteTests: XCTestCase {
  private let tones: [AppThemePreferences.Tone] = [.neutral, .warm, .cool]
  private let appearances: [PanelAppearance] = [.light, .dark]

  /// Every palette the panel can wear in `appearance`: each tone's and the Halloween look's.
  private func palettes(_ appearance: PanelAppearance) -> [(String, SurfacePalette)] {
    tones.map { ("\($0) \(appearance)", SurfacePalette(tone: $0, appearance: appearance)) }
      + [("halloween \(appearance)", SurfacePalette(season: .halloween, appearance: appearance))]
  }

  func testTextAndSemanticColoursStayReadableInEveryToneSeasonAndAppearance() {
    for appearance in appearances {
      for (context, palette) in palettes(appearance) {
        for ground in [
          palette.background, palette.surface, palette.card, palette.raised, palette.well,
          palette.sunken,
        ] {
          XCTAssertGreaterThanOrEqual(palette.text.contrast(with: ground), 7, context)
          // Approval and heart marks are graphics beside text, not text.
          for mark in [palette.approved, palette.heart] {
            XCTAssertGreaterThanOrEqual(mark.contrast(with: ground), 3, context)
          }
        }
        for ground in [palette.background, palette.surface, palette.card] {
          for secondary in [palette.muted, palette.danger, palette.warning] {
            XCTAssertGreaterThanOrEqual(secondary.contrast(with: ground), 4.5, context)
          }
        }
        XCTAssertGreaterThanOrEqual(palette.tagInk.contrast(with: palette.badge), 4.5, context)
      }
    }
  }

  func testTonesTintTheSurfacesAndNeutralKeepsTheDefaultLook() {
    for appearance in appearances {
      let neutral = SurfacePalette(tone: .neutral, appearance: appearance)
      let warm = SurfacePalette(tone: .warm, appearance: appearance)
      let cool = SurfacePalette(tone: .cool, appearance: appearance)
      XCTAssertNotEqual(neutral.background, warm.background, "\(appearance)")
      XCTAssertNotEqual(neutral.surface, cool.surface, "\(appearance)")
      XCTAssertGreaterThanOrEqual(red(warm.surface), blue(warm.surface), "\(appearance)")
      XCTAssertGreaterThanOrEqual(blue(cool.surface), red(cool.surface), "\(appearance)")
      XCTAssertGreaterThanOrEqual(red(warm.muted) - blue(warm.muted), 0, "\(appearance)")
    }
    XCTAssertEqual(SurfacePalette(tone: .neutral, appearance: .light).background.hex, "#ffffff")
    XCTAssertEqual(SurfacePalette(tone: .neutral, appearance: .dark).background.hex, "#1d1d1f")
    XCTAssertEqual(SurfacePalette(tone: .warm, appearance: .dark).text.hex, "#f5f1ea")
    XCTAssertEqual(SurfacePalette(tone: .cool, appearance: .light).well.hex, "#eef1f6")
  }

  func testTheHalloweenLookHasItsOwnSurfacesInBothAppearances() {
    for appearance in appearances {
      let halloween = SurfacePalette(season: .halloween, appearance: appearance)
      for tone in tones {
        let everyday = SurfacePalette(tone: tone, appearance: appearance)
        XCTAssertNotEqual(halloween.background, everyday.background, "\(tone) \(appearance)")
        XCTAssertNotEqual(halloween.text, everyday.text, "\(tone) \(appearance)")
      }
    }
    // Moonlit ink in the dark: violet, never the neutral grey; parchment in the light: warm.
    let night = SurfacePalette(season: .halloween, appearance: .dark)
    XCTAssertGreaterThan(blue(night.surface), red(night.surface))
    let parchment = SurfacePalette(season: .halloween, appearance: .light)
    XCTAssertGreaterThan(red(parchment.surface), blue(parchment.surface))
  }

  func testOverlaysAreWhiteOnDarkSurfacesAndBlackOnLightOnes() {
    for (dark, light) in zip(palettes(.dark).map(\.1), palettes(.light).map(\.1)) {
      for overlay in [dark.line, dark.divider, dark.hover, dark.pressed, dark.selected] {
        XCTAssertEqual(overlay.rgb, 0xffffff)
        XCTAssertLessThan(overlay.alpha, 0.2)
      }
      for overlay in [light.line, light.divider, light.hover, light.pressed, light.selected] {
        XCTAssertEqual(overlay.rgb, 0)
        XCTAssertLessThan(overlay.alpha, 0.2)
      }
      XCTAssertLessThan(dark.hover.alpha, dark.pressed.alpha)
      XCTAssertLessThan(light.hover.alpha, light.pressed.alpha)
      XCTAssertLessThan(light.divider.alpha, light.line.alpha)
    }
  }

  func testMiniatureTintsOnlyTheBackgroundAndKeepsTheLightAndDarkPictures() {
    for appearance in appearances {
      let neutral = SurfacePalette.miniature(tone: .neutral, appearance: appearance)
      for tone in [AppThemePreferences.Tone.warm, .cool] {
        let tinted = SurfacePalette.miniature(tone: tone, appearance: appearance)
        XCTAssertNotEqual(tinted.background, neutral.background, "\(tone) \(appearance)")
        XCTAssertEqual(tinted.bar, neutral.bar)
        XCTAssertEqual(tinted.line, neutral.line)
      }
    }
    let light = SurfacePalette.miniature(tone: .neutral, appearance: .light)
    XCTAssertEqual([light.background.hex, light.bar.hex, light.line.hex], ["#f5f5f7", "#e2e2e7", "#c9c9d0"])
    let dark = SurfacePalette.miniature(tone: .neutral, appearance: .dark)
    XCTAssertEqual([dark.background.hex, dark.bar.hex, dark.line.hex], ["#2c2c2e", "#1c1c1e", "#48484c"])
    // 55% neutral and 45% amber, channel by channel, as the web panel mixed it.
    XCTAssertEqual(
      SurfacePalette.miniature(tone: .warm, appearance: .light).background.hex, "#f5efe7")
  }

  /// What lies over a picture is drawn on any picture in any look, so it never follows the tone,
  /// the season or the appearance.
  func testWhatLiesOverAPictureIsTheSameInEveryToneSeasonAndAppearance() {
    func overlays(_ palette: SurfacePalette) -> [PanelColor] {
      [
        palette.scrim, palette.scrimStrong, palette.scrimSubtle, palette.markFill,
        palette.markFillHover, palette.markGlyph, palette.markApproved, palette.markHeart,
        palette.controlFill, palette.controlRim,
      ]
    }
    let reference = overlays(SurfacePalette(tone: .neutral, appearance: .light))
    for appearance in appearances {
      for (context, palette) in palettes(appearance) {
        XCTAssertEqual(overlays(palette), reference, context)
      }
    }
  }

  /// The brightest picture is white: a status's words and glyphs must read on it through the scrim
  /// and the disc they are drawn on, and the disc under the pointer and the scrims must step from
  /// lighter to darker.
  func testWordsAndGlyphsOverAPictureStayReadableOverTheBrightestPicture() {
    let palette = SurfacePalette(tone: .neutral, appearance: .light)
    let white = PanelColor(rgb: 0xffffff)
    /// `layers` of black or white laid over a white picture, in order.
    func over(_ layers: PanelColor...) -> PanelColor {
      var channel = 1.0
      for layer in layers {
        let ink = layer.rgb == 0 ? 0.0 : 1.0
        channel = channel * (1 - layer.alpha) + ink * layer.alpha
      }
      let value = UInt32((channel * 255).rounded())
      return PanelColor(rgb: value << 16 | value << 8 | value)
    }
    let glyph = palette.markGlyph
    XCTAssertGreaterThanOrEqual(glyph.contrast(with: over(palette.markFill)), 4.5, "a mark's disc")
    XCTAssertGreaterThanOrEqual(
      glyph.contrast(with: over(palette.scrim, palette.markFill)), 4.5, "a ring's disc on a scrim")
    XCTAssertGreaterThanOrEqual(
      glyph.contrast(with: over(palette.scrimStrong)), 4.5, "Applying, straight on the scrim")
    XCTAssertGreaterThanOrEqual(glyph.contrast(with: over(palette.controlFill)), 3, "a tile's check")
    // A mark's trophy and heart are graphics, not words: 3:1 against the disc they sit on.
    XCTAssertGreaterThanOrEqual(
      palette.markApproved.contrast(with: over(palette.markFill)), 3, "the trophy on a mark's disc")
    XCTAssertGreaterThanOrEqual(
      palette.markHeart.contrast(with: over(palette.markFill)), 3, "the heart on a mark's disc")
    XCTAssertEqual(glyph, white)

    let darkness = [
      palette.scrimSubtle, palette.scrim, palette.scrimStrong, palette.markFill,
      palette.markFillHover,
    ].map(\.alpha)
    XCTAssertEqual(darkness, darkness.sorted(), "subtle, scrim, strong, the disc, the disc hovered")
    XCTAssertLessThan(palette.scrim.alpha, palette.scrimStrong.alpha)
    XCTAssertLessThan(palette.markFill.alpha, palette.markFillHover.alpha)
  }

  private func red(_ color: PanelColor) -> Int { Int((color.rgb >> 16) & 255) }
  private func blue(_ color: PanelColor) -> Int { Int(color.rgb & 255) }
}
