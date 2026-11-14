import Foundation
import Translation

/// The system's Translation framework, which translates on this Mac.
///
/// From macOS 26 a translation between downloaded languages runs on a session made here
/// (`TranslationSession(installedSource:target:)`), which can never ask for a download. Before
/// macOS 26 it borrows a session from the panel's `.translationTask` through `sessionHost`, and a
/// download always does, because only such a session can show the system's download prompt.
@MainActor
final class SystemTranslation: OnDeviceTranslating {
    let sessionHost: TranslationSessionHost

    /// The sessions made for downloaded languages, by source and target, reused across searches.
    private var installedSessions: [String: TranslationSession] = [:]

    init(sessionHost: TranslationSessionHost? = nil) {
        self.sessionHost = sessionHost ?? TranslationSessionHost()
    }

    func availability(from source: Locale.Language, to target: Locale.Language) async
        -> OnDeviceTranslationAvailability
    {
        switch await LanguageAvailability().status(from: source, to: target) {
        case .installed: .installed
        case .supported: .downloadable
        case .unsupported: .unsupported
        @unknown default: .unsupported
        }
    }

    func translate(_ text: String, from source: Locale.Language, to target: Locale.Language)
        async throws -> String
    {
#if compiler(>=6.2)
        guard #available(macOS 26.0, *) else {
            return try await sessionHost.translate(text, from: source, to: target)
        }
        let key = "\(source.maximalIdentifier)>\(target.maximalIdentifier)"
        let session = installedSessions[key] ?? TranslationSession(installedSource: source, target: target)
        installedSessions[key] = session
        do {
            return try await session.translatedText(text)
        } catch {
            // A language removed since, or a session the framework ended: the next one starts afresh.
            installedSessions[key] = nil
            throw error
        }
#else
        // Intel build note: `TranslationSession(installedSource:target:)` arrived with the
        // macOS 26 SDK and has no declaration in the macOS 15 SDK, so Xcode 16.4 cannot
        // compile that branch at all. Every translation borrows the panel's session instead,
        // which is what this app does on macOS 15 anyway.
        _ = installedSessions
        return try await sessionHost.translate(text, from: source, to: target)
#endif
    }

    func download(from source: Locale.Language, to target: Locale.Language) async throws {
        try await sessionHost.prepare(from: source, to: target)
    }
}
