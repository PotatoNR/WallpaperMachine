import Darwin
import Foundation

@MainActor
final class SystemWallpaperStore {
    static let shared = SystemWallpaperStore()

    struct AgentIdentity: Equatable {
        var pid: pid_t
        var userID: uid_t
        var realUserID: uid_t
        var executable: String
        var startSeconds: UInt64
        var startMicroseconds: UInt64

        var startedAt: TimeInterval {
            TimeInterval(startSeconds) + TimeInterval(startMicroseconds) / 1_000_000
        }
    }

    private struct Change {
        var path: [String]
        var before: Any?
        var after: Any?
    }

    private struct Waiter {
        var id: UUID
        var continuation: CheckedContinuation<Void, Error>
    }

    private struct Restart {
        var old: [AgentIdentity]
        var signalled: [AgentIdentity] = []
        var threshold: TimeInterval
    }

    static let agentExecutable = "/System/Library/CoreServices/WallpaperAgent.app/Contents/MacOS/WallpaperAgent"

    private let storeURL: URL
    private let agents: @MainActor () throws -> [AgentIdentity]
    private let signal: @MainActor (AgentIdentity) throws -> Void
    private let isRunning: @MainActor (AgentIdentity) -> Bool
    private let now: @MainActor () -> TimeInterval
    private let wait: @MainActor (TimeInterval) async throws -> Void
    private let userID: uid_t
    private let timeout: TimeInterval
    private let pollInterval: TimeInterval
    private let maximumReloads: Int
    private var occupied = false
    private var waiters: [Waiter] = []
    private var changes: [Change] = []
    private var invalidated = false
    private var writtenAt: TimeInterval?
    private var restart: Restart?
    private var requiresRestart = false
    private var turnoverAcknowledged = false

    init(
        storeURL: URL = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(
            "Library/Application Support/com.apple.wallpaper/Store/Index.plist"),
        agents: @escaping @MainActor () throws -> [AgentIdentity] = SystemWallpaperStore.runningAgents,
        signal: @escaping @MainActor (AgentIdentity) throws -> Void = SystemWallpaperStore.signalAgent,
        isRunning: @escaping @MainActor (AgentIdentity) -> Bool = SystemWallpaperStore.isAgentRunning,
        now: @escaping @MainActor () -> TimeInterval = { Date().timeIntervalSince1970 },
        wait: @escaping @MainActor (TimeInterval) async throws -> Void = {
            try await Task.sleep(nanoseconds: UInt64($0 * 1_000_000_000))
        },
        userID: uid_t = getuid(),
        timeout: TimeInterval = 5,
        pollInterval: TimeInterval = 0.1,
        maximumReloads: Int = 3
    ) {
        self.storeURL = storeURL
        self.agents = agents
        self.signal = signal
        self.isRunning = isRunning
        self.now = now
        self.wait = wait
        self.userID = userID
        self.timeout = max(0.01, timeout)
        self.pollInterval = max(0.01, pollInterval)
        self.maximumReloads = max(1, maximumReloads)
    }

    func transaction<T>(_ operation: @MainActor () async throws -> T) async throws -> T {
        try Task.checkCancellation()
        if occupied {
            let id = UUID()
            try await withTaskCancellationHandler {
                try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                    waiters.append(Waiter(id: id, continuation: continuation))
                }
            } onCancel: {
                Task { @MainActor in self.cancelWaiter(id) }
            }
        } else {
            occupied = true
        }
        defer {
            if changes.isEmpty { turnoverAcknowledged = false }
            release()
        }
        try Task.checkCancellation()
        if requiresRestart || !changes.isEmpty {
            let deadline = now() + timeout
            var pollsRemaining = max(1, Int(ceil(timeout / pollInterval)))
            if !turnoverAcknowledged {
                try await finishRestart(deadline: deadline, pollsRemaining: &pollsRemaining)
            }
            if !invalidated {
                try await reload(deadline: deadline, pollsRemaining: &pollsRemaining)
                turnoverAcknowledged = true
            }
        }
        if invalidated {
            invalidated = false
            writtenAt = nil
        }
        try Task.checkCancellation()
        return try await operation()
    }

    func read() throws -> Data {
        let data = try Data(contentsOf: storeURL)
        if !changes.isEmpty {
            let root = try Self.decode(data)
            if changes.contains(where: { change in
                let value = Self.value(root, path: change.path)
                return !Self.equal(value, change.before) && !Self.equal(value, change.after)
            }) {
                changes = []
                invalidated = true
            }
        }
        return data
    }

    func replace(_ data: Data, expected: Data) throws {
        try Task.checkCancellation()
        guard try Data(contentsOf: storeURL) == expected else {
            changes = []
            invalidated = true
            throw Self.conflict()
        }
        let before = try Self.decode(expected)
        let after = try Self.decode(data)
        let next = Self.differences(before: before, after: after)
        guard !next.isEmpty else { return }
        try data.write(to: storeURL, options: .atomic)
        writtenAt = now()
        requiresRestart = true
        turnoverAcknowledged = false
        changes.removeAll { existing in
            next.contains { change in
                existing.path.starts(with: change.path) || change.path.starts(with: existing.path)
            }
        }
        changes += next
        invalidated = false
    }

    func reload() async throws {
        var pollsRemaining = max(1, Int(ceil(timeout / pollInterval)))
        try await reload(deadline: now() + timeout, pollsRemaining: &pollsRemaining)
    }

    private func reload(deadline: TimeInterval, pollsRemaining: inout Int) async throws {
        try Task.checkCancellation()
        guard !invalidated else { throw Self.conflict() }
        for attempt in 0..<maximumReloads {
            try Task.checkCancellation()
            if !turnoverAcknowledged {
                try await finishRestart(deadline: deadline, pollsRemaining: &pollsRemaining)
            }
            try Task.checkCancellation()
            let data = try read()
            guard !invalidated else { throw Self.conflict() }
            var root = try Self.decode(data)
            let stale = changes.filter { !Self.equal(Self.value(root, path: $0.path), $0.after) }
            if stale.isEmpty {
                changes = []
                writtenAt = nil
                turnoverAcknowledged = false
                return
            }
            guard attempt + 1 < maximumReloads, pollsRemaining > 0, now() < deadline else {
                throw Self.unconfirmed()
            }
            for change in stale {
                guard Self.equal(Self.value(root, path: change.path), change.before),
                      Self.canSet(root, path: change.path) else {
                    changes = []
                    invalidated = true
                    throw Self.conflict()
                }
                Self.set(&root, path: change.path, value: change.after)
            }
            guard try Data(contentsOf: storeURL) == data else { throw Self.conflict() }
            try Task.checkCancellation()
            let reconciled = try PropertyListSerialization.data(fromPropertyList: root, format: .binary, options: 0)
            try reconciled.write(to: storeURL, options: .atomic)
            writtenAt = now()
            requiresRestart = true
            turnoverAcknowledged = false
        }
        throw Self.unconfirmed()
    }

    private func finishRestart(deadline: TimeInterval, pollsRemaining: inout Int) async throws {
        if restart == nil {
            restart = Restart(old: try verifiedAgents(), threshold: writtenAt ?? now())
        }
        requiresRestart = true
        guard let pending = restart else { throw Self.unconfirmed() }
        for identity in pending.old where !pending.signalled.contains(identity) {
            try Task.checkCancellation()
            if try verifiedAgents().contains(identity) { try signal(identity) }
            restart?.signalled.append(identity)
        }
        while pollsRemaining > 0, now() <= deadline {
            try Task.checkCancellation()
            let current = try verifiedAgents()
            if !pending.old.contains(where: isRunning),
               current.contains(where: { $0.startedAt >= pending.threshold && !pending.old.contains($0) }) {
                restart = nil
                requiresRestart = false
                turnoverAcknowledged = true
                return
            }
            pollsRemaining -= 1
            try await wait(min(pollInterval, max(0, deadline - now())))
        }
        throw Self.unconfirmed()
    }

    private func cancelWaiter(_ id: UUID) {
        guard let index = waiters.firstIndex(where: { $0.id == id }) else { return }
        waiters.remove(at: index).continuation.resume(throwing: CancellationError())
    }

    private func release() {
        if waiters.isEmpty {
            occupied = false
        } else {
            waiters.removeFirst().continuation.resume()
        }
    }

    private func verifiedAgents() throws -> [AgentIdentity] {
        try agents().filter {
            $0.pid > 0 && $0.userID == userID && $0.realUserID == userID
                && $0.executable == Self.agentExecutable
        }
    }

    private static func decode(_ data: Data) throws -> [String: Any] {
        guard let root = try PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any] else {
            throw LockScreenWallpaperFailure(message: String(localized:
                "This macOS wallpaper store format is unsupported. Native selection was not changed."))
        }
        return root
    }

    private static func equal(_ lhs: Any?, _ rhs: Any?) -> Bool {
        switch (lhs, rhs) {
        case (nil, nil): return true
        case let (lhs as NSObject, rhs as NSObject): return lhs == rhs
        default: return false
        }
    }

    private static func differences(before: [String: Any], after: [String: Any], path: [String] = []) -> [Change] {
        Set(before.keys).union(after.keys).sorted().flatMap { key -> [Change] in
            let old = before[key]
            let new = after[key]
            guard !equal(old, new) else { return [] }
            if !["Desktop", "Idle", "Linked"].contains(key),
               (old == nil || old is [String: Any]), (new == nil || new is [String: Any]),
               !(old as? [String: Any] ?? [:]).isEmpty || !(new as? [String: Any] ?? [:]).isEmpty {
                return differences(before: old as? [String: Any] ?? [:],
                                   after: new as? [String: Any] ?? [:], path: path + [key])
            }
            return [Change(path: path + [key], before: old, after: new)]
        }
    }

    private static func value(_ root: [String: Any], path: [String]) -> Any? {
        guard let key = path.first else { return root }
        if path.count == 1 { return root[key] }
        guard let child = root[key] as? [String: Any] else { return nil }
        return value(child, path: Array(path.dropFirst()))
    }

    private static func canSet(_ root: [String: Any], path: [String]) -> Bool {
        guard let key = path.first, path.count > 1 else { return true }
        guard let child = root[key] else { return true }
        guard let node = child as? [String: Any] else { return false }
        return canSet(node, path: Array(path.dropFirst()))
    }

    private static func set(_ root: inout [String: Any], path: [String], value: Any?) {
        guard let key = path.first else { return }
        guard path.count > 1 else {
            root[key] = value
            return
        }
        var child = root[key] as? [String: Any] ?? [:]
        set(&child, path: Array(path.dropFirst()), value: value)
        root[key] = child.isEmpty ? nil : child
    }

    private static func conflict() -> LockScreenWallpaperFailure {
        LockScreenWallpaperFailure(message: String(localized:
            "The system wallpaper changed during native selection. Please retry; no concurrent changes were overwritten."),
            reason: .transient)
    }

    private static func unconfirmed() -> LockScreenWallpaperFailure {
        LockScreenWallpaperFailure(message: String(localized:
            "No positively verified user-owned WallpaperAgent is running. Native selection could not be activated; its restoration journal was retained."),
            reason: .transient)
    }

    static func runningAgents() throws -> [AgentIdentity] {
        let capacity = proc_listallpids(nil, 0)
        guard capacity > 0 else { throw unconfirmed() }
        var pids = [pid_t](repeating: 0, count: Int(capacity) + 32)
        let count = pids.withUnsafeMutableBytes { proc_listallpids($0.baseAddress, Int32($0.count)) }
        guard count > 0, Int(count) <= pids.count else { throw unconfirmed() }
        return pids.prefix(Int(count)).compactMap(identity)
    }

    private static func identity(_ pid: pid_t) -> AgentIdentity? {
        guard pid > 0 else { return nil }
        var info = proc_bsdinfo()
        let size = Int32(MemoryLayout<proc_bsdinfo>.size)
        guard proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, &info, size) == size,
              info.pbi_uid == getuid(), info.pbi_ruid == getuid() else { return nil }
        var path = [CChar](repeating: 0, count: 4 * Int(MAXPATHLEN))
        let length = path.withUnsafeMutableBytes { proc_pidpath(pid, $0.baseAddress, UInt32($0.count)) }
        guard length > 0, String(cString: path) == agentExecutable else { return nil }
        return AgentIdentity(pid: pid, userID: info.pbi_uid, realUserID: info.pbi_ruid,
                             executable: agentExecutable, startSeconds: info.pbi_start_tvsec,
                             startMicroseconds: info.pbi_start_tvusec)
    }

    static func signalAgent(_ expected: AgentIdentity) throws {
        guard identity(expected.pid) == expected else { return }
        guard kill(expected.pid, SIGTERM) == 0 || errno == ESRCH else {
            throw LockScreenWallpaperFailure(message: String(localized:
                "macOS refused to reload the user-owned wallpaper service (errno \(errno)). The restoration journal was retained."))
        }
    }

    static func isAgentRunning(_ expected: AgentIdentity) -> Bool {
        var info = proc_bsdinfo()
        let size = Int32(MemoryLayout<proc_bsdinfo>.size)
        if proc_pidinfo(expected.pid, PROC_PIDTBSDINFO, 0, &info, size) == size {
            return info.pbi_start_tvsec == expected.startSeconds
                && info.pbi_start_tvusec == expected.startMicroseconds
        }
        return !(kill(expected.pid, 0) == -1 && errno == ESRCH)
    }
}
