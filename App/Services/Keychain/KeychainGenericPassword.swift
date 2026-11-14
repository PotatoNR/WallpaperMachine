import Foundation
import Security

/// The keychain calls `KeychainGenericPassword` makes. Injected so tests never touch the keychain.
protocol KeychainItemCalls: Sendable {
    func copyMatching(_ query: [String: Any]) -> (status: OSStatus, item: CFTypeRef?)
    func update(_ query: [String: Any], with attributes: [String: Any]) -> OSStatus
    func add(_ attributes: [String: Any]) -> OSStatus
    func delete(_ query: [String: Any]) -> OSStatus
}

/// The Security framework's calls, on the user's login keychain.
struct SystemKeychain: KeychainItemCalls {
    func copyMatching(_ query: [String: Any]) -> (status: OSStatus, item: CFTypeRef?) {
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        return (status, item)
    }

    func update(_ query: [String: Any], with attributes: [String: Any]) -> OSStatus {
        SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
    }

    func add(_ attributes: [String: Any]) -> OSStatus {
        SecItemAdd(attributes as CFDictionary, nil)
    }

    func delete(_ query: [String: Any]) -> OSStatus {
        SecItemDelete(query as CFDictionary)
    }
}

/// The keychain answered `status` instead of doing what was asked.
struct KeychainFailure: Error, Equatable, CustomStringConvertible {
    let status: OSStatus
    var description: String { "\(status)" }
}

/// The keychain kept the saved sign-in it was asked to remove, deleting it and emptying it both
/// refused; `reason` is macOS's own wording.
struct KeychainRemovalFailed: LocalizedError {
    let reason: String
    var errorDescription: String? { reason }
}

/// One generic password in the user's login keychain, found by service and account: how the pixiv
/// and Steam Community sign-ins are kept between launches.
///
/// macOS keeps such an item in the keychain partition of the build that saved it, and asks for the
/// login keychain password before another build may read it; **Always Allow** adds that build's
/// partition. Changing the data never asks, and deleting the item is refused to another build,
/// which is why `remove()` empties what it cannot delete.
/// Releases signed with the Developer ID share their team's partition, so an update reads what the
/// version before it saved without asking. Any other build has a partition of its own (its code
/// hash): a locally built, ad-hoc signed app, and each release signed with the project certificate
/// (1.0.2 to 1.8.2), which therefore asked after every update.
struct KeychainGenericPassword: Sendable {
    let service: String
    let account: String
    /// The item's name in Keychain Access.
    let label: String
    private let calls: any KeychainItemCalls

    init(service: String, account: String, label: String, calls: any KeychainItemCalls = SystemKeychain()) {
        self.service = service
        self.account = account
        self.label = label
        self.calls = calls
    }

    private var query: [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
    }

    /// The saved data; nil when there is no item. Any other answer is thrown.
    func read() throws -> Data? {
        var request = query
        request[kSecReturnData as String] = true
        request[kSecMatchLimit as String] = kSecMatchLimitOne
        let answer = calls.copyMatching(request)
        switch answer.status {
        case errSecSuccess: return answer.item as? Data
        case errSecItemNotFound: return nil
        default: throw KeychainFailure(status: answer.status)
        }
    }

    /// Saves `data`, changing the item or adding it when there is none. Any other answer is thrown
    /// as it is and the item is left alone: deleting it to add it again cannot succeed where
    /// changing it failed (the keychain refuses another build's delete outright), and would only
    /// report a duplicate item in place of the reason.
    func write(_ data: Data) throws {
        var status = calls.update(query, with: [kSecValueData as String: data])
        if status == errSecItemNotFound {
            var item = query
            item[kSecValueData as String] = data
            item[kSecAttrLabel as String] = label
            status = calls.add(item)
        }
        guard status == errSecSuccess else { throw KeychainFailure(status: status) }
    }

    /// Deletes the item, or empties it when the keychain refuses: macOS will not let one build
    /// delete what another saved, but lets it change the data, and an emptied item holds nothing
    /// a later read could sign in with. One that is not there is not a failure. Throws
    /// `KeychainRemovalFailed` only when the data stays, so a sign-out never reports what did
    /// not happen.
    func remove() throws {
        let deleted = calls.delete(query)
        guard deleted != errSecSuccess, deleted != errSecItemNotFound else { return }
        let emptied = calls.update(query, with: [kSecValueData as String: Data()])
        guard emptied != errSecSuccess, emptied != errSecItemNotFound else {
            AppLog.info("\(label) could not be deleted from the keychain (\(deleted)); it was emptied instead")
            return
        }
        AppLog.warn("\(label) could not be removed from the keychain (\(deleted), then \(emptied))")
        throw KeychainRemovalFailed(reason: SecCopyErrorMessageString(emptied, nil) as String? ?? "\(emptied)")
    }
}
