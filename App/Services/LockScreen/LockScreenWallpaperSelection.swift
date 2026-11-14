import AppKit
import Darwin

struct LockScreenWallpaperFailure: LocalizedError {
  /// `transient` is a failure a later attempt can get past on its own: a write that raced
  /// WallpaperAgent's own, or the agent between a restart and its relaunch.
  enum Reason { case general, differentExtensionCopy, extensionTurnedOff, transient }
  let message: String
  var reason: Reason = .general
  var errorDescription: String? { message }
}

/// Journals physical-display choices and temporarily removes global overrides
/// for the native presentation modes the app owns.
@MainActor
final class LockScreenWallpaperSelection {
  private struct Entry: Codable, Equatable {
    var path: [String]
    var original: Data
    var created: Bool
    var observeOnly: Bool? = nil
    // Absent in pre-independent journals, which owned both native choices.
    var fields: [String]? = nil
    var typeOwned: Bool? = nil
    // Preserve the native linked shape while Desktop and Idle are independent.
    var linkedOriginal: Data? = nil
    // A synthesized display needs both native fields even when we own only one.
    var inheritedOriginal: Data? = nil
    var globalWasPresent: Bool? = nil

    var ownedFields: Set<String> { Set(fields ?? ["Desktop", "Idle"]) }
  }

  /// A check that found nothing to change, and the store version it read.
  private struct Settled: Equatable {
    var desktopDisplays: Set<String>
    var screenSaverDisplays: Set<String>
    var revision: String?
    var store: [Int]
  }

  private static let globalPath = ["AllSpacesAndDisplays"]

  private let storeURL: URL
  private let journalURL: URL
  private let reload: @MainActor () async throws -> Void
  private let coordinator: SystemWallpaperStore?
  private let persistJournal: @MainActor (URL, Data?) throws -> Void
  private let persistArchive: @MainActor (URL, Data?) throws -> Void
  private var entries: [Entry] = []
  private var hasPersistedJournal = false
  private var readoptionNeedsPersistence = false
  private var restartPending = false
  private var settled: Settled?

  convenience init(folder: URL, coordinator: SystemWallpaperStore? = nil) {
    let coordinator = coordinator ?? .shared
    self.init(
      storeURL: FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(
        "Library/Application Support/com.apple.wallpaper/Store/Index.plist"),
      journalURL: folder.appendingPathComponent("native-selection.plist"),
      reload: { try await coordinator.reload() }, coordinator: coordinator)
  }

  init(
    storeURL: URL, journalURL: URL, reload: @escaping @MainActor () async throws -> Void,
    coordinator: SystemWallpaperStore? = nil,
    persistJournal: @escaping @MainActor (URL, Data?) throws -> Void =
      LockScreenWallpaperSelection.persistJournalFile,
    persistArchive: @escaping @MainActor (URL, Data?) throws -> Void =
      LockScreenWallpaperSelection.persistJournalFile
  ) {
    self.storeURL = storeURL
    self.journalURL = journalURL
    self.reload = reload
    self.coordinator = coordinator
    self.persistJournal = persistJournal
    self.persistArchive = persistArchive
  }

  func recover() async throws {
    if let coordinator {
      try await coordinator.transaction { try await self.recoverSelection() }
    } else {
      try await recoverSelection()
    }
  }

  private func recoverSelection() async throws {
    guard FileManager.default.fileExists(atPath: journalURL.path) else { return }
    let recovered = try PropertyListDecoder().decode([Entry].self, from: Data(contentsOf: journalURL))
    guard Set(recovered.map(\.path)).count == recovered.count else {
      throw LockScreenWallpaperFailure(
        message: String(localized: "The native wallpaper restoration journal is invalid."))
    }
    entries = recovered
    readoptionNeedsPersistence = false
    hasPersistedJournal = true
    // A crash may occur after the store write but before its service reload.
    restartPending = true
    try await synchronizeSelection(desktopDisplays: [], screenSaverDisplays: [])
  }

  func checkCompatibility() throws {
    let root =
      try PropertyListSerialization.propertyList(from: Data(contentsOf: storeURL), format: nil)
      as? [String: Any]
    if let global = root?["AllSpacesAndDisplays"] as? [String: Any],
      global["Type"] as? String == "linked", Self.defaultLinkedChoice(global) == nil
    {
      throw LockScreenWallpaperFailure(
        message:
          String(localized: "A system-wide linked wallpaper currently overrides individual displays. Turn off that wallpaper app or its all-displays setting before enabling native wallpaper animation; the existing global wallpaper was not changed.")
      )
    }
  }

  func synchronize(
    desktopDisplays: Set<String>, screenSaverDisplays: Set<String>, revision: String? = nil
  ) async throws {
    if let coordinator {
      try await coordinator.transaction {
        try await self.synchronizeSelection(
          desktopDisplays: desktopDisplays, screenSaverDisplays: screenSaverDisplays, revision: revision)
      }
    } else {
      try await synchronizeSelection(
        desktopDisplays: desktopDisplays, screenSaverDisplays: screenSaverDisplays, revision: revision)
    }
  }

  private func synchronizeSelection(
    desktopDisplays: Set<String>, screenSaverDisplays: Set<String>, revision: String? = nil
  ) async throws {
    try Task.checkCancellation()
    let displays = desktopDisplays.union(screenSaverDisplays)
    if displays.isEmpty && entries.isEmpty && !restartPending { return }
    // With the same request and journal, only the store can change the outcome, and
    // everything that matters rewrites it: a new Space, a choice made in System
    // Settings, a WallpaperAgent reload. Until then a settled check would repeat itself.
    let request = Self.storeVersion(storeURL).map {
      Settled(
        desktopDisplays: desktopDisplays, screenSaverDisplays: screenSaverDisplays,
        revision: revision, store: $0)
    }
    if !restartPending, let request, request == settled { return }
    settled = nil
    let priorEntries = entries
    let bytes = try Data(contentsOf: storeURL)
    guard
      var root = try PropertyListSerialization.propertyList(from: bytes, format: nil)
        as? [String: Any],
      root["Displays"] is [String: Any], root["Spaces"] is [String: Any]
    else {
      throw LockScreenWallpaperFailure(
        message:
          String(localized: "This macOS wallpaper store format is unsupported. Native selection was not changed."))
    }
    let sortedDisplays = displays.sorted()
    var paths = sortedDisplays.map { ["Displays", $0] }
    let spaces = root["Spaces"] as? [String: Any] ?? [:]
    // Stored back converted: each node lookup would otherwise convert every Space again.
    root["Spaces"] = spaces
    // Keep only paths still represented by this store or its live recovery journal.
    let livePaths = Set(entries.map(\.path))
    let archived = readArchivedEntries().filter {
      $0.path == Self.globalPath || livePaths.contains($0.path) || Self.node(root, path: $0.path) != nil
    }
    entries = try readoptedEntries(root, archived: archived)
    if entries != priorEntries { readoptionNeedsPersistence = true }
    let entryPaths = Set(entries.map(\.path))
    for (space, value) in spaces.sorted(by: { $0.key < $1.key }) {
      guard let node = value as? [String: Any], node["Displays"] is [String: Any] else {
        throw LockScreenWallpaperFailure(
          message: String(localized: "This macOS Space has an unsupported wallpaper configuration."))
      }
      paths += sortedDisplays.map { ["Spaces", space, "Displays", $0] }
    }
    let fallbackPaths = [["SystemDefault"]] + spaces.keys.sorted().map { ["Spaces", $0, "Default"] }
    let desiredPaths = Set(paths)
    let desiredFallbackPaths = Set(fallbackPaths)
    let activeFields = Set(
      (desktopDisplays.isEmpty ? [] : ["Desktop"])
        + (screenSaverDisplays.isEmpty ? [] : ["Idle"]))
    func desiredFields(_ path: [String], observeOnly: Bool) -> Set<String> {
      if observeOnly { return desiredFallbackPaths.contains(path) ? activeFields : [] }
      guard desiredPaths.contains(path), let display = path.last else { return [] }
      return Set(
        (desktopDisplays.contains(display) ? ["Desktop"] : [])
          + (screenSaverDisplays.contains(display) ? ["Idle"] : []))
    }
    var originals: [[String]: [String: Any]] = [:]
    for entry in entries {
      guard
        let original = try PropertyListSerialization.propertyList(from: entry.original, format: nil)
          as? [String: Any]
      else {
        throw LockScreenWallpaperFailure(
          message: String(localized: "The native wallpaper restoration journal is invalid."))
      }
      originals[entry.path] = entry.path == Self.globalPath ? original : original.filter {
        entry.ownedFields.contains($0.key) || ($0.key == "Type" && (entry.typeOwned ?? true))
      }
    }
    let journaledOriginal = { (path: [String]) in originals[path] }
    var recovery = entries
    var recoveryIndices = Dictionary(
      uniqueKeysWithValues: recovery.enumerated().map { ($0.element.path, $0.offset) })
    var retained: [Entry] = []
    var changed = false
    let selection = try Self.selection(revision: revision)
    // The pre-commit journal owns the union of old and new fields. A crash at
    // either side of the atomic store write can therefore restore all of them.
    func record(_ entry: Entry, original: [String: Any]) throws {
      if let index = recoveryIndices[entry.path] {
        var merged = originals[entry.path] ?? [:]
        if entry.path == Self.globalPath {
          merged = original
        } else {
          for key in entry.ownedFields.subtracting(recovery[index].ownedFields) {
            merged[key] = original[key]
          }
        }
        recovery[index].original =
          entry.path == Self.globalPath ? entry.original : try Self.encode(merged)
        recovery[index].fields = recovery[index].ownedFields.union(entry.ownedFields).sorted()
        originals[entry.path] = merged
      } else {
        recoveryIndices[entry.path] = recovery.count
        recovery.append(entry)
        originals[entry.path] = original
      }
    }
    func reconcile(_ prior: Entry?, path: [String], observeOnly: Bool) throws {
      let desired = desiredFields(path, observeOnly: observeOnly)
      let previous = prior?.ownedFields ?? []
      let existing = Self.node(root, path: path)
      if existing == nil && desired.isEmpty { return }
      if existing == nil, !observeOnly, !previous.intersection(desired).isEmpty {
        throw LockScreenWallpaperFailure(
          message:
            String(localized: "A native wallpaper override was removed outside WallpaperMachine. Disable the affected wallpaper feature before enabling it again."))
      }
      var node = existing ?? [:]
      var linkedOriginal: [String: Any]?
      if let data = prior?.linkedOriginal {
        guard let decoded = try PropertyListSerialization.propertyList(from: data, format: nil)
          as? [String: Any]
        else {
          throw LockScreenWallpaperFailure(
            message: String(localized: "The native wallpaper restoration journal is invalid."))
        }
        linkedOriginal = decoded
      }
      var inheritedOriginal: [String: Any]?
      if let data = prior?.inheritedOriginal {
        guard let decoded = try PropertyListSerialization.propertyList(from: data, format: nil)
          as? [String: Any]
        else {
          throw LockScreenWallpaperFailure(
            message: String(localized: "The native wallpaper restoration journal is invalid."))
        }
        inheritedOriginal = decoded
      }
      if prior == nil, !desired.isEmpty {
        if Self.defaultLinkedChoice(node) != nil {
          linkedOriginal = node
        } else if existing == nil, !observeOnly {
          // An `individual` native node requires Desktop AND Idle. Resolve the
          // inherited originals before installing either owned choice; a parent
          // display may already be ours, so consult its journal as well.
          let inherited = try Self.restorationOriginal(
            ["Type": "individual", "Desktop": selection, "Idle": selection],
            path: path, root: root, fields: ["Desktop", "Idle"], journaled: journaledOriginal)
          inheritedOriginal = inherited
          node = inherited
        }
      }
      if !observeOnly, !desired.isEmpty, let linkedOriginal,
        existing == nil || Self.defaultLinkedChoice(node) != nil
      {
        node = Self.separatedLinked(node.isEmpty ? linkedOriginal : node)
      }
      if !observeOnly && !desired.isEmpty && existing != nil
        && node["Type"] as? String != "individual"
      {
        throw LockScreenWallpaperFailure(
          message:
            String(localized: "This display uses a linked or unsupported native wallpaper configuration. Choose separate desktop and screen saver wallpapers in System Settings before enabling native wallpaper animation."))
      }
      var original = prior.flatMap { originals[$0.path] } ?? [:]
      let removed = previous.subtracting(desired)
      let allPreviouslyOwned = previous.allSatisfy { Self.owns(node[$0]) }
      for key in previous.sorted() {
        if desired.contains(key) {
          if !observeOnly && !Self.owns(node[key]) {
            throw LockScreenWallpaperFailure(
              message:
                String(localized: "The system wallpaper was changed outside WallpaperMachine. Disable the affected wallpaper feature before enabling it again; external choices will be preserved."))
          }
        } else if Self.owns(node[key]) {
          node[key] = original[key]
        }
      }
      let added = desired.subtracting(previous)
      if !added.isEmpty {
        let restored = try Self.restorationOriginal(
          Self.separatedLinked(node), path: path, root: root, fields: added,
          journaled: journaledOriginal)
        for key in added { original[key] = restored[key] }
      }
      let typeOwned = prior.map { $0.typeOwned ?? true }
        ?? (!observeOnly && existing == nil && linkedOriginal == nil && inheritedOriginal == nil)
      if prior == nil && typeOwned { original["Type"] = existing?["Type"] }
      if !observeOnly {
        for key in desired.sorted() {
          let current = node[key] as? [String: Any]
          let content = current?["Content"] as? [String: Any]
          let choices = content?["Choices"] as? [[String: Any]]
          let expected = (selection["Content"] as? [String: Any])?["Choices"] as? [[String: Any]]
          if added.contains(key)
            || (revision != nil
              && choices?.first?["Configuration"] as? Data
                != expected?.first?["Configuration"] as? Data)
          {
            node[key] = selection
          }
        }
        // Linked choices already have a separate Desktop/Idle shape above.
        if prior == nil && typeOwned { node["Type"] = "individual" }
      }
      if desired.isEmpty && !removed.isEmpty && typeOwned && allPreviouslyOwned
        && node["Type"] as? String == "individual"
        && ["Desktop", "Idle"].allSatisfy({
          (node[$0] as? NSDictionary) == (original[$0] as? NSDictionary)
        })
      {
        node["Type"] = original["Type"]
      }
      if desired.isEmpty, let linkedOriginal {
        let baseline = Self.separatedLinked(linkedOriginal)
        if prior?.created == true, (node as NSDictionary) == (baseline as NSDictionary) {
          node = [:]
        } else {
          node = Self.relinked(node, original: linkedOriginal)
        }
      }
      if desired.isEmpty, let inheritedOriginal, prior?.created == true,
        (node as NSDictionary) == (inheritedOriginal as NSDictionary)
      {
        node = [:]
      }
      if !desired.isEmpty {
        if !observeOnly, !(node["Desktop"] is [String: Any] && node["Idle"] is [String: Any]) {
          throw LockScreenWallpaperFailure(
            message: String(localized: "This macOS wallpaper store format is unsupported. Native selection was not changed."))
        }
        original = original.filter {
          desired.contains($0.key) || ($0.key == "Type" && typeOwned)
        }
        let originalData: Data
        if let prior, desired == previous {
          originalData = prior.original
        } else {
          originalData = try Self.encode(original)
        }
        // Both baselines are set only when a path is first taken over; keep the
        // journaled bytes, which re-encoding could reorder.
        let entry = Entry(
          path: path, original: originalData,
          created: prior?.created ?? (existing == nil), observeOnly: observeOnly,
          fields: desired.sorted(), typeOwned: typeOwned,
          linkedOriginal: try prior.map(\.linkedOriginal)
            ?? linkedOriginal.map { try Self.encode($0) },
          inheritedOriginal: try prior.map(\.inheritedOriginal)
            ?? inheritedOriginal.map { try Self.encode($0) })
        if !added.isEmpty { try record(entry, original: original) }
        retained.append(entry)
      }
      let value: [String: Any]? =
        node.isEmpty && ((prior?.created ?? false) || existing == nil) ? nil : node
      if (existing as NSDictionary?) != (value as NSDictionary?) {
        Self.setNode(&root, path: path, value: value)
        changed = true
      }
    }
    // Global choices take precedence over physical displays. Suppress only the
    // requested modes, keeping the original shape in the write-ahead journal.
    let globalEntry = entries.first { $0.path == Self.globalPath }
    let global = Self.node(root, path: Self.globalPath)
    if !activeFields.isEmpty || globalEntry != nil {
      let previous = globalEntry?.ownedFields ?? []
      var original = globalEntry.flatMap { originals[$0.path] } ?? global ?? [:]
      let wasPresent = globalEntry?.globalWasPresent
        ?? (globalEntry == nil ? global != nil : !original.isEmpty)
      var restored = Self.separatedLinked(global ?? [:])
      let supported = restored.isEmpty
        || ["desktop", "idle", "individual"].contains(restored["Type"] as? String ?? "")
      if !activeFields.isEmpty {
        guard supported,
          previous.intersection(activeFields).allSatisfy({ restored[$0] == nil })
        else {
          throw LockScreenWallpaperFailure(
            message: String(localized: "The system wallpaper was changed outside WallpaperMachine. Disable the affected wallpaper feature before enabling it again; external choices will be preserved."))
        }
      }
      if supported && !(activeFields.isEmpty && global?["Type"] as? String == "linked") {
        if globalEntry != nil {
          if let global {
            let choiceKeys: Set<String> = ["Desktop", "Idle", "Linked", "Type"]
            original = original.filter { choiceKeys.contains($0.key) }
              .merging(global.filter { !choiceKeys.contains($0.key) }) { _, new in new }
          }
          var expanded = Self.separatedLinked(original)
          for key in activeFields.subtracting(previous) {
            expanded[key] = restored[key]
          }
          if (expanded as NSDictionary) != (Self.separatedLinked(original) as NSDictionary) {
            original = Self.globalNode(expanded) ?? [:]
          }
        }
        if global == nil {
          restored = original.filter { !["Desktop", "Idle", "Linked", "Type"].contains($0.key) }
        }
        for key in previous.subtracting(activeFields) where restored[key] == nil {
          restored[key] = Self.separatedLinked(original)[key]
        }
        for key in activeFields { restored.removeValue(forKey: key) }
        var replacement = Self.globalNode(restored)
        if let node = replacement { replacement = Self.relinked(node, original: original) }
        // Preserve empty native nodes and inactive metadata verbatim on recovery.
        if activeFields.isEmpty,
          (replacement as NSDictionary?) == (Self.globalNode(Self.separatedLinked(original)) as NSDictionary?)
        {
          replacement = !original.isEmpty || wasPresent ? original : nil
        }
        if (global as NSDictionary?) != (replacement as NSDictionary?) {
          Self.setNode(&root, path: Self.globalPath, value: replacement)
          changed = true
        }
      }
      if !activeFields.isEmpty {
        let kept = globalEntry.flatMap {
          (originals[$0.path] as NSDictionary?) == (original as NSDictionary) ? $0.original : nil
        }
        let entry = Entry(
          path: Self.globalPath, original: try kept ?? Self.encode(original),
          created: globalEntry?.created ?? (global == nil), fields: activeFields.sorted(),
          typeOwned: false, globalWasPresent: wasPresent)
        try record(entry, original: original)
        retained.append(entry)
      }
    }
    for entry in entries where entry.path != Self.globalPath {
      try reconcile(entry, path: entry.path, observeOnly: entry.observeOnly == true)
    }
    // New Spaces may inherit copied choices just before one mode is disabled.
    // Restore only that mode, including unjournaled Defaults, while the other
    // mode and all foreign choices remain untouched.
    let oldFallbackFields = entries.filter { $0.observeOnly == true }
      .reduce(into: Set<String>()) { $0.formUnion($1.ownedFields) }
    let topEntries = entries.filter { $0.path.count == 2 && $0.path[0] == "Displays" }
    for space in spaces.keys.sorted() {
      let discovered = [(["Spaces", space, "Default"], oldFallbackFields.subtracting(activeFields))]
        + topEntries.map {
          (["Spaces", space, "Displays", $0.path[1]],
            $0.ownedFields.subtracting(desiredFields($0.path, observeOnly: false)))
        }
      for (path, fields) in discovered where !entryPaths.contains(path) {
        guard var node = Self.node(root, path: path) else { continue }
        let copied = fields.filter { Self.owns(node[$0]) }
        guard !copied.isEmpty else { continue }
        let original = try Self.restorationOriginal(
          node, path: path, root: root, fields: copied, journaled: journaledOriginal)
          .filter { copied.contains($0.key) }
        let entry = Entry(
          path: path, original: try Self.encode(original), created: false,
          observeOnly: path.last == "Default", fields: copied.sorted(), typeOwned: false)
        try record(entry, original: original)
        for key in copied { node[key] = original[key] }
        Self.setNode(&root, path: path, value: node)
        changed = true
      }
    }
    for path in fallbackPaths
    where !activeFields.isEmpty && !entryPaths.contains(path) {
      try reconcile(nil, path: path, observeOnly: true)
    }
    for path in paths where !entryPaths.contains(path) {
      try reconcile(nil, path: path, observeOnly: false)
    }
    if changed {
      try persistEntries(recovery)
      guard try Data(contentsOf: storeURL) == bytes else {
        // Nothing was written. The union stays on disk for recovery, but the next attempt must
        // not count the fields this one was about to take as ours: it would read them as
        // changed outside the app.
        entries = priorEntries
        throw LockScreenWallpaperFailure(
          message:
            String(localized: "The system wallpaper changed during native selection. Please retry; no concurrent changes were overwritten."),
          reason: .transient)
      }
      if let coordinator {
        try coordinator.replace(Self.encode(root), expected: bytes)
      } else {
        try Self.encode(root).write(to: storeURL, options: .atomic)
      }
      restartPending = true
    }
    if restartPending {
      try await reload()
      restartPending = false
    }
    let unchanged = !changed && retained == entries
    // Save relinquished fields before pruning the write-ahead journal. A failed archive
    // write leaves that journal intact; a failed prune leaves both copies recoverable.
    try archiveRemovedEntries(retained, archived: archived)
    try persistEntries(retained)
    if unchanged { settled = request }
  }

  private func persistEntries(_ next: [Entry]) throws {
    // Adoption changes memory before the union is saved. Keep it pending across a failed
    // write so a retry cannot mistake those fields for an already-persisted journal.
    guard readoptionNeedsPersistence || next != entries || hasPersistedJournal != !next.isEmpty
    else { return }
    let data = try (next.isEmpty ? nil : PropertyListEncoder().encode(next))
    try persistJournal(journalURL, data)
    readoptionNeedsPersistence = false
    entries = next
    hasPersistedJournal = !next.isEmpty
  }

  static func persistJournalFile(_ url: URL, _ data: Data?) throws {
    if let data {
      try FileManager.default.createDirectory(
        at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
      try data.write(to: url, options: .atomic)
    } else if FileManager.default.fileExists(atPath: url.path) {
      try FileManager.default.removeItem(at: url)
    }
  }

  /// A pruned journal, kept for `readoptedEntries`.
  private static func restoredJournalURL(_ journal: URL) -> URL {
    journal.deletingLastPathComponent().appendingPathComponent("restored-" + journal.lastPathComponent)
  }

  private func readArchivedEntries() -> [Entry] {
    guard let data = try? Data(contentsOf: Self.restoredJournalURL(journalURL)),
      let archived = try? PropertyListDecoder().decode([Entry].self, from: data)
    else { return [] }
    // A malformed archive is optional recovery evidence, never a reason to trap.
    guard Set(archived.map(\.path)).count == archived.count else { return [] }
    return archived
  }

  private func archiveRemovedEntries(_ next: [Entry], archived: [Entry]) throws {
    let nextFields = Dictionary(uniqueKeysWithValues: next.map { ($0.path, $0.ownedFields) })
    var saved = Dictionary(uniqueKeysWithValues: archived.map { ($0.path, $0) })
    var removed = false
    for entry in entries {
      let fields = entry.ownedFields.subtracting(nextFields[entry.path] ?? [])
      guard !fields.isEmpty else { continue }
      removed = true
      var released = entry
      released.fields = fields.sorted()
      saved[entry.path] = try Self.merging(saved[entry.path], into: released)
    }
    guard removed else { return }
    let combined = saved.values.sorted { $0.path.lexicographicallyPrecedes($1.path) }
    try persistArchive(Self.restoredJournalURL(journalURL), PropertyListEncoder().encode(combined))
  }

  /// Global entries retain a complete baseline; display entries retain only owned fields.
  /// Keep the newer baseline and metadata, filling only missing display ownership.
  private static func merging(_ older: Entry?, into newer: Entry) throws -> Entry {
    guard let older else { return newer }
    let extra = older.ownedFields.subtracting(newer.ownedFields)
    guard !extra.isEmpty else { return newer }
    var result = newer
    result.fields = newer.ownedFields.union(extra).sorted()
    // An unowned global choice (even an absent one) is newer recovery evidence too.
    if newer.path == globalPath { return result }
    guard let previous = try PropertyListSerialization.propertyList(from: older.original, format: nil)
      as? [String: Any],
      let latest = try PropertyListSerialization.propertyList(from: newer.original, format: nil)
        as? [String: Any]
    else {
      throw LockScreenWallpaperFailure(
        message: String(localized: "The native wallpaper restoration journal is invalid."))
    }
    var original = latest
    for key in extra { original[key] = previous[key] }
    result.original = try encode(original)
    return result
  }

  /// WallpaperAgent may write an old snapshot over either a partial or complete restore.
  /// Recover each app-written field independently; active originals and manual choices win.
  private func readoptedEntries(_ root: [String: Any], archived: [Entry]) throws -> [Entry] {
    var recovered = Dictionary(uniqueKeysWithValues: entries.map { ($0.path, $0) })
    var takenFields: Set<String> = []
    for entry in archived where entry.path != Self.globalPath {
      guard let node = Self.node(root, path: entry.path) else { continue }
      let active = recovered[entry.path]?.ownedFields ?? []
      let fields = entry.ownedFields.subtracting(active).filter {
        Self.ownsRevisionedSelection(node[$0])
      }
      guard !fields.isEmpty else { continue }
      var taken = entry
      taken.fields = fields.sorted()
      takenFields.formUnion(fields)
      if let current = recovered[entry.path] {
        recovered[entry.path] = try Self.merging(taken, into: current)
      } else {
        recovered[entry.path] = taken
      }
    }
    if var entry = archived.first(where: { $0.path == Self.globalPath }), !takenFields.isEmpty {
      let global = Self.separatedLinked(Self.node(root, path: Self.globalPath) ?? [:])
      let active = recovered[Self.globalPath]?.ownedFields ?? []
      entry.fields = entry.ownedFields.intersection(takenFields).subtracting(active)
        .filter { global[$0] == nil }.sorted()
      if !entry.ownedFields.isEmpty {
        if let current = recovered[Self.globalPath] {
          recovered[Self.globalPath] = try Self.merging(entry, into: current)
        } else {
          recovered[Self.globalPath] = entry
        }
      }
    }
    // Keep the live journal's order so unchanged reconciliation remains a no-op.
    let activePaths = Set(entries.map(\.path))
    return entries.compactMap { recovered[$0.path] }
      + recovered.values.filter { !activePaths.contains($0.path) }
        .sorted { $0.path.lexicographicallyPrecedes($1.path) }
  }

  /// A fallback that macOS overwrote with a copy of this extension's selection
  /// still has its native choice in the journal, so `journaled` is consulted
  /// after the live value: a Space created after that copy, a full-screen
  /// app's included, would otherwise have no fallback left at all.
  private static func restorationOriginal(
    _ node: [String: Any], path: [String], root: [String: Any], fields: Set<String>,
    journaled: ([String]) -> [String: Any]?
  ) throws -> [String: Any] {
    var original = node
    let fallbackPaths = Self.fallbackPaths(for: path)
    for key in fields.sorted() where owns(node[key]) {
      guard
        let replacement = fallbackPaths
          .filter({ $0 != path })
          .flatMap({ fallback in
            [
              Self.node(root, path: fallback).map(Self.separatedLinked)?[key] as? [String: Any],
              journaled(fallback).map(Self.separatedLinked)?[key] as? [String: Any],
            ].compactMap { $0 }
          })
          .first(where: { value in
            guard !owns(value), let content = value["Content"] as? [String: Any],
              let choices = content["Choices"] as? [[String: Any]], !choices.isEmpty
            else { return false }
            return choices.allSatisfy {
              guard let provider = $0["Provider"] as? String else { return false }
              return !provider.isEmpty && provider != LockScreenConfiguration.extensionIdentifier
            }
          })
      else {
        throw LockScreenWallpaperFailure(
          message:
            String(localized: "A native wallpaper selection has no restoration journal or surviving system fallback. Choose a system wallpaper for this display before enabling native wallpaper animation.")
        )
      }
      original[key] = replacement
    }
    return original
  }

  // `default` is macOS's own linked desktop/saver choice, not an extension
  // from a competing app. Unknown linked providers remain unsupported.
  private static func defaultLinkedChoice(_ node: [String: Any]) -> [String: Any]? {
    guard node["Type"] as? String == "linked",
      let linked = node["Linked"] as? [String: Any],
      let content = linked["Content"] as? [String: Any],
      let choices = content["Choices"] as? [[String: Any]], !choices.isEmpty,
      choices.allSatisfy({ $0["Provider"] as? String == "default" })
    else { return nil }
    return linked
  }

  private static func separatedLinked(_ node: [String: Any]) -> [String: Any] {
    guard let linked = defaultLinkedChoice(node) else { return node }
    var result = node
    result.removeValue(forKey: "Linked")
    result["Type"] = "individual"
    result["Desktop"] = linked
    result["Idle"] = linked
    return result
  }

  private static func relinked(_ node: [String: Any], original: [String: Any]) -> [String: Any] {
    guard let linked = defaultLinkedChoice(original),
      node["Type"] as? String == "individual",
      ["Desktop", "Idle"].allSatisfy({ (node[$0] as? NSDictionary) == (linked as NSDictionary) })
    else { return node }
    var result = node
    result.removeValue(forKey: "Desktop")
    result.removeValue(forKey: "Idle")
    result["Type"] = "linked"
    result["Linked"] = linked
    return result
  }

  private static func globalNode(_ node: [String: Any]) -> [String: Any]? {
    var result = node
    switch (node["Desktop"] != nil, node["Idle"] != nil) {
    case (true, true): result["Type"] = "individual"
    case (true, false): result["Type"] = "desktop"
    case (false, true): result["Type"] = "idle"
    case (false, false): return nil
    }
    return result
  }

  private static func fallbackPaths(for path: [String]) -> [[String]] {
    var paths: [[String]] = []
    if path.count == 4, path[0] == "Spaces" {
      paths.append(["Displays", path[3]])
      paths.append(["Spaces", path[1], "Default"])
    }
    return paths + [["SystemDefault"], ["AllSpacesAndDisplays"]]
  }

  private static func selection(revision: String?) throws -> [String: Any] {
    [
      "Content": [
        "Choices": [
          [
            "Provider": LockScreenConfiguration.extensionIdentifier,
            "Configuration": Data((revision.map { "current:" + $0 } ?? "current").utf8),
            "Files": [String](),
          ]
        ],
        "Shuffle": "$null", "EncodedOptionValues": try encode(["values": [String: Any]()]),
      ],
      "LastSet": Date(), "LastUse": Date(),
    ]
  }

  private static func owns(_ value: Any?) -> Bool {
    guard let selection = value as? [String: Any],
      let content = selection["Content"] as? [String: Any],
      let choices = content["Choices"] as? [[String: Any]], choices.count == 1
    else { return false }
    return choices[0]["Provider"] as? String == LockScreenConfiguration.extensionIdentifier
  }

  /// Only the service writes revisioned selections; System Settings offers plain `current`.
  private static func ownsRevisionedSelection(_ value: Any?) -> Bool {
    guard owns(value), let selection = value as? [String: Any],
      let content = selection["Content"] as? [String: Any],
      let choices = content["Choices"] as? [[String: Any]],
      let data = choices.first?["Configuration"] as? Data,
      let configuration = String(data: data, encoding: .utf8)
    else { return false }
    return configuration.hasPrefix("current:") && configuration.count > "current:".count
  }

  /// Swift dictionaries iterate in a per-instance order, so equal values can encode to
  /// different bytes. Compare decoded values, or keep bytes already journaled.
  private static func encode(_ value: Any) throws -> Data {
    try PropertyListSerialization.data(fromPropertyList: value, format: .binary, options: 0)
  }

  /// Identifies one version of a file: an atomic replacement gets a new inode, and any
  /// write moves the change time, which user space cannot set back.
  private static func storeVersion(_ url: URL) -> [Int]? {
    var info = stat()
    guard stat(url.path, &info) == 0 else { return nil }
    return [
      Int(info.st_dev), Int(truncatingIfNeeded: info.st_ino), Int(info.st_size),
      info.st_mtimespec.tv_sec, info.st_mtimespec.tv_nsec,
      info.st_ctimespec.tv_sec, info.st_ctimespec.tv_nsec,
    ]
  }

  private static func node(_ root: [String: Any], path: [String]) -> [String: Any]? {
    var node = root
    for key in path {
      guard let child = node[key] as? [String: Any] else { return nil }
      node = child
    }
    return node
  }

  private static func setNode(_ root: inout [String: Any], path: [String], value: [String: Any]?) {
    guard let key = path.first else { return }
    if path.count == 1 {
      root[key] = value
      return
    }
    var child = root.removeValue(forKey: key) as? [String: Any] ?? [:]
    setNode(&child, path: Array(path.dropFirst()), value: value)
    root[key] = child
  }

}
