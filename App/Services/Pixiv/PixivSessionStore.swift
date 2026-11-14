import Foundation

/// Keeps the pixiv session between launches. Injected so tests never touch the keychain.
protocol PixivSessionStoring: Sendable {
    /// The saved session; nil when there is none or it cannot be read.
    func load() -> String?
    func save(_ session: String) throws
    /// Throws when the saved session stays: a log-out must not report what did not happen.
    func remove() throws
}

/// The session as a generic password in the user's login keychain (`KeychainGenericPassword`
/// says when macOS asks before handing it over).
struct KeychainPixivSessionStore: PixivSessionStoring {
    static let service = "app.wallpapermachine.pixiv"
    static let account = "session"

    private let item: KeychainGenericPassword

    init(calls: any KeychainItemCalls = SystemKeychain()) {
        item = KeychainGenericPassword(
            service: Self.service, account: Self.account, label: "WallpaperMachine pixiv sign-in", calls: calls)
    }

    func load() -> String? {
        let data: Data?
        do {
            data = try item.read()
        } catch {
            AppLog.warn("pixiv sign-in could not be read from the keychain (\(error))")
            return nil
        }
        guard let data, let session = String(data: data, encoding: .utf8), PixivService.isSessionValue(session)
        else { return nil }
        return session
    }

    func save(_ session: String) throws {
        do {
            try item.write(Data(session.utf8))
        } catch {
            AppLog.warn("pixiv sign-in could not be saved in the keychain (\(error))")
            throw PixivFailure(code: .notSaved)
        }
    }

    /// Deletes the item, or empties it, which loads as no session (`KeychainGenericPassword.remove`).
    func remove() throws {
        try item.remove()
    }
}
