import XCTest

@testable import WallpaperMachine

/// Settings › Playback & Power › When another app plays sound and When windows cover the desktop
/// › Reduce volume: one more choice beside Mute on each row, one level for both, asked for only
/// once one of them chooses it, and only a whole percentage from 0 to 100 accepted.
@MainActor
final class OtherAudioVolumeSettingsTests: PanelTestCase {
  func testReduceVolumeIsOfferedBesideMute() throws {
    try pinPanelLanguageToEnglish()
    XCTAssertEqual(
      OtherAudioAction.allCases.map(\.title), ["Keep running", "Reduce volume", "Mute", "Pause"])
    XCTAssertEqual(
      DesktopCoveredAction.allCases.map(\.title), ["Pause", "Mute", "Reduce volume", "Keep running"])
  }

  /// A covered desktop that turns wallpapers down asks for the same level, and the level's row
  /// follows the first row that chose Reduce volume.
  func testACoveredDesktopThatTurnsWallpapersDownAsksForTheSharedLevel() async throws {
    try pinPanelLanguageToEnglish()
    try await withRecordingPanel { panel, _ in
      panel.store.snapshotRevision = 1
      let controller = panel.controller
      let settings = controller.settings
      XCTAssertEqual(controller.playbackSettings.desktopCoveredAction, .pause)

      try await controller.setDesktopCoveredAction(.mute)
      XCTAssertEqual(controller.playback.desktopCoveredAction, .mute)
      XCTAssertFalse(controller.playbackSettings.showsOtherAudioVolume, "Mute has no level")

      try await controller.setDesktopCoveredAction(.reduceVolume)
      XCTAssertEqual(controller.playback.desktopCoveredAction, .reduceVolume)
      XCTAssertTrue(controller.playbackSettings.showsOtherAudioVolume)
      XCTAssertTrue(controller.playbackSettings.reducedVolumeFollowsDesktopCovered)
      settings.query = "Reduce volume to"
      XCTAssertTrue(settings.search.shows(PlaybackSettingsSection.otherAudioVolume))

      try await controller.setOtherAudioAction(.reduceVolume)
      try await controller.setOtherAudioVolume(40)
      XCTAssertEqual(controller.playback.otherAudioVolume, 40, "One level for both rows")
      XCTAssertTrue(controller.playbackSettings.reducedVolumeFollowsDesktopCovered)

      try await controller.setDesktopCoveredAction(.keepRunning)
      XCTAssertTrue(controller.playbackSettings.showsOtherAudioVolume, "Other-app sound still turns them down")
      XCTAssertFalse(controller.playbackSettings.reducedVolumeFollowsDesktopCovered)

      try await controller.setOtherAudioAction(.keepRunning)
      XCTAssertFalse(controller.playbackSettings.showsOtherAudioVolume)
    }
  }

  func testTheLevelIsAskedForOnlyWhileReduceVolumeIsTheChoice() async throws {
    try pinPanelLanguageToEnglish()
    try await withRecordingPanel { panel, _ in
      panel.store.snapshotRevision = 1
      let controller = panel.controller
      let settings = controller.settings
      settings.query = "When another app plays sound"
      XCTAssertTrue(settings.search.shows(PlaybackSettingsSection.otherAudio))
      settings.query = "Reduce volume to"
      XCTAssertTrue(settings.search.hasNoResults, "Keep running is the default and needs no level")
      XCTAssertFalse(controller.playbackSettings.showsOtherAudioVolume)

      for action in [OtherAudioAction.mute, .pause] {
        try await controller.setOtherAudioAction(action)
        XCTAssertFalse(controller.playbackSettings.showsOtherAudioVolume, "\(action) has no level")
      }

      try await controller.setOtherAudioAction(.reduceVolume)
      XCTAssertTrue(settings.search.shows(PlaybackSettingsSection.otherAudioVolume))
      XCTAssertTrue(controller.playbackSettings.showsOtherAudioVolume)
    }
  }

  func testTheLevelReachesThePreferencesAndOneOutsideTheSliderIsRefused() async throws {
    try await withRecordingPanel { panel, _ in
      let controller = panel.controller
      XCTAssertEqual(controller.playbackSettings.otherAudioAction, .keepRunning)
      XCTAssertEqual(controller.playbackSettings.otherAudioVolume, 30)

      try await controller.setOtherAudioAction(.reduceVolume)
      try await controller.setOtherAudioVolume(55)
      XCTAssertEqual(controller.playback.otherAudioAction, .reduceVolume)
      XCTAssertEqual(controller.playback.otherAudioVolume, 55)
      XCTAssertEqual(controller.playbackSettings.otherAudioVolume, 55)

      for level in [0, 100] {
        try await controller.setOtherAudioVolume(level)
        XCTAssertEqual(controller.playbackSettings.otherAudioVolume, level)
      }
      for level in [-1, 101] {
        do {
          try await controller.setOtherAudioVolume(level)
          XCTFail("\(level)% is outside the slider")
        } catch is InvalidControlValue {}
      }
      XCTAssertEqual(controller.playback.otherAudioVolume, 100)
    }
  }
}
