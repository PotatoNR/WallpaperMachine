import XCTest
@testable import WallpaperMachine

@MainActor
private final class CompositionProbe {
    var presentations: [GlobalPresentation] = []
    var audio: [Bool] = []
    var sessionLocked = false
    var sleepAction = DisplaySleepAction.pause
    var rules: Set<AppRuleAction> = []
    var otherAudio = false
    var otherAudioAction = OtherAudioAction.keepRunning
    /// The share of its own volume a wallpaper keeps under Reduce volume, and what the bridge was told.
    var otherAudioVolume: Float = 0.3
    var gains: [Float] = []
    /// Failures the gain channel returns before it starts acknowledging.
    var gainFailures = 0
    var userMuted = false
    /// What the conditions ask the quality channel for, and what it was told, in order.
    var reductions: Set<QualityReduction> = []
    var quality: [Set<QualityReduction>] = []
    /// Failures the quality channel returns before it starts acknowledging.
    var qualityFailures = 0
    /// Every delivery in the order it was made, across the channels.
    var order: [Delivery] = []
    /// Holds the global acknowledgement until the test releases it.
    var holdGlobal = false
    var heldGlobal: [WallpaperPresentationPolicy.ApplyCompletion] = []
    /// The displays with a wallpaper and whether each is on screen.
    var surfaces = [WallpaperSurfaceVisibility(displayID: 1, isVisible: true)]
    /// Displays whose working area other windows cover, and what the user chose for that.
    var covered: Set<UInt32> = []
    var coveredAction = DesktopCoveredAction.keepRunning
    /// Per-display decisions, in delivery order.
    var displays: [(display: UInt32, suspended: Bool)] = []
    var displayFailures = 0
    var onDisplay: ((UInt32, Bool) -> Void)?

    func setVisible(_ visible: Bool, display: UInt32) {
        surfaces = surfaces.map {
            $0.displayID == display ? WallpaperSurfaceVisibility(displayID: display, isVisible: visible) : $0
        }
    }
}

private struct DeliveryRefused: Error {}

/// One request the policy made of the bridge, what it asked for and not how the log words it.
private enum Delivery: Equatable {
    case global(GlobalPresentation)
    case audio(suppressed: Bool)
    case gain(Float)
    case quality(Set<QualityReduction>)
}

/// A Mac with no battery to read: the low-battery rule is left on keep running in these tests.
@MainActor
private final class NoBattery: BatteryLevelSource {
    var reading: BatteryReading? { nil }
    func start(onChange: @escaping @MainActor () -> Void) {}
    func stop() {}
}

@MainActor
final class PlaybackPolicyCompositionTests: XCTestCase {
    private let workspaceCenter = NotificationCenter()
    private let lockCenter = NotificationCenter()
    private let windowCenter = NotificationCenter()

    private func makePolicy(
        _ probe: CompositionProbe, conditions: SystemConditionMonitor? = nil, settle: Duration = .zero
    ) -> WallpaperPresentationPolicy {
        WallpaperPresentationPolicy(
            workspaceCenter: workspaceCenter,
            lockCenter: lockCenter,
            windowCenter: windowCenter,
            surfaces: { probe.surfaces },
            sessionState: { .init(locked: probe.sessionLocked) },
            displaySleepAction: { probe.sleepAction },
            appRuleActions: { probe.rules.union(conditions?.actions ?? []) },
            otherAudioActive: { probe.otherAudio },
            otherAudioAction: { probe.otherAudioAction },
            otherAudioVolume: { probe.otherAudioVolume },
            userMuted: { probe.userMuted },
            desktopCoveredAction: { probe.coveredAction },
            coveredDisplays: { probe.covered },
            qualityReductions: { probe.reductions.union(conditions?.qualityReductions ?? []) },
            occlusionSettleDelay: settle,
            applyGlobal: { presentation, completion in
                probe.presentations.append(presentation)
                probe.order.append(.global(presentation))
                if probe.holdGlobal {
                    probe.heldGlobal.append(completion)
                } else {
                    completion(.success(()))
                }
            },
            applyAudio: { suppressed, completion in
                probe.audio.append(suppressed)
                probe.order.append(.audio(suppressed: suppressed))
                completion(.success(()))
            },
            applyAudioGain: { gain, completion in
                probe.gains.append(gain)
                probe.order.append(.gain(gain))
                if probe.gainFailures > 0 {
                    probe.gainFailures -= 1
                    completion(.failure(DeliveryRefused()))
                } else {
                    completion(.success(()))
                }
            },
            applyQuality: { reductions, completion in
                probe.quality.append(reductions)
                probe.order.append(.quality(reductions))
                if probe.qualityFailures > 0 {
                    probe.qualityFailures -= 1
                    completion(.failure(DeliveryRefused()))
                } else {
                    completion(.success(()))
                }
            },
            applyDisplay: { display, suspended, completion in
                probe.displays.append((display, suspended))
                probe.onDisplay?(display, suspended)
                if probe.displayFailures > 0 {
                    probe.displayFailures -= 1
                    completion(.failure(DeliveryRefused()))
                } else {
                    completion(.success(()))
                }
            })
    }

    func testDisplaySleepStopUnloadsAndPauseOnlySuspends() {
        let probe = CompositionProbe()
        probe.sleepAction = .stop
        let policy = makePolicy(probe)
        policy.start()
        defer { policy.stop() }

        workspaceCenter.post(name: NSWorkspace.screensDidSleepNotification, object: nil)
        XCTAssertEqual(probe.presentations, [.unloaded])
        XCTAssertEqual(policy.globalPresentation, .unloaded)
        XCTAssertTrue(policy.isSuspended)

        probe.sleepAction = .pause
        policy.evaluate()
        XCTAssertEqual(policy.globalPresentation, .suspended)
        XCTAssertEqual(probe.presentations.last, .suspended)
    }

    func testLockPlusPauseRuleSuspendsAndStopBeatsPause() {
        let probe = CompositionProbe()
        probe.sessionLocked = true
        probe.rules = [.pause]
        let policy = makePolicy(probe)
        policy.start()
        defer { policy.stop() }
        XCTAssertEqual(probe.presentations, [.suspended])
        XCTAssertTrue(probe.audio.isEmpty, "Pause does not mute")

        probe.rules = [.pause, .stop]
        policy.evaluate()
        XCTAssertEqual(policy.globalPresentation, .unloaded)
        XCTAssertEqual(probe.presentations.last, .unloaded)
    }

    func testMuteComesFromARuleOrFromOtherAudio() {
        let probe = CompositionProbe()
        probe.rules = [.mute]
        let policy = makePolicy(probe)
        policy.start()
        defer { policy.stop() }
        XCTAssertEqual(probe.audio, [true])
        XCTAssertTrue(probe.presentations.isEmpty, "Mute leaves presentation running")
        XCTAssertFalse(policy.isSuspended)

        probe.rules = []
        policy.evaluate()
        XCTAssertEqual(probe.audio.last, false)

        probe.otherAudio = true
        probe.otherAudioAction = .mute
        policy.evaluate()
        XCTAssertEqual(probe.audio.last, true)
        XCTAssertTrue(probe.presentations.isEmpty)

        probe.otherAudioAction = .pause
        policy.evaluate()
        XCTAssertEqual(probe.audio.last, false)
        XCTAssertEqual(probe.presentations, [.suspended])
    }

    /// The user's own mute of every wallpaper is one more reason for the bridge's single
    /// audio-suppression flag, not a replacement for the others: it silences without touching
    /// presentation, and what else is muting keeps holding when it is lifted.
    func testUserMuteComposesWithRulesAndOtherAudio() {
        let probe = CompositionProbe()
        probe.userMuted = true
        let policy = makePolicy(probe)
        policy.start()
        defer { policy.stop() }
        XCTAssertEqual(probe.audio, [true], "A mute that was already on at launch reaches the bridge")
        XCTAssertTrue(policy.isAudioSuppressed)
        XCTAssertTrue(probe.presentations.isEmpty, "Muting never pauses or unloads anything")
        XCTAssertFalse(policy.isSuspended)

        // A mute rule and other-app audio hold as well, so lifting the user's mute changes nothing.
        probe.rules = [.mute]
        probe.otherAudio = true
        probe.otherAudioAction = .mute
        policy.evaluate()
        XCTAssertEqual(probe.audio, [true], "Already suppressed: no second delivery")
        probe.userMuted = false
        policy.evaluate()
        XCTAssertEqual(probe.audio, [true], "The rule and the other audio still mute")
        XCTAssertTrue(policy.isAudioSuppressed)

        probe.rules = []
        policy.evaluate()
        XCTAssertTrue(policy.isAudioSuppressed, "Other-app audio alone still mutes")
        probe.otherAudio = false
        policy.evaluate()
        XCTAssertEqual(probe.audio, [true, false], "Nothing mutes any more")
        XCTAssertFalse(policy.isAudioSuppressed)

        // And back on from silence, with no rule involved.
        probe.userMuted = true
        policy.evaluate()
        XCTAssertEqual(probe.audio, [true, false, true])
        XCTAssertTrue(probe.presentations.isEmpty)
    }

    func testTeardownRestoresSoundWhateverTheUserChose() {
        let probe = CompositionProbe()
        probe.userMuted = true
        let policy = makePolicy(probe)
        policy.start()
        XCTAssertEqual(probe.audio, [true])

        policy.stop()
        XCTAssertEqual(probe.audio.last, false, "Teardown must never leave a surface muted")
        XCTAssertFalse(policy.isAudioSuppressed)
    }

    func testKeepRunningIgnoresOtherAudio() {
        let probe = CompositionProbe()
        probe.otherAudio = true
        probe.otherAudioAction = .keepRunning
        let policy = makePolicy(probe)
        policy.start()
        defer { policy.stop() }
        XCTAssertTrue(probe.presentations.isEmpty)
        XCTAssertTrue(probe.audio.isEmpty)
        XCTAssertEqual(policy.globalPresentation, .running)
        XCTAssertFalse(policy.isAudioSuppressed)
    }

    // MARK: Reduced volume

    func testReduceVolumeTurnsWallpapersDownOnlyWhileAnotherAppPlaysSound() {
        let probe = CompositionProbe()
        probe.otherAudioAction = .reduceVolume
        let policy = makePolicy(probe)
        policy.start()
        defer { policy.stop() }
        XCTAssertTrue(probe.gains.isEmpty, "Nothing else is playing, so wallpapers keep their own volume")
        XCTAssertEqual(policy.audioGain, 1)

        probe.otherAudio = true
        policy.evaluate()
        XCTAssertEqual(probe.gains, [0.3])
        XCTAssertEqual(policy.audioGain, 0.3)
        XCTAssertTrue(probe.audio.isEmpty, "Turning down is not muting")
        XCTAssertFalse(policy.isAudioSuppressed)
        XCTAssertTrue(probe.presentations.isEmpty, "And it never pauses anything")
        XCTAssertFalse(policy.isSuspended)

        policy.evaluate()
        XCTAssertEqual(probe.gains, [0.3], "Already turned down: no second delivery")

        probe.otherAudio = false
        policy.evaluate()
        XCTAssertEqual(probe.gains, [0.3, 1], "The other sound ended, so each wallpaper is back at its own volume")
    }

    /// Dragging the slider while another app is already playing: the level is a number, so a new
    /// one is a new decision even though the rule was holding all along.
    func testANewLevelIsDeliveredWhileTheRuleAlreadyHolds() {
        let probe = CompositionProbe()
        probe.otherAudio = true
        probe.otherAudioAction = .reduceVolume
        let policy = makePolicy(probe)
        policy.start()
        defer { policy.stop() }
        XCTAssertEqual(probe.gains, [0.3])

        probe.otherAudioVolume = 0.65
        policy.evaluate()
        XCTAssertEqual(probe.gains, [0.3, 0.65])

        // A level outside 0 to 1 never reaches the bridge as it is.
        probe.otherAudioVolume = 1.8
        policy.evaluate()
        XCTAssertEqual(probe.gains.last, 1)
        probe.otherAudioVolume = -0.2
        policy.evaluate()
        XCTAssertEqual(probe.gains.last, 0)
    }

    func testOnlyReduceVolumeChangesTheGainAndTheOtherChoicesLiftIt() {
        let probe = CompositionProbe()
        probe.otherAudio = true
        probe.otherAudioAction = .reduceVolume
        let policy = makePolicy(probe)
        policy.start()
        defer { policy.stop() }
        XCTAssertEqual(probe.gains, [0.3])

        probe.otherAudioAction = .mute
        policy.evaluate()
        XCTAssertEqual(probe.gains, [0.3, 1], "Mute silences through its own channel, at the saved volume")
        XCTAssertEqual(probe.audio, [true])

        probe.otherAudioAction = .pause
        policy.evaluate()
        XCTAssertEqual(probe.gains, [0.3, 1])
        XCTAssertEqual(probe.presentations, [.suspended])

        probe.otherAudioAction = .keepRunning
        policy.evaluate()
        XCTAssertEqual(probe.gains, [0.3, 1])
        XCTAssertEqual(policy.audioGain, 1)
    }

    /// A mute from anywhere else still silences: the user's Mute All or a mute rule holds on its
    /// own channel while the wallpapers are also turned down, and lifting it leaves them turned
    /// down, not at full volume.
    func testAMuteStillSilencesWallpapersThatAreTurnedDown() {
        let probe = CompositionProbe()
        probe.otherAudio = true
        probe.otherAudioAction = .reduceVolume
        probe.userMuted = true
        let policy = makePolicy(probe)
        policy.start()
        defer { policy.stop() }
        XCTAssertEqual(probe.audio, [true])
        XCTAssertEqual(probe.gains, [0.3])
        XCTAssertEqual(probe.order, [.audio(suppressed: true), .gain(0.3)], "Silence first, then the level")

        probe.userMuted = false
        probe.rules = [.mute]
        policy.evaluate()
        XCTAssertEqual(probe.audio, [true], "The rule still mutes")

        probe.rules = []
        policy.evaluate()
        XCTAssertEqual(probe.audio, [true, false])
        XCTAssertEqual(probe.gains, [0.3], "Unmuted into the reduced volume, which never left")
        XCTAssertEqual(policy.audioGain, 0.3)
    }

    func testARefusedLevelIsSentAgainAtTheNextEvaluation() {
        let probe = CompositionProbe()
        probe.otherAudio = true
        probe.otherAudioAction = .reduceVolume
        probe.gainFailures = 1
        let policy = makePolicy(probe)
        policy.start()
        defer { policy.stop() }
        XCTAssertEqual(probe.gains, [0.3], "Refused once, and not retried in a loop")

        policy.evaluate()
        XCTAssertEqual(probe.gains, [0.3, 0.3], "The level the bridge never took is sent again")
        policy.evaluate()
        XCTAssertEqual(probe.gains, [0.3, 0.3], "Once taken it is not sent a third time")
    }

    func testTeardownRestoresEveryWallpapersOwnVolume() {
        let probe = CompositionProbe()
        probe.otherAudio = true
        probe.otherAudioAction = .reduceVolume
        let policy = makePolicy(probe)
        policy.start()
        XCTAssertEqual(probe.gains, [0.3])

        policy.stop()
        XCTAssertEqual(probe.gains.last, 1, "Teardown must never leave a surface turned down")
        XCTAssertEqual(policy.audioGain, 1)
    }

    func testStopRestoresRunningAndUnmuted() {
        let probe = CompositionProbe()
        probe.rules = [.stop, .mute]
        let policy = makePolicy(probe)
        policy.start()
        XCTAssertEqual(probe.presentations, [.unloaded])
        XCTAssertEqual(probe.audio, [true])

        policy.stop()
        XCTAssertEqual(probe.presentations.last, .running)
        XCTAssertEqual(probe.audio.last, false)
        XCTAssertEqual(policy.globalPresentation, .running)
        XCTAssertFalse(policy.isAudioSuppressed)
        XCTAssertFalse(policy.isSuspended)
    }

    // MARK: Sound under a covered desktop

    /// Mute for a covered desktop silences the wallpapers and leaves them playing: nothing is
    /// suspended, globally or for the covered display, and uncovering gives the sound back.
    func testMuteForACoveredDesktopSilencesWithoutPausingAnything() {
        let probe = CompositionProbe()
        probe.coveredAction = .mute
        probe.covered = [1]
        let policy = makePolicy(probe)
        policy.start()
        defer { policy.stop() }
        XCTAssertEqual(probe.audio, [true])
        XCTAssertTrue(policy.isDesktopCoveredForSound)
        XCTAssertTrue(probe.presentations.isEmpty, "Muting never pauses the desktop")
        XCTAssertTrue(probe.displays.isEmpty, "Nor the covered display")
        XCTAssertTrue(policy.suspendedDisplayIDs.isEmpty)
        XCTAssertTrue(probe.gains.isEmpty, "Silenced at each wallpaper's own volume")

        probe.covered = []
        windowCenter.post(name: NSWindow.didChangeOcclusionStateNotification, object: nil)
        XCTAssertEqual(probe.audio, [true, false])
        XCTAssertFalse(policy.isDesktopCoveredForSound)
    }

    /// Reduce volume for a covered desktop uses the level other-app sound uses. When both hold,
    /// the volume is that level once, not the level of the level.
    func testReduceVolumeForACoveredDesktopUsesTheOneSharedLevel() {
        let probe = CompositionProbe()
        probe.coveredAction = .reduceVolume
        let policy = makePolicy(probe)
        policy.start()
        defer { policy.stop() }
        XCTAssertTrue(probe.gains.isEmpty, "Nothing covers the desktop yet")

        probe.covered = [1]
        policy.evaluate()
        XCTAssertEqual(probe.gains, [0.3])
        XCTAssertTrue(probe.audio.isEmpty, "Turning down is not muting")
        XCTAssertTrue(probe.displays.isEmpty)

        probe.otherAudio = true
        probe.otherAudioAction = .reduceVolume
        policy.evaluate()
        XCTAssertEqual(probe.gains, [0.3], "Both reasons, one level")

        probe.covered = []
        policy.evaluate()
        XCTAssertEqual(probe.gains, [0.3], "The other sound still turns them down")
        probe.otherAudio = false
        policy.evaluate()
        XCTAssertEqual(probe.gains, [0.3, 1])
    }

    /// Wallpaper sound is one channel for every display, so a covered display alone does not
    /// silence a wallpaper still in view on another. A display hidden for another reason (a
    /// full-screen app) is not in view and does not keep the sound.
    func testSoundChangesOnlyOnceEveryWallpaperInViewIsCovered() {
        let probe = CompositionProbe()
        probe.surfaces = [
            WallpaperSurfaceVisibility(displayID: 1, isVisible: true),
            WallpaperSurfaceVisibility(displayID: 2, isVisible: true),
        ]
        probe.coveredAction = .mute
        probe.covered = [1]
        let policy = makePolicy(probe)
        policy.start()
        defer { policy.stop() }
        XCTAssertTrue(probe.audio.isEmpty, "The wallpaper on display 2 is still in view")
        XCTAssertFalse(policy.isDesktopCoveredForSound)

        probe.covered = [1, 2]
        policy.evaluate()
        XCTAssertEqual(probe.audio, [true])

        probe.covered = [1]
        probe.setVisible(false, display: 2)
        policy.evaluate()
        XCTAssertEqual(probe.audio, [true], "Display 2 is out of view, and display 1 is still covered")

        probe.setVisible(true, display: 2)
        policy.evaluate()
        XCTAssertEqual(probe.audio, [true, false], "Display 2 is in view again, uncovered")
        XCTAssertTrue(probe.displays.allSatisfy { $0.display == 2 }, "Only the hidden display paused")
    }

    /// While no wallpaper is in view at all (a full-screen app, say) the last answer stands, so
    /// coming back to the same covered desktop brings no burst of sound before the settle.
    func testNoWallpaperInViewKeepsTheLastAnswer() {
        let probe = CompositionProbe()
        probe.coveredAction = .mute
        probe.covered = [1]
        let policy = makePolicy(probe)
        policy.start()
        defer { policy.stop() }
        XCTAssertEqual(probe.audio, [true])

        probe.setVisible(false, display: 1)
        probe.covered = []
        policy.evaluate()
        XCTAssertEqual(probe.audio, [true], "Nothing is in view, so nothing is uncovered either")
        XCTAssertTrue(policy.isDesktopCoveredForSound)

        probe.setVisible(true, display: 1)
        probe.covered = [1]
        policy.evaluate()
        XCTAssertEqual(probe.audio, [true])

        probe.covered = []
        policy.evaluate()
        XCTAssertEqual(probe.audio, [true, false])
    }

    /// The mute waits for the same settle a covered display's pause does, so a brief cover never
    /// cuts the sound, and uncovering gives it back at once.
    func testTheSoundWaitsForTheSettleAndComesBackAtOnce() async throws {
        let probe = CompositionProbe()
        probe.coveredAction = .mute
        let policy = makePolicy(probe, settle: .milliseconds(20))
        policy.start()
        defer { policy.stop() }

        probe.covered = [1]
        policy.evaluate()
        probe.covered = []
        policy.evaluate()
        try await Task.sleep(for: .milliseconds(80))
        XCTAssertTrue(probe.audio.isEmpty, "Uncovered within the settle: never muted")

        probe.covered = [1]
        policy.evaluate()
        XCTAssertTrue(probe.audio.isEmpty, "Covering waits for the settle")
        try await Task.sleep(for: .milliseconds(80))
        XCTAssertEqual(probe.audio, [true])

        probe.covered = []
        policy.evaluate()
        XCTAssertEqual(probe.audio, [true, false], "Uncovering does not wait")
    }

    /// A new choice applies to a desktop that is already covered at the next evaluation, and no
    /// step lets the sound out louder than the new choice: Mute to Reduce volume sets the level
    /// before it lifts the mute, Pause keeps the covered desktop silent and pauses the covered
    /// display, and Keep running gives the sound back.
    func testChangingTheChoiceOnACoveredDesktopAppliesAtTheNextEvaluation() {
        let probe = CompositionProbe()
        probe.coveredAction = .mute
        probe.covered = [1]
        let policy = makePolicy(probe)
        policy.start()
        defer { policy.stop() }
        XCTAssertEqual(probe.order, [.audio(suppressed: true)])

        probe.coveredAction = .reduceVolume
        policy.evaluate()
        XCTAssertEqual(
            probe.order, [.audio(suppressed: true), .gain(0.3), .audio(suppressed: false)],
            "The level first, then the sound, so it never plays at its own volume in between")

        probe.coveredAction = .pause
        policy.evaluate()
        XCTAssertEqual(
            Array(probe.order.suffix(2)), [.audio(suppressed: true), .gain(1)],
            "Silent again before the level goes back up")
        XCTAssertTrue(policy.isDesktopCoveredForSound, "The covered desktop is still silent under Pause")
        XCTAssertEqual(probe.displays.map(\.suspended), [true], "Pause suspends the covered display")

        probe.coveredAction = .keepRunning
        policy.evaluate()
        XCTAssertEqual(probe.displays.map(\.suspended), [true, false])
        XCTAssertEqual(probe.order.last, .audio(suppressed: false))
        XCTAssertFalse(policy.isDesktopCoveredForSound)
        XCTAssertEqual(probe.gains, [0.3, 1])
    }

    func testPausedCoveredDesktopMutesBeforeResuming() async {
        await checkPausedCoveredDesktopResumes(with: .mute)
    }

    func testPausedCoveredDesktopReducesVolumeBeforeResuming() async {
        await checkPausedCoveredDesktopResumes(with: .reduceVolume)
    }

    func testPausedCoveredDesktopWaitsForARefusedLowerVolumeBeforeResuming() async {
        await checkPausedCoveredDesktopResumes(with: .reduceVolume, gainFailures: 1)
    }

    func testPausedCoveredDisplayMutesBeforeResumingBesideANewlyCoveredDisplay() async {
        await checkPausedCoveredDesktopResumes(with: .mute, pausedDisplays: [1])
    }

    func testPausedCoveredDisplayReducesVolumeBeforeResumingBesideANewlyCoveredDisplay() async {
        await checkPausedCoveredDesktopResumes(with: .reduceVolume, pausedDisplays: [1])
    }

    /// A sound-only choice must reach the bridge before any paused, covered display resumes,
    /// even beside a newly covered display or if the lower volume has to be retried.
    private func checkPausedCoveredDesktopResumes(
        with action: DesktopCoveredAction, gainFailures: Int = 0, pausedDisplays: Set<UInt32> = [1, 2]
    ) async {
        let probe = CompositionProbe()
        probe.surfaces = [
            WallpaperSurfaceVisibility(displayID: 1, isVisible: true),
            WallpaperSurfaceVisibility(displayID: 2, isVisible: true),
        ]
        probe.covered = pausedDisplays
        probe.coveredAction = .pause
        let paused = expectation(description: "Covered displays paused")
        paused.expectedFulfillmentCount = pausedDisplays.count
        probe.onDisplay = { _, suspended in
            if suspended { paused.fulfill() }
        }
        let policy = makePolicy(probe, settle: .milliseconds(20))
        policy.start()
        defer {
            probe.onDisplay = nil
            policy.stop()
        }
        await fulfillment(of: [paused], timeout: 5)
        XCTAssertEqual(policy.suspendedDisplayIDs, pausedDisplays)

        probe.onDisplay = { _, suspended in
            guard !suspended else { return }
            XCTAssertEqual(probe.audio.last ?? false, action == .mute,
                           "The mute must land before playback resumes")
            XCTAssertEqual(probe.gains.last ?? 1, action == .reduceVolume ? 0.3 : 1,
                           "The volume must land before playback resumes")
            XCTAssertEqual(probe.gainFailures, 0)
        }
        probe.covered = [1, 2]
        probe.coveredAction = action
        probe.gainFailures = gainFailures
        policy.evaluate()
        if gainFailures > 0 {
            XCTAssertTrue(probe.displays.allSatisfy(\.suspended),
                          "A refused level must leave the displays paused")
            XCTAssertEqual(probe.gains, [0.3])
            policy.evaluate()
            XCTAssertEqual(probe.gains, [0.3, 0.3])
        }
        XCTAssertEqual(probe.displays.filter { !$0.suspended }.map(\.display), pausedDisplays.sorted(),
                       "Already-paused wallpapers resume without another settle, at the chosen sound level")
    }

    func testReconnectedCoveredDisplayMutesBeforeResumingItsRetainedPause() async {
        await checkReconnectedCoveredDisplayResumes(with: .mute)
    }

    func testReconnectedCoveredDisplayReducesVolumeBeforeResumingItsRetainedPause() async {
        await checkReconnectedCoveredDisplayResumes(with: .reduceVolume)
    }

    func testReconnectedCoveredDisplayMutesBeforeRetryingARefusedResume() async {
        await checkReconnectedCoveredDisplayResumes(with: .mute, refuseResume: true)
    }

    func testReconnectedCoveredDisplayReducesVolumeBeforeRetryingARefusedResume() async {
        await checkReconnectedCoveredDisplayResumes(with: .reduceVolume, refuseResume: true)
    }

    /// A disconnect removes the display from the desired pause set, but the bridge retains either
    /// an acknowledged pause or an unknown state after a refused resume. Both need sound first.
    private func checkReconnectedCoveredDisplayResumes(
        with action: DesktopCoveredAction, refuseResume: Bool = false
    ) async {
        let probe = CompositionProbe()
        probe.covered = [1]
        probe.coveredAction = .pause
        let paused = expectation(description: "Covered display paused")
        probe.onDisplay = { _, suspended in
            if suspended { paused.fulfill() }
        }
        let policy = makePolicy(probe, settle: .milliseconds(20))
        policy.start()
        defer {
            probe.onDisplay = nil
            policy.stop()
        }
        await fulfillment(of: [paused], timeout: 5)
        probe.onDisplay = nil
        XCTAssertEqual(probe.displays.map(\.suspended), [true])

        if refuseResume {
            probe.covered = []
            probe.displayFailures = 1
            policy.evaluate()
            XCTAssertEqual(probe.displayFailures, 0, "The resume reached the bridge and was refused")
        }
        probe.surfaces = []
        policy.evaluate()
        XCTAssertTrue(policy.suspendedDisplayIDs.isEmpty)

        probe.coveredAction = action
        probe.covered = [1]
        policy.evaluate()
        XCTAssertTrue(probe.audio.isEmpty)
        XCTAssertTrue(probe.gains.isEmpty)

        let previousDeliveries = probe.displays.count
        probe.onDisplay = { display, suspended in
            XCTAssertEqual(display, 1)
            XCTAssertFalse(suspended)
            XCTAssertEqual(probe.audio.last ?? false, action == .mute,
                           "The mute must reach the bridge before the reconnected wallpaper resumes")
            XCTAssertEqual(probe.gains.last ?? 1, action == .reduceVolume ? 0.3 : 1,
                           "The lower volume must reach the bridge before the reconnected wallpaper resumes")
        }
        probe.surfaces = [WallpaperSurfaceVisibility(displayID: 1, isVisible: true)]
        policy.evaluate()
        XCTAssertEqual(probe.displays.count, previousDeliveries + 1,
                       "The reconnected wallpaper resumes immediately at the chosen sound level")
    }

    /// A lower level the bridge refused is not known to have landed, so the mute stays until the
    /// level is sent again and taken; only then is the sound let out.
    func testTheMuteStaysUntilARefusedLowerLevelIsTaken() {
        let probe = CompositionProbe()
        probe.coveredAction = .mute
        probe.covered = [1]
        let policy = makePolicy(probe)
        policy.start()
        defer { policy.stop() }

        probe.coveredAction = .reduceVolume
        probe.gainFailures = 1
        policy.evaluate()
        XCTAssertEqual(probe.order, [.audio(suppressed: true), .gain(0.3)], "Refused, so still muted")

        policy.evaluate()
        XCTAssertEqual(
            probe.order, [.audio(suppressed: true), .gain(0.3), .gain(0.3), .audio(suppressed: false)],
            "The level is taken, then the sound comes back at it")
    }

    /// Lifting a mute while the level goes back up needs no wait: the sound comes back no louder
    /// than the decision either way.
    func testAMuteLiftedWhileTheLevelRisesIsNotHeldBack() {
        let probe = CompositionProbe()
        probe.coveredAction = .reduceVolume
        probe.covered = [1]
        probe.userMuted = true
        let policy = makePolicy(probe)
        policy.start()
        defer { policy.stop() }
        XCTAssertEqual(probe.order, [.audio(suppressed: true), .gain(0.3)])

        probe.userMuted = false
        probe.covered = []
        policy.evaluate()
        XCTAssertEqual(
            probe.order, [.audio(suppressed: true), .gain(0.3), .audio(suppressed: false), .gain(1)])
    }

    /// Changing a muted covered desktop to Pause keeps it silent through the settle the pause waits
    /// for, instead of letting the sound out for that second; the sound comes back with the
    /// wallpaper when the desktop shows again. Pause alone never silences anything.
    func testAMutedCoveredDesktopChangedToPauseStaysSilentUntilItIsUncovered() async throws {
        let probe = CompositionProbe()
        probe.coveredAction = .mute
        probe.covered = [1]
        let policy = makePolicy(probe, settle: .milliseconds(20))
        policy.start()
        defer { policy.stop() }
        try await Task.sleep(for: .milliseconds(80))
        XCTAssertEqual(probe.audio, [true])

        probe.coveredAction = .pause
        policy.evaluate()
        XCTAssertEqual(probe.audio, [true], "Still silent while the pause waits for the settle")
        XCTAssertTrue(probe.displays.isEmpty)
        try await Task.sleep(for: .milliseconds(80))
        XCTAssertEqual(probe.displays.map(\.suspended), [true])
        XCTAssertEqual(probe.audio, [true])

        probe.covered = []
        policy.evaluate()
        XCTAssertEqual(probe.audio, [true, false])
        XCTAssertEqual(probe.displays.map(\.suspended), [true, false])

        probe.covered = [1]
        policy.evaluate()
        try await Task.sleep(for: .milliseconds(80))
        XCTAssertEqual(probe.audio, [true, false], "Pause on its own pauses and leaves the sound alone")
        XCTAssertEqual(probe.displays.map(\.suspended), [true, false, true])
    }

    /// A covered desktop is one more reason for the mute, beside the user's own and the rules:
    /// lifting the user's mute keeps a covered desktop silent, and teardown releases everything.
    func testACoveredDesktopComposesWithTheUsersMuteAndTeardownReleasesIt() {
        let probe = CompositionProbe()
        probe.coveredAction = .mute
        probe.covered = [1]
        probe.userMuted = true
        let policy = makePolicy(probe)
        policy.start()
        XCTAssertEqual(probe.audio, [true])

        probe.userMuted = false
        policy.evaluate()
        XCTAssertEqual(probe.audio, [true], "The covered desktop still mutes")

        policy.stop()
        XCTAssertEqual(probe.audio, [true, false], "Teardown must never leave a surface muted")
        XCTAssertFalse(policy.isDesktopCoveredForSound)
    }

    // MARK: Quality channel

    func testQualityReductionIsDeliveredOnItsOwnAndNeverSuspends() {
        let probe = CompositionProbe()
        let policy = makePolicy(probe)
        policy.start()
        defer { policy.stop() }
        XCTAssertTrue(probe.quality.isEmpty, "The bridge starts unthrottled: nothing to say yet")

        probe.reductions = [.heat]
        policy.evaluate()
        XCTAssertEqual(probe.quality, [[.heat]])
        XCTAssertEqual(policy.qualityReductions, [.heat])
        XCTAssertTrue(probe.presentations.isEmpty, "Reduced quality is not a presentation change")
        XCTAssertTrue(probe.audio.isEmpty)
        XCTAssertFalse(policy.isSuspended)
        XCTAssertTrue(policy.suspendedDisplayIDs.isEmpty)

        policy.evaluate()
        XCTAssertEqual(probe.quality, [[.heat]], "An unchanged set is not sent again")

        probe.reductions = [.heat, .lowBattery]
        policy.evaluate()
        XCTAssertEqual(probe.quality.last, [.heat, .lowBattery], "Another cause joining is a new request")

        probe.reductions = []
        policy.evaluate()
        XCTAssertEqual(probe.quality.last, [], "Nothing asks for it any more")
        XCTAssertEqual(probe.quality.count, 3)
        XCTAssertTrue(policy.qualityReductions.isEmpty)
        XCTAssertTrue(probe.presentations.isEmpty)
    }

    func testAFailedQualityDeliveryIsRetriedByTheNextEvaluation() {
        let probe = CompositionProbe()
        probe.qualityFailures = 1
        let policy = makePolicy(probe)
        policy.start()
        defer { policy.stop() }

        probe.reductions = [.heat]
        policy.evaluate()
        XCTAssertEqual(probe.quality, [[.heat]], "A refusal is not retried inside the same evaluation")

        policy.evaluate()
        XCTAssertEqual(probe.quality, [[.heat], [.heat]], "The next evaluation sends the same request again")

        policy.evaluate()
        XCTAssertEqual(probe.quality.count, 2, "Once acknowledged it stays delivered")
    }

    func testAFailedReleaseIsSentAgainToo() {
        let probe = CompositionProbe()
        probe.reductions = [.lowPowerMode]
        let policy = makePolicy(probe)
        policy.start()
        defer { policy.stop() }
        XCTAssertEqual(probe.quality, [[.lowPowerMode]])

        probe.reductions = []
        probe.qualityFailures = 1
        policy.evaluate()
        policy.evaluate()
        XCTAssertEqual(probe.quality, [[.lowPowerMode], [], []],
                       "A wallpaper must not stay reduced because the release was refused once")
    }

    func testStoppingThePolicyRestoresFullQuality() {
        let probe = CompositionProbe()
        probe.reductions = [.heat]
        let policy = makePolicy(probe)
        policy.start()
        XCTAssertEqual(probe.quality, [[.heat]])

        policy.stop()
        XCTAssertEqual(probe.quality.last, [], "Teardown must never leave a wallpaper reduced")
        XCTAssertTrue(policy.qualityReductions.isEmpty)
    }

    func testQualityIsDeliveredAfterGlobalPresentationAndIndependentOfIt() {
        let probe = CompositionProbe()
        probe.holdGlobal = true
        let policy = makePolicy(probe)
        policy.start()
        defer { policy.stop() }

        probe.reductions = [.lowPowerMode]
        workspaceCenter.post(name: NSWorkspace.screensDidSleepNotification, object: nil)
        XCTAssertEqual(probe.order, [.global(.suspended)], "One acknowledgement at a time: quality waits")
        XCTAssertTrue(probe.quality.isEmpty)

        probe.holdGlobal = false
        probe.heldGlobal.removeFirst()(.success(()))
        XCTAssertEqual(probe.order, [.global(.suspended), .quality([.lowPowerMode])])
        XCTAssertEqual(policy.globalPresentation, .suspended)
        XCTAssertEqual(policy.qualityReductions, [.lowPowerMode])

        workspaceCenter.post(name: NSWorkspace.screensDidWakeNotification, object: nil)
        XCTAssertEqual(policy.globalPresentation, .running)
        XCTAssertEqual(probe.presentations, [.suspended, .running])
        XCTAssertEqual(probe.quality.count, 1, "Waking does not send the unchanged request again")
    }

    /// "When another app is in front" on Pause on battery reaches the policy as the pause rule it
    /// is: another app in front on battery suspends every display, plugging in presents again at
    /// once, and it composes with the user's mute and a mute rule without touching sound.
    func testPauseOnBatterySuspendsOnlyOnBatteryWithAnotherAppInFront() throws {
        let defaults = try TemporaryDefaults.make(for: self).defaults
        let preferences = PlaybackPreferences(defaults: defaults)
        preferences.otherAppInFrontAction = .pauseOnBattery
        var frontmost: String? = "com.apple.finder"
        var onBattery = false
        let monitor = AppRuleMonitor(
            preferences: preferences, workspaceCenter: workspaceCenter, runningBundleIDs: { [] },
            frontmostBundleID: { frontmost }, onBattery: { onBattery },
            desktopBundleIDs: ["com.apple.finder", "com.example.Self"])
        let probe = CompositionProbe()
        probe.userMuted = true
        let policy = WallpaperPresentationPolicy(
            workspaceCenter: workspaceCenter,
            lockCenter: lockCenter,
            windowCenter: windowCenter,
            surfaces: { [WallpaperSurfaceVisibility(displayID: 1, isVisible: true)] },
            sessionState: { .init(locked: false) },
            displaySleepAction: { .pause },
            appRuleActions: { monitor.actions },
            otherAudioActive: { false },
            otherAudioAction: { .keepRunning },
            userMuted: { probe.userMuted },
            qualityReductions: { [] },
            occlusionSettleDelay: .zero,
            applyGlobal: { presentation, completion in
                probe.presentations.append(presentation)
                completion(.success(()))
            },
            applyAudio: { suppressed, completion in
                probe.audio.append(suppressed)
                completion(.success(()))
            },
            applyQuality: { _, completion in completion(.success(())) },
            applyDisplay: { _, _, completion in completion(.success(())) })
        monitor.onChange = { policy.evaluate() }
        monitor.start()
        policy.start()
        defer {
            monitor.onChange = nil
            monitor.stop()
            policy.stop()
        }
        func activate(_ bundleID: String?) {
            frontmost = bundleID
            workspaceCenter.post(name: NSWorkspace.didActivateApplicationNotification, object: nil)
        }

        activate("com.example.Editor")
        XCTAssertTrue(probe.presentations.isEmpty, "Plugged in, another app in front changes nothing")
        XCTAssertEqual(policy.globalPresentation, .running)

        onBattery = true
        monitor.refresh()
        XCTAssertEqual(probe.presentations, [.suspended], "Unplugged with another app in front: paused")
        XCTAssertEqual(probe.audio, [true], "The user's mute is delivered once and never lifted by the pause")

        activate("com.apple.finder")
        XCTAssertEqual(probe.presentations, [.suspended, .running], "Clicking the desktop plays again")
        activate("com.example.Editor")
        XCTAssertEqual(probe.presentations, [.suspended, .running, .suspended])

        onBattery = false
        monitor.refresh()
        XCTAssertEqual(probe.presentations, [.suspended, .running, .suspended, .running],
                       "Plugging in plays again without the desktop in front")
        XCTAssertEqual(probe.audio, [true], "Pausing and playing never touched the sound")
        XCTAssertEqual(policy.globalPresentation, .running)
    }

    func testHeatThrottlesAtSeriousAndEscalatesToAPauseAtCritical() throws {
        let defaults = try TemporaryDefaults.make(for: self).defaults
        let preferences = PlaybackPreferences(defaults: defaults)
        preferences.thermalAction = .reduceQuality
        var thermal = ProcessInfo.ThermalState.nominal
        let systemCenter = NotificationCenter()
        let monitor = SystemConditionMonitor(
            preferences: preferences, focus: FocusFilterState(defaults: defaults),
            systemCenter: systemCenter, isLowPowerModeEnabled: { false }, thermalState: { thermal },
            battery: NoBattery())
        let probe = CompositionProbe()
        let policy = makePolicy(probe, conditions: monitor)
        monitor.onChange = { policy.evaluate() }
        monitor.start()
        policy.start()
        defer {
            monitor.onChange = nil
            monitor.stop()
            policy.stop()
        }
        func announce(_ state: ProcessInfo.ThermalState) {
            thermal = state
            systemCenter.post(name: ProcessInfo.thermalStateDidChangeNotification, object: nil)
        }

        announce(.fair)
        XCTAssertTrue(probe.quality.isEmpty, "Fair heat asks for nothing")

        announce(.serious)
        XCTAssertEqual(probe.quality, [[.heat]])
        XCTAssertTrue(probe.presentations.isEmpty, "Serious heat reduces and keeps presenting")
        XCTAssertFalse(policy.isSuspended)

        announce(.critical)
        XCTAssertEqual(probe.presentations, [.suspended], "Critical heat is past what reducing can do")
        XCTAssertEqual(probe.quality.count, 1, "The reduction is already in force and is not sent again")

        announce(.serious)
        XCTAssertEqual(probe.presentations, [.suspended, .running], "Cooling to serious presents again")
        XCTAssertEqual(probe.quality.count, 1, "Cooling to serious does not release the reduction")

        announce(.nominal)
        XCTAssertEqual(probe.quality, [[.heat], []])
        XCTAssertEqual(probe.presentations, [.suspended, .running])
    }

    // MARK: An inactive Mac

    /// The inactivity rule pauses every display the way an app rule does, beside a display that is
    /// paused on its own because it is covered, and gives each display back to its own visibility
    /// at the next input. Stop goes through the unload that frees memory.
    func testInactivitySuspendsEveryDisplayAndACoveredOneKeepsItsOwnPause() throws {
        let defaults = try TemporaryDefaults.make(for: self).defaults
        let preferences = PlaybackPreferences(defaults: defaults)
        preferences.inactivityAction = .pause
        let input = ManualInactivityInput()
        let monitor = SystemConditionMonitor(
            preferences: preferences, focus: FocusFilterState(defaults: defaults),
            systemCenter: NotificationCenter(), isLowPowerModeEnabled: { false },
            thermalState: { .nominal }, battery: NoBattery(), inactivity: input.makeMonitor())
        var presentations: [GlobalPresentation] = []
        let policy = WallpaperPresentationPolicy(
            workspaceCenter: workspaceCenter, lockCenter: lockCenter, windowCenter: windowCenter,
            surfaces: {
                [WallpaperSurfaceVisibility(displayID: 1, isVisible: true),
                 WallpaperSurfaceVisibility(displayID: 2, isVisible: false)]
            },
            sessionState: { .init(locked: false) },
            appRuleActions: { monitor.actions },
            occlusionSettleDelay: .zero,
            applyGlobal: { presentation, completion in
                presentations.append(presentation)
                completion(.success(()))
            },
            applyDisplay: { _, _, completion in completion(.success(())) })
        monitor.onChange = { policy.evaluate() }
        monitor.start()
        policy.start()
        defer {
            monitor.onChange = nil
            monitor.stop()
            policy.stop()
        }
        XCTAssertEqual(policy.suspendedDisplayIDs, [2], "The covered display pauses on its own")
        XCTAssertTrue(presentations.isEmpty)

        input.secondsSinceInput = 600
        input.fireTimer()
        XCTAssertEqual(presentations, [.suspended], "Ten minutes without input pause every display")
        XCTAssertEqual(policy.suspendedDisplayIDs, [2])
        XCTAssertFalse(policy.isUnattended, "Only sleeping displays or a lock count as nobody at the Mac")

        input.movePointer()
        XCTAssertEqual(presentations, [.suspended, .running])
        XCTAssertEqual(policy.suspendedDisplayIDs, [2], "The covered display is still paused")

        preferences.inactivityAction = .stop
        input.secondsSinceInput = 600
        input.fireTimer()
        XCTAssertEqual(presentations.last, .unloaded)
    }
}
