import XCTest
@testable import WallpaperMachine

@MainActor
final class SystemWallpaperStoreTests: XCTestCase {
    func testTransactionsRemainFIFOAcrossSuspension() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let store = fixture.store()
        let gate = Gate()
        var events: [String] = []
        var secondSubmitted = false
        var thirdSubmitted = false
        let first = Task {
            try await store.transaction {
                events.append("first")
                await gate.wait()
                events.append("first done")
            }
        }
        await until { events == ["first"] }
        let second = Task {
            secondSubmitted = true
            try await store.transaction { events.append("second") }
        }
        await until { secondSubmitted }
        let third = Task {
            thirdSubmitted = true
            try await store.transaction { events.append("third") }
        }
        await until { thirdSubmitted }
        XCTAssertEqual(events, ["first"])
        gate.open()
        try await first.value
        try await second.value
        try await third.value
        XCTAssertEqual(events, ["first", "first done", "second", "third"])
    }

    func testCancelledQueuedCallerDoesNotExecuteOrWaitForTheHolder() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let store = fixture.store()
        let gate = Gate()
        var holding = false
        var submitted = false
        var executed = false
        let holder = Task { try await store.transaction { holding = true; await gate.wait() } }
        await until { holding }
        let cancelled = Task {
            submitted = true
            try await store.transaction { executed = true }
        }
        await until { submitted }
        cancelled.cancel()
        do { try await cancelled.value; XCTFail("Cancellation must be reported") }
        catch is CancellationError {} catch { XCTFail("Unexpected error: \(error)") }
        XCTAssertFalse(executed)
        gate.open()
        try await holder.value
        let value = try await store.transaction { 42 }
        XCTAssertEqual(value, 42)
    }

    func testFailureReleasesTheQueue() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let store = fixture.store()
        let gate = Gate()
        var holding = false
        var submitted = false
        var executed = false
        let holder = Task {
            try await store.transaction { holding = true; await gate.wait(); throw TestFailure.expected }
        }
        await until { holding }
        let next = Task { submitted = true; try await store.transaction { executed = true } }
        await until { submitted }
        XCTAssertFalse(executed)
        gate.open()
        do { try await holder.value; XCTFail("Expected failure") } catch TestFailure.expected {}
        try await next.value
        XCTAssertTrue(executed)
    }

    func testCancellingTheHolderDoesNotReleaseItsSuspendedBody() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let store = fixture.store()
        let gate = Gate()
        var holding = false
        var submitted = false
        var executed = false
        let holder = Task { try await store.transaction { holding = true; await gate.wait() } }
        await until { holding }
        holder.cancel()
        let next = Task { submitted = true; try await store.transaction { executed = true } }
        await until { submitted }
        XCTAssertFalse(executed)
        gate.open()
        try await holder.value
        try await next.value
        XCTAssertTrue(executed)
    }

    func testReloadWaitsForDelayedExitAndDelayedStart() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let store = fixture.store()
        fixture.onWait = { state in
            if state.waits == 2 { state.processes = [] }
            if state.waits == 4 { state.startReplacement() }
        }
        try await store.transaction {
            try fixture.replaceDesktop(in: store)
            try await store.reload()
        }
        XCTAssertEqual(fixture.waits, 4)
        XCTAssertEqual(fixture.signals.map(\.pid), [10])
        XCTAssertEqual(try fixture.desktop(), "new")
    }

    func testPIDReuseRequiresANewVerifiedIdentity() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let store = fixture.store()
        fixture.onWait = { state in
            var replacement = state.identity(pid: 10)
            if state.waits < 3 { replacement.executable = "/unrelated/process" }
            state.processes = [replacement]
        }
        try fixture.replaceDesktop(in: store)
        try await store.reload()
        XCTAssertEqual(fixture.waits, 3)
        XCTAssertEqual(fixture.signals.count, 1)
    }

    func testIdentityReplacedBeforeSignalIsNeverSignalled() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let store = fixture.store()
        fixture.onAgents = { state in
            if state.reads == 2 {
                var reused = state.identity(pid: 10)
                reused.realUserID = 999
                state.processes = [reused]
            }
            return state.processes
        }
        fixture.onWait = { $0.startReplacement() }
        try fixture.replaceDesktop(in: store)
        try await store.reload()
        XCTAssertTrue(fixture.signals.isEmpty)
    }

    func testWrongUIDRealUIDOrExecutableIsNeverSignalledOrAccepted() async throws {
        for field in 0..<3 {
            let fixture = try Fixture()
            defer { fixture.remove() }
            var foreign = fixture.identity(pid: 11)
            if field == 0 { foreign.userID = 999 }
            if field == 1 { foreign.realUserID = 999 }
            if field == 2 { foreign.executable = "/unrelated/process" }
            fixture.processes = [foreign]
            fixture.onWait = { _ in }
            let store = fixture.store(timeout: 0.3)
            try fixture.replaceDesktop(in: store)
            do { try await store.reload(); XCTFail("Unverified agents cannot acknowledge a write") } catch {}
            XCTAssertTrue(fixture.signals.isEmpty)
            XCTAssertLessThanOrEqual(fixture.waits, 3)
        }
    }

    func testTurnoverStartedBeforeTheWriteDoesNotAcknowledgeIt() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let store = fixture.store(timeout: 0.3)
        fixture.onWait = { state in
            var replacement = state.identity(pid: 11)
            replacement.startSeconds = 900
            replacement.startMicroseconds = 0
            state.processes = [replacement]
        }
        try fixture.replaceDesktop(in: store)
        do { try await store.reload(); XCTFail("A replacement must have started after the write") } catch {}
        XCTAssertEqual(fixture.signals.count, 1)
    }

    func testStaleSaveReplaysOnlyOwnedChangesAndPreservesUnrelatedEdits() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let store = fixture.store()
        fixture.onWait = { state in
            if state.waits == 1 {
                try state.write(["Display": ["Desktop": "old", "Idle": "external saver"], "other": 99])
            }
            state.startReplacement()
        }
        try fixture.replaceDesktop(in: store)
        try await store.reload()
        let root = try fixture.root()
        XCTAssertEqual((root["Display"] as? [String: Any])?["Desktop"] as? String, "new")
        XCTAssertEqual((root["Display"] as? [String: Any])?["Idle"] as? String, "external saver")
        XCTAssertEqual(root["other"] as? Int, 99)
        XCTAssertEqual(fixture.signals.count, 2)
    }

    func testForeignChoiceIsPreservedAndItsStalePlanCannotBeRetried() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let store = fixture.store()
        fixture.onWait = { state in
            try state.write(["Display": ["Desktop": "foreign", "Idle": "saver"], "other": 1])
            state.startReplacement()
        }
        try fixture.replaceDesktop(in: store)
        do { try await store.reload(); XCTFail("Foreign choice must not be acknowledged") } catch {}
        fixture.onWait = nil
        do { try await store.reload(); XCTFail("An invalidated plan must not be retried") } catch {}
        XCTAssertEqual(try fixture.desktop(), "foreign")
        XCTAssertEqual(fixture.signals.count, 1)
    }

    func testOnlyChangedFieldsAreVerified() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let store = fixture.store()
        fixture.onWait = { state in
            try state.write(["Display": ["Desktop": "new", "Idle": "external saver"], "new metadata": true])
            state.startReplacement()
        }
        try fixture.replaceDesktop(in: store)
        try await store.reload()
        XCTAssertEqual((try fixture.root()["Display"] as? [String: Any])?["Idle"] as? String, "external saver")
        XCTAssertEqual(fixture.signals.count, 1)
    }

    func testReadMismatchInvalidatesOldIntentWithoutOverwritingNewChoice() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let store = fixture.store()
        try fixture.replaceDesktop(in: store)
        try fixture.write(["Display": ["Desktop": "foreign", "Idle": "saver"]])
        _ = try store.read()
        do { try await store.reload(); XCTFail("Reading a foreign choice invalidates pending intent") } catch {}
        XCTAssertEqual(try fixture.desktop(), "foreign")
        XCTAssertTrue(fixture.signals.isEmpty)
    }

    func testCompareFailureDoesNotOverwriteConcurrentChanges() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let store = fixture.store()
        let expected = try store.read()
        try fixture.write(["Display": ["Desktop": "foreign"]])
        XCTAssertThrowsError(try store.replace(Fixture.encode(["Display": ["Desktop": "new"]]), expected: expected))
        XCTAssertEqual(try fixture.desktop(), "foreign")
    }

    func testTimeoutRetainsIntentAndJournalUntilRetrySucceeds() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let store = fixture.store(timeout: 0.3)
        let journal = fixture.folder.appendingPathComponent("journal")
        try Data([1]).write(to: journal)
        fixture.onWait = { _ in }
        do {
            try await store.transaction {
                try fixture.replaceDesktop(in: store)
                try await store.reload()
                try FileManager.default.removeItem(at: journal)
            }
            XCTFail("Reload must time out")
        } catch {}
        XCTAssertTrue(FileManager.default.fileExists(atPath: journal.path))
        XCTAssertEqual(fixture.signals.count, 1)
        fixture.onWait = { state in
            if state.signals.count == 1 {
                try state.write(["Display": ["Desktop": "old", "Idle": "external saver"], "other": 8])
            }
            state.startReplacement()
        }
        try await store.transaction {
            try await store.reload()
            try FileManager.default.removeItem(at: journal)
        }
        XCTAssertFalse(FileManager.default.fileExists(atPath: journal.path))
        XCTAssertEqual(try fixture.desktop(), "new")
        XCTAssertEqual(try fixture.root()["other"] as? Int, 8)
    }

    func testQueuedWriterCannotEnterDuringTimedOutRestart() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let store = fixture.store(timeout: 0.3)
        fixture.onWait = { _ in }
        try fixture.replaceDesktop(in: store)
        do { try await store.reload(); XCTFail("Expected timeout") } catch {}
        var entered = false
        do {
            try await store.transaction { entered = true }
            XCTFail("The next writer must not enter while the old agent lives")
        } catch {}
        XCTAssertFalse(entered)
        XCTAssertEqual(fixture.signals.count, 1)
        fixture.onWait = { $0.startReplacement() }
        try await store.transaction { entered = true }
        XCTAssertTrue(entered)
    }

    func testQueuedWriterWaitsForCancelledRestartBeforeEntering() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let store = fixture.store()
        let gate = Gate()
        var waiting = false
        var submitted = false
        var entered = false
        fixture.onWait = { _ in waiting = true; await gate.wait() }
        let first = Task {
            try await store.transaction {
                try fixture.replaceDesktop(in: store)
                try await store.reload()
            }
        }
        await until { waiting }
        let next = Task {
            submitted = true
            try await store.transaction { entered = true }
        }
        await until { submitted }
        first.cancel()
        XCTAssertFalse(entered)
        fixture.onWait = { state in
            XCTAssertFalse(entered)
            state.startReplacement()
        }
        gate.open()
        do { try await first.value; XCTFail("Cancellation must be reported") }
        catch is CancellationError {} catch { XCTFail("Unexpected error: \(error)") }
        try await next.value
        XCTAssertTrue(entered)
        XCTAssertEqual(fixture.signals.count, 1)
    }

    func testRepeatedStaleSavesAreBoundedAndDoNotReportSuccess() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let store = fixture.store(maximumReloads: 2)
        fixture.onWait = { state in
            try state.write(["Display": ["Desktop": "old", "Idle": "saver"], "other": state.waits])
            state.startReplacement()
        }
        try fixture.replaceDesktop(in: store)
        do { try await store.reload(); XCTFail("PID turnover is not store acknowledgement") } catch {}
        XCTAssertEqual(fixture.signals.count, 2)
        XCTAssertEqual(try fixture.desktop(), "old")
        fixture.onWait = nil
        try await store.reload()
        XCTAssertEqual(try fixture.desktop(), "new")
    }

    func testRecoveryWithoutAWriteStillRestartsTheAgent() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let store = fixture.store()
        try await store.transaction { try await store.reload() }
        XCTAssertEqual(fixture.signals.count, 1)
        XCTAssertEqual(try fixture.desktop(), "old")
    }

    func testAdmissionAcknowledgementIsNotRestartedAgainByReload() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let store = fixture.store(timeout: 0.3)
        fixture.onWait = { _ in }
        try fixture.replaceDesktop(in: store)
        do { try await store.reload(); XCTFail("Expected timeout") } catch {}
        fixture.onWait = nil
        try await store.transaction { try await store.reload() }
        XCTAssertEqual(fixture.signals.count, 1)
        XCTAssertEqual(try fixture.desktop(), "new")
    }

    func testChangedWallpaperChoicesAreAtomicAndNeverBecomeHybrids() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let original: [String: Any] = ["Content": ["Choices": ["original"]], "Options": ["color": "blue"]]
        let intended: [String: Any] = ["Content": ["Choices": ["intended"]], "Options": ["color": "blue"]]
        let foreign: [String: Any] = ["Content": ["Choices": ["original"]], "Options": ["color": "red"]]
        try fixture.write(["Display": ["Desktop": original, "Idle": "saver"]])
        let store = fixture.store()
        let expected = try store.read()
        try store.replace(Fixture.encode(["Display": ["Desktop": intended, "Idle": "saver"]]), expected: expected)
        fixture.onWait = { state in
            try state.write(["Display": ["Desktop": foreign, "Idle": "saver"]])
            state.startReplacement()
        }
        do { try await store.reload(); XCTFail("A changed choice must be preserved as a unit") } catch {}
        let actual = try XCTUnwrap((fixture.root()["Display"] as? [String: Any])?["Desktop"] as? [String: Any])
        XCTAssertTrue(NSDictionary(dictionary: actual).isEqual(to: foreign))
        XCTAssertEqual(fixture.signals.count, 1)
    }

    func testClockMovingBackwardCannotMakeReloadWaitForever() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let store = fixture.store(timeout: 0.3)
        fixture.onWait = { $0.time -= 1 }
        try fixture.replaceDesktop(in: store)
        do { try await store.reload(); XCTFail("The poll budget must eventually expire") } catch {}
        XCTAssertLessThanOrEqual(fixture.waits, 3)
    }

    func testMissingEnumerationDoesNotProveTheOldProcessExited() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let store = fixture.store(timeout: 0.3)
        fixture.onAgents = { state in
            state.reads < 3 ? state.processes : state.processes.filter { $0.pid != 10 }
        }
        fixture.onWait = { state in
            state.processes = [state.processes[0], state.identity(pid: 11)]
        }
        try fixture.replaceDesktop(in: store)
        do { try await store.reload(); XCTFail("A hidden but living old process still blocks acknowledgement") } catch {}
        XCTAssertEqual(fixture.signals.count, 1)
        XCTAssertEqual(fixture.processes.first?.pid, 10)
    }

    func testCancellationAfterWriteStillConfirmsIntentBeforeTheNextWriter() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let store = fixture.store()
        let gate = Gate()
        var written = false
        var entered = false
        let cancelled = Task {
            try await store.transaction {
                try fixture.replaceDesktop(in: store)
                written = true
                await gate.wait()
                try Task.checkCancellation()
                try await store.reload()
            }
        }
        await until { written }
        cancelled.cancel()
        fixture.onWait = { state in
            XCTAssertFalse(entered)
            if state.waits == 1 {
                try state.write(["Display": ["Desktop": "old", "Idle": "external saver"], "other": 4])
            }
            state.startReplacement()
        }
        let next = Task {
            try await store.transaction {
                XCTAssertEqual(try fixture.desktop(), "new")
                entered = true
                try await store.reload()
            }
        }
        gate.open()
        do { try await cancelled.value; XCTFail("Cancellation must be reported") }
        catch is CancellationError {} catch { XCTFail("Unexpected error: \(error)") }
        try await next.value
        XCTAssertTrue(entered)
        XCTAssertEqual(fixture.signals.count, 2)
    }

    func testFreshTransactionCanPreserveForeignChoiceWithoutRevivingInvalidatedIntent() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let store = fixture.store()
        fixture.onWait = { state in
            try state.write(["Display": ["Desktop": "foreign", "Idle": "saver"], "other": 7])
            state.startReplacement()
        }
        do {
            try await store.transaction {
                try fixture.replaceDesktop(in: store)
                try await store.reload()
            }
            XCTFail("The foreign choice invalidates this transaction's intent")
        } catch {}
        let foreign = try Data(contentsOf: fixture.storeURL)
        fixture.onWait = nil
        try await store.transaction {
            XCTAssertEqual(try store.read(), foreign)
            try await store.reload()
        }
        XCTAssertEqual(try Data(contentsOf: fixture.storeURL), foreign)
        XCTAssertEqual(try fixture.desktop(), "foreign")
    }

    private enum TestFailure: Error { case expected }

    private func until(_ condition: () -> Bool, file: StaticString = #filePath, line: UInt = #line) async {
        for _ in 0..<1_000 {
            if condition() { return }
            await Task.yield()
        }
        XCTFail("Condition never became true", file: file, line: line)
    }

    @MainActor
    private final class Gate {
        private var opened = false
        private var waiters: [CheckedContinuation<Void, Never>] = []

        func wait() async {
            guard !opened else { return }
            await withCheckedContinuation { waiters.append($0) }
        }

        func open() {
            opened = true
            let pending = waiters
            waiters = []
            pending.forEach { $0.resume() }
        }
    }

    @MainActor
    private final class Fixture {
        let folder: URL
        let storeURL: URL
        var time: TimeInterval = 1_000
        var waits = 0
        var reads = 0
        var processes: [SystemWallpaperStore.AgentIdentity] = []
        var signals: [SystemWallpaperStore.AgentIdentity] = []
        var onWait: ((Fixture) async throws -> Void)?
        var onAgents: ((Fixture) -> [SystemWallpaperStore.AgentIdentity])?

        init() throws {
            folder = FileManager.default.temporaryDirectory.appendingPathComponent("system-wallpaper-" + UUID().uuidString)
            storeURL = folder.appendingPathComponent("Index.plist")
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            processes = [identity(pid: 10)]
            processes[0].startSeconds = 900
            try write(["Display": ["Desktop": "old", "Idle": "saver"], "other": 1])
        }

        func remove() { try? FileManager.default.removeItem(at: folder) }

        func identity(pid: Int32) -> SystemWallpaperStore.AgentIdentity {
            SystemWallpaperStore.AgentIdentity(pid: pid, userID: 501, realUserID: 501,
                executable: SystemWallpaperStore.agentExecutable, startSeconds: UInt64(time),
                startMicroseconds: UInt64((time - floor(time)) * 1_000_000))
        }

        func startReplacement() { processes = [identity(pid: (signals.last?.pid ?? 10) + 1)] }

        func store(timeout: TimeInterval = 3, maximumReloads: Int = 3) -> SystemWallpaperStore {
            SystemWallpaperStore(storeURL: storeURL, agents: {
                self.reads += 1
                return self.onAgents?(self) ?? self.processes
            }, signal: { self.signals.append($0) }, isRunning: { expected in
                self.processes.contains {
                    $0.pid == expected.pid && $0.startSeconds == expected.startSeconds
                        && $0.startMicroseconds == expected.startMicroseconds
                }
            }, now: { self.time }, wait: { interval in
                self.time += interval
                self.waits += 1
                if let onWait = self.onWait { try await onWait(self) }
                else { self.startReplacement() }
            }, userID: 501, timeout: timeout, pollInterval: 0.1, maximumReloads: maximumReloads)
        }

        func replaceDesktop(in store: SystemWallpaperStore) throws {
            let expected = try store.read()
            var root = try self.root()
            var display = root["Display"] as? [String: Any] ?? [:]
            display["Desktop"] = "new"
            root["Display"] = display
            try store.replace(Self.encode(root), expected: expected)
        }

        static func encode(_ root: [String: Any]) throws -> Data {
            try PropertyListSerialization.data(fromPropertyList: root, format: .binary, options: 0)
        }

        func write(_ root: [String: Any]) throws { try Self.encode(root).write(to: storeURL, options: .atomic) }

        func root() throws -> [String: Any] {
            try XCTUnwrap(PropertyListSerialization.propertyList(from: Data(contentsOf: storeURL), format: nil) as? [String: Any])
        }

        func desktop() throws -> String? { (try root()["Display"] as? [String: Any])?["Desktop"] as? String }
    }
}
