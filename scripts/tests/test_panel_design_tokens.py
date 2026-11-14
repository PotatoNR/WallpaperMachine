"""Keep raw font sizes and colours out of new control panel code, without Xcode.

The panel's type comes from the roles of `PanelFont` and its colours from `\\.panelTheme`
(`AccentPalette`, `SurfacePalette`), both in `App/Views/ControlPanel/Theme/`. A raw
`.system(size:)`, an `NSFont.systemFont(ofSize:)`, a system text style (`.caption`,
`.headline`…), `.black`, `.white`, a named hue or a hierarchical `.secondary` or `.tertiary`
(which ignore the Warm and Cool tones) bypasses them. This scans `App/Views/ControlPanel/`, Theme
aside, for those. Files that still hold them are listed below with the reason; the lists only
shrink: a file not on them fails on its first hit, and a listed file with none left fails until
its entry is deleted. Shadows and alpha masks are not colours a person reads, so `.shadow(...)`
arguments and `.mask { }` closures are skipped. See docs/conventions.md#swiftui-control-panel.
"""
from pathlib import Path
import re
import sys
import unittest

sys.path.insert(0, str(Path(__file__).resolve().parent))
from test_localization_catalogs import ROOT  # noqa: E402
from test_panel_lazy_lists import blank_comments_and_strings, call_end  # noqa: E402

PANEL = ROOT / "App" / "Views" / "ControlPanel"
THEME = PANEL / "Theme"

TEXT_STYLES = r"(?:caption2?|footnote|callout|subheadline|headline|body|title[23]?|largeTitle)"
TYPE = [
    re.compile(r"\.system\(\s*size:"),
    re.compile(r"\.system\(\s*\."),
    re.compile(r"[sS]ystemFont\(\s*ofSize:"),
    re.compile(r"\.font\(\s*\." + TEXT_STYLES + r"\b"),
    re.compile(r"\bFont\." + TEXT_STYLES + r"\b"),
]
COLOUR = [
    re.compile(r"(?<![\w.)\]])\.(?:black|white)\b"),
    re.compile(r"(?<![\w.])(?:NS)?Color\.(?:black|white)\b"),
    re.compile(
        r"(?<![\w.])(?:NS)?Color\.(?:red|green|blue|orange|yellow|pink|purple|gray|cyan|mint|teal|indigo"
        r"|brown)\b"),
    re.compile(r"(?<![\w.])Color\(\s*(?:red|white):"),
    re.compile(r"(?<![\w.)\]])\.(?:secondary|tertiary)\b"),
    re.compile(r"(?<![\w.])(?:NS)?Color\.(?:secondary|tertiary)\b"),
]
EXEMPT = re.compile(r"\.(shadow|mask)\b")

# Files that still draw a raw size, with why. Shrink only: migrate a file to `PanelFont` and
# delete its entry.
TYPE_ALLOWLIST = {
    "App/Views/ControlPanel/Components/FilterPanel.swift":
        "the system headline over the filters; no role at its size yet",
    "App/Views/ControlPanel/Components/FilterTagChip.swift":
        "the chip's 8-point check glyph",
    "App/Views/ControlPanel/Components/ReleaseNotesEntryView.swift":
        "the release notes' own scale (body size passed in)",
    "App/Views/ControlPanel/Components/SettingsSegmentedControl.swift":
        "12.5 semibold segments: no role",
    "App/Views/ControlPanel/Components/SteamQRSignInSection.swift":
        "added after the scale; not migrated yet",
    "App/Views/ControlPanel/Discover/WorkshopBrowserPage.swift":
        "backlog: Steam Workshop page",
    "App/Views/ControlPanel/Discover/WorkshopFilters.swift":
        "backlog: Steam Workshop page",
    "App/Views/ControlPanel/Discover/WorkshopFooter.swift":
        "backlog: Steam Workshop page",
    "App/Views/ControlPanel/Discover/WorkshopHeader.swift":
        "backlog: Steam Workshop page",
    "App/Views/ControlPanel/Discover/WorkshopInspector.swift":
        "12.5 regular creator line and description: no role",
    "App/Views/ControlPanel/Discover/WorkshopTranslationBar.swift":
        "backlog: Steam Workshop page",
    "App/Views/ControlPanel/Downloads/DownloadDialogStages.swift":
        "backlog: Downloads",
    "App/Views/ControlPanel/Downloads/DownloadDialogView.swift":
        "backlog: Downloads",
    "App/Views/ControlPanel/Downloads/DownloadsPopover.swift":
        "backlog: Downloads",
    "App/Views/ControlPanel/Downloads/DownloadsToolbarButton.swift":
        "backlog: Downloads",
    "App/Views/ControlPanel/Downloads/SetupActivityPill.swift":
        "backlog: Downloads",
    "App/Views/ControlPanel/Downloads/SteamSignInGuideView.swift":
        "backlog: Downloads",
    "App/Views/ControlPanel/Images/PanelImage.swift":
        "the placeholder glyph",
    "App/Views/ControlPanel/Inspector/InspectorChecksCards.swift":
        "status glyphs and an 11 medium summary: no text role",
    "App/Views/ControlPanel/Inspector/InspectorHeader.swift":
        "the 30-point placeholder glyph",
    "App/Views/ControlPanel/Inspector/InspectorOptionsCards.swift":
        "12.5 regular, 11.5 and 11 medium lines and a chevron: no role",
    "App/Views/ControlPanel/Inspector/InspectorStyles.swift":
        "the section's 9-point chevron",
    "App/Views/ControlPanel/Inspector/InstalledInspector.swift":
        "the footer's 11.5 medium line: no role",
    "App/Views/ControlPanel/Inspector/PresetsCard.swift":
        "the 11.5 medium status line: no role",
    "App/Views/ControlPanel/Inspector/PropertyTopLine.swift":
        "the Modified and Not applied pill's 10.5 points, drawn and measured from one value",
    "App/Views/ControlPanel/Library/CollectionsFilterGroup.swift":
        "backlog: Library",
    "App/Views/ControlPanel/Library/ImportActivityPill.swift":
        "backlog: Library",
    "App/Views/ControlPanel/Library/ImportPopover.swift":
        "backlog: Library",
    "App/Views/ControlPanel/Library/InstalledFilters.swift":
        "backlog: Library",
    "App/Views/ControlPanel/Library/InstalledFooter.swift":
        "backlog: Library",
    "App/Views/ControlPanel/Library/InstalledHeaderRow.swift":
        "the capsules' glyph sizes",
    "App/Views/ControlPanel/Library/InstalledScopeBar.swift":
        "backlog: Library",
    "App/Views/ControlPanel/Library/InstalledTile.swift":
        "control and placeholder glyph sizes",
    "App/Views/ControlPanel/MenuBar/StatusPanelView.swift":
        "backlog: the menu bar panel beyond its eyebrow",
    "App/Views/ControlPanel/Pixiv/PixivActivityPill.swift":
        "backlog: pixiv page",
    "App/Views/ControlPanel/Pixiv/PixivBrowserPage.swift":
        "backlog: pixiv page",
    "App/Views/ControlPanel/Pixiv/PixivFilters.swift":
        "backlog: pixiv page",
    "App/Views/ControlPanel/Pixiv/PixivInspector.swift":
        "notice, stepper and chevron glyphs",
    "App/Views/ControlPanel/Pixiv/PixivPagerBar.swift":
        "backlog: pixiv page",
    "App/Views/ControlPanel/Pixiv/PixivTileCell.swift":
        "the R-18 capsule and page-count glyph",
    "App/Views/ControlPanel/Pixiv/PixivTileRing.swift":
        "ring glyph and text sizes fixed to its 52-point disc",
    "App/Views/ControlPanel/Settings/Infrastructure/SettingsDisclosureHeader.swift":
        "backlog: Settings",
    "App/Views/ControlPanel/Settings/Infrastructure/SettingsEntryControls.swift":
        "backlog: Settings",
    "App/Views/ControlPanel/Settings/Infrastructure/SettingsRow.swift":
        "backlog: Settings",
    "App/Views/ControlPanel/Settings/Infrastructure/SettingsStatusViews.swift":
        "backlog: Settings",
    "App/Views/ControlPanel/Settings/Sections/AboutSettingsSection.swift":
        "backlog: Settings",
    "App/Views/ControlPanel/Settings/Sections/AppearanceAccent.swift":
        "backlog: Settings",
    "App/Views/ControlPanel/Settings/Sections/AppearanceChoiceCards.swift":
        "backlog: Settings",
    "App/Views/ControlPanel/Settings/Sections/AppearanceSettingsSection.swift":
        "backlog: Settings",
    "App/Views/ControlPanel/Settings/Sections/DesktopSettingsSection.swift":
        "backlog: Settings",
    "App/Views/ControlPanel/Settings/Sections/DisplaysAutomationRows.swift":
        "backlog: Settings",
    "App/Views/ControlPanel/Settings/Sections/DisplaysControls.swift":
        "backlog: Settings",
    "App/Views/ControlPanel/Settings/Sections/DisplaysDesktopRows.swift":
        "backlog: Settings",
    "App/Views/ControlPanel/Settings/Sections/DisplaysGroups.swift":
        "backlog: Settings",
    "App/Views/ControlPanel/Settings/Sections/DisplaysOrderEditor.swift":
        "backlog: Settings",
    "App/Views/ControlPanel/Settings/Sections/DisplaysPlaylistRows.swift":
        "backlog: Settings",
    "App/Views/ControlPanel/Settings/Sections/DisplaysRow.swift":
        "backlog: Settings",
    "App/Views/ControlPanel/Settings/Sections/DisplaysSettingsCard.swift":
        "backlog: Settings",
    "App/Views/ControlPanel/Settings/Sections/DisplaysSettingsSection.swift":
        "backlog: Settings",
    "App/Views/ControlPanel/Settings/Sections/LibrarySettingsSection.swift":
        "backlog: Settings",
    "App/Views/ControlPanel/Settings/Sections/PerformanceEnergyReadout.swift":
        "backlog: Settings",
    "App/Views/ControlPanel/Settings/Sections/PerformanceSettingsSection.swift":
        "backlog: Settings",
    "App/Views/ControlPanel/Settings/Sections/PlaybackAppRuleRows.swift":
        "backlog: Settings",
    "App/Views/ControlPanel/Settings/Sections/PlaybackSettingsSection.swift":
        "backlog: Settings",
    "App/Views/ControlPanel/Settings/Sections/QuickSettingsSection.swift":
        "backlog: Settings",
    "App/Views/ControlPanel/Settings/Sections/QuickSettingsTile.swift":
        "backlog: Settings",
    "App/Views/ControlPanel/Settings/Sections/ShortcutsSettingsSection.swift":
        "backlog: Settings",
    "App/Views/ControlPanel/Settings/Sections/StorageSettingsSection.swift":
        "backlog: Settings",
    "App/Views/ControlPanel/Settings/Sections/WidgetsSettingsSection.swift":
        "backlog: Settings",
    "App/Views/ControlPanel/Shell/NowPlayingBar.swift":
        "backlog: Shell",
    "App/Views/ControlPanel/Shell/NowPlayingControl.swift":
        "backlog: Shell",
    "App/Views/ControlPanel/Shell/NowPlayingPlaylist.swift":
        "backlog: Shell",
    "App/Views/ControlPanel/Shell/PageSearchBar.swift":
        "backlog: Shell",
    "App/Views/ControlPanel/Shell/PanelBanners.swift":
        "backlog: Shell",
    "App/Views/ControlPanel/Shell/PanelIdentity.swift":
        "backlog: Shell",
    "App/Views/ControlPanel/Shell/PanelTabs.swift":
        "backlog: Shell",
    "App/Views/ControlPanel/Shell/RecentlyUsedPopover.swift":
        "backlog: Shell",
    "App/Views/ControlPanel/UpdateWindow.swift":
        "backlog: the update window",
    "App/Views/ControlPanel/WallpaperPreviewWindow.swift":
        "an AppKit window's small system font",
    "App/Views/ControlPanel/WebSignInWindow.swift":
        "an AppKit window's bold system-font heading",
    "App/Views/ControlPanel/Welcome/WelcomeActionRow.swift":
        "backlog: Welcome (its own hero sizes)",
    "App/Views/ControlPanel/Welcome/WelcomeGuide.swift":
        "backlog: Welcome (its own hero sizes)",
    "App/Views/ControlPanel/Welcome/WelcomeLanguagePage.swift":
        "backlog: Welcome (its own hero sizes)",
    "App/Views/ControlPanel/Welcome/WelcomeOverlayHost.swift":
        "backlog: Welcome (its own hero sizes)",
    "App/Views/ControlPanel/Welcome/WelcomeParts.swift":
        "backlog: Welcome (its own hero sizes)",
    "App/Views/ControlPanel/Welcome/WelcomePerformancePage.swift":
        "backlog: Welcome (its own hero sizes)",
    "App/Views/ControlPanel/Welcome/WelcomePreferencesPage.swift":
        "backlog: Welcome (its own hero sizes)",
    "App/Views/ControlPanel/Welcome/WelcomeTipsAndStartPages.swift":
        "backlog: Welcome (its own hero sizes)",
}

# Files that still draw a raw colour, with why. Shrink only.
COLOUR_ALLOWLIST = {
    "App/Views/ControlPanel/Components/SteamQRSignInSection.swift":
        "the QR code's white quiet zone, which a scanner needs",
    "App/Views/ControlPanel/Components/SymbolTile.swift":
        "the white symbol on a coloured tile, as System Settings draws it",
    "App/Views/ControlPanel/Discover/WorkshopBrowserPage.swift":
        "backlog: hierarchical .secondary",
    "App/Views/ControlPanel/Discover/WorkshopFilters.swift":
        "backlog: approved green and .secondary in the filter list",
    "App/Views/ControlPanel/Images/PanelImage.swift":
        "backlog: hierarchical .tertiary placeholder",
    "App/Views/ControlPanel/Library/CollectionsFilterGroup.swift":
        "backlog: hierarchical .secondary",
    "App/Views/ControlPanel/Library/InstalledFilters.swift":
        "backlog: .secondary in the filter list",
    "App/Views/ControlPanel/Pixiv/PixivBrowserPage.swift":
        "backlog: hierarchical .secondary",
    "App/Views/ControlPanel/Pixiv/PixivTileCell.swift":
        "pixiv's own R-18 red, with white words on it",
    "App/Views/ControlPanel/Settings/Sections/AppearanceAccent.swift":
        "swatch ink picked by contrast against each swatch",
    "App/Views/ControlPanel/Settings/Sections/DesktopSettingsSection.swift":
        "backlog: hierarchical .secondary",
    "App/Views/ControlPanel/Settings/Sections/DisplaysPlaylistRows.swift":
        "backlog: hierarchical .secondary",
    "App/Views/ControlPanel/Settings/Sections/PlaybackAppRuleRows.swift":
        "backlog: hierarchical .secondary and .tertiary",
    "App/Views/ControlPanel/Settings/Sections/PlaybackSettingsSection.swift":
        "backlog: hierarchical .secondary",
    "App/Views/ControlPanel/WallpaperPreviewWindow.swift":
        "the preview window's black backdrop behind the wallpaper",
    "App/Views/ControlPanel/Welcome/WelcomeGuide.swift":
        "the guide's scrim over the whole window",
    "App/Views/ControlPanel/Welcome/WelcomeLanguagePage.swift":
        "backlog: Welcome",
}


def exempt_shadows_and_masks(code):
    """`code` with the arguments of every `.shadow(...)` and the closure or arguments of every
    `.mask` blanked, offsets and newlines kept."""
    out = list(code)
    for match in EXEMPT.finditer(code):
        start = match.end()
        end = call_end(code, start)
        for position in range(start, end):
            if out[position] != "\n":
                out[position] = " "
    return "".join(out)


def hits(text, patterns):
    """(line, snippet) for every match of `patterns` in Swift source `text`, comments, strings,
    shadows and masks aside."""
    code = exempt_shadows_and_masks(blank_comments_and_strings(text))
    found = []
    for pattern in patterns:
        for match in pattern.finditer(code):
            line = code.count("\n", 0, match.start()) + 1
            found.append((line, text.splitlines()[line - 1].strip()))
    return sorted(found)


def panel_sources():
    return [path for path in sorted(PANEL.rglob("*.swift")) if THEME not in path.parents]


def scan(patterns):
    """{repo-relative path: [(line, snippet)]} for every panel file with a hit."""
    result = {}
    for path in panel_sources():
        found = hits(path.read_text(encoding="utf-8"), patterns)
        if found:
            result[str(path.relative_to(ROOT))] = found
    return result


class PanelDesignTokenTests(unittest.TestCase):
    def check(self, patterns, allowlist, kind, fix):
        found = scan(patterns)
        unlisted = [
            f"{path}:{line}: {snippet}"
            for path, entries in found.items() if path not in allowlist
            for line, snippet in entries
        ]
        self.assertEqual(
            unlisted, [],
            f"Raw {kind} in panel code: {fix} See docs/conventions.md#swiftui-control-panel.")
        stale = [path for path in allowlist if path not in found]
        self.assertEqual(
            stale, [],
            f"These files no longer hold a raw {kind}: delete their entries from the allowlist in"
            " scripts/tests/test_panel_design_tokens.py, so it only shrinks.")

    def test_panel_text_takes_its_size_from_a_type_role(self):
        self.check(
            TYPE, TYPE_ALLOWLIST, "font size",
            "use a role of PanelFont (.font(.panel(.body)), .panelFont(.eyebrow)), or"
            " PanelFont.proportional(to:ratio:weight:) for a size taken from a control's geometry;"
            " AppKit measures with the role's nsFont.")

    def test_panel_colours_come_from_the_theme(self):
        self.check(
            COLOUR, COLOUR_ALLOWLIST, "colour",
            "take it from \\.panelTheme (AccentPalette, SurfacePalette; over a picture the scrim,"
            " mark and control tokens), never .black, .white, a named hue or .secondary/.tertiary,"
            " which ignore the tone.")

    def test_every_allowlisted_file_exists(self):
        for path in list(TYPE_ALLOWLIST) + list(COLOUR_ALLOWLIST):
            self.assertTrue((ROOT / path).is_file(), path)

    def test_the_type_scan_finds_every_spelling_of_a_system_font(self):
        raw = """
        heading.font = .boldSystemFont(ofSize: NSFont.systemFontSize + 2)
        let digits = NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .regular)
        Text("H").font(.system(.caption, design: .rounded))
        Text("I").font(Font.caption)
        Text("J").font(SwiftUI.Font.headline.weight(.semibold))
        """
        self.assertEqual([line for line, _ in hits(raw, TYPE)], [2, 3, 4, 5, 6])
        clean = """
        Text("K").font(.panel(.caption))
        let size = NSFont.systemFontSize
        let font = PanelFont.caption.nsFont
        Image(systemName: "photo").fontDesign(.rounded)
        """
        self.assertEqual(hits(clean, TYPE), [])

    def test_the_scan_finds_raw_sizes_and_colours_and_nothing_else(self):
        raw = """
        Text("A").font(.system(size: 12, weight: .semibold))
        let font = NSFont.systemFont(ofSize: 13)
        Text("B").font(.caption)
        Circle().fill(.black.opacity(0.4))
        Text("C").foregroundStyle(Color.white)
        Image(systemName: "x").foregroundStyle(.secondary)
        Capsule().fill(Color(red: 0.8, green: 0.1, blue: 0.2))
        Rectangle().fill(Color.green)
        Text("G").foregroundStyle(isOn ? .primary : Color.secondary)
        """
        self.assertEqual([line for line, _ in hits(raw, TYPE)], [2, 3, 4])
        self.assertEqual([line for line, _ in hits(raw, COLOUR)], [5, 6, 7, 8, 9, 10])
        clean = """
        Text("D").font(.panel(.body))
        Button("E") {}.buttonStyle(.panelSecondary)
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        Text("F").foregroundStyle(theme.surface.markGlyph.color)
        let look: PanelButtonLook = .quiet
        // .font(.system(size: 9)) and .black in a comment
        let words = "Color.white .secondary .system(size: 3)"
        view.shadow(color: .black.opacity(0.18), radius: 10, y: 4)
        image.mask { LinearGradient(colors: [.black, .clear], startPoint: .top, endPoint: .bottom) }
        """
        self.assertEqual(hits(clean, TYPE), [])
        self.assertEqual(hits(clean, COLOUR), [])


if __name__ == "__main__":
    if "--print" in sys.argv:
        for name, patterns in (("TYPE", TYPE), ("COLOUR", COLOUR)):
            print(name)
            for path, entries in scan(patterns).items():
                print(f"  {path}: {len(entries)}")
    else:
        unittest.main()
