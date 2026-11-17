//
// See LICENSE for this package's licensing information.
//

#if canImport(Darwin)

import Dispatch
import Security

#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif

extension Internals {

    /// One Keychain item, as much of it as the cleanup of `LegacyIdentityItems` looks at.
    package struct KeychainItem: Equatable, Sendable {

        package enum ItemClass: Equatable, Sendable {
            case key
            case certificate
            case other
        }

        package var itemClass: ItemClass
        package var label: String?
        package var applicationLabel: Data?
        package var creationDate: Date?

        /// What names this very row and no other (`kSecValuePersistentRef`), taken from the same
        /// query that read the other attributes.
        package var persistentRef: Data

        package init(
            itemClass: ItemClass,
            label: String?,
            applicationLabel: Data?,
            creationDate: Date?,
            persistentRef: Data
        ) {
            self.itemClass = itemClass
            self.label = label
            self.applicationLabel = applicationLabel
            self.creationDate = creationDate
            self.persistentRef = persistentRef
        }
    }

    /// A Keychain call that did not succeed, with the `OSStatus` it answered.
    package struct KeychainFailure: Swift.Error, Equatable, Sendable {
        package var status: OSStatus

        package init(status: OSStatus) {
            self.status = status
        }

        /// The answers that mean Security would need the user (a prompt, a passcode, a locked
        /// device): the cleanup stops at the first one instead of insisting.
        fileprivate var needsTheUser: Bool {
            [
                errSecInteractionNotAllowed,
                errSecAuthFailed,
                errSecUserCanceled,
                errSecInteractionRequired,
                errSecNotAvailable,
            ].contains(status)
        }
    }

    /// The only two things the cleanup asks of the Keychain, so a test can stand in for it.
    package protocol KeychainItemStore: Sendable {

        /// The private keys this process can see. Attributes and persistent references only, never
        /// the secret.
        func queryKeys() throws -> [KeychainItem]

        /// Deletes exactly the row `persistentRef` names.
        func delete(persistentRef: Data) throws
    }

    /// The real Keychain: `SecItemCopyMatching` and `SecItemDelete`, in one of the two keychains.
    package struct SystemKeychainItemStore: KeychainItemStore {

        package var useDataProtectionKeychain: Bool

        package init(useDataProtectionKeychain: Bool) {
            self.useDataProtectionKeychain = useDataProtectionKeychain
        }

        package func queryKeys() throws -> [KeychainItem] {
            let query: [CFString: Any] = [
                kSecClass: kSecClassKey,
                kSecUseDataProtectionKeychain: useDataProtectionKeychain,
                kSecMatchLimit: kSecMatchLimitAll,
                kSecReturnAttributes: true,
                kSecReturnPersistentRef: true,
            ]

            var result: CFTypeRef?
            let status = SecItemCopyMatching(query as CFDictionary, &result)

            switch status {
            case errSecSuccess:
                break
            case errSecItemNotFound:
                return []
            default:
                throw KeychainFailure(status: status)
            }

            guard let rows = result as? [[String: Any]] else {
                return []
            }

            return rows.compactMap { row in
                // A row with no persistent reference cannot be deleted one by one: it is not ours
                // to touch.
                guard let persistentRef = row[kSecValuePersistentRef as String] as? Data else {
                    return nil
                }

                return KeychainItem(
                    itemClass: .key,
                    label: row[kSecAttrLabel as String] as? String,
                    applicationLabel: row[kSecAttrApplicationLabel as String] as? Data,
                    creationDate: row[kSecAttrCreationDate as String] as? Date,
                    persistentRef: persistentRef
                )
            }
        }

        package func delete(persistentRef: Data) throws {
            let query: [CFString: Any] = [
                kSecClass: kSecClassKey,
                kSecUseDataProtectionKeychain: useDataProtectionKeychain,
                kSecValuePersistentRef: persistentRef,
            ]

            let status = SecItemDelete(query as CFDictionary)
            guard status == errSecSuccess else {
                throw KeychainFailure(status: status)
            }
        }
    }

    /// Cleans up what earlier versions of this library left in the Keychain.
    ///
    /// Those versions stored the private key of the mTLS client identity (a `kSecClassKey` item
    /// labelled `RequestDL.mtls.key.<hex>`), and a process that died before it could delete the
    /// item left it behind. Nothing stores such an item any more (`makeIdentity` builds the
    /// identity in memory), so what is left is not read by this version.
    ///
    /// This only ever removes an item that is surely ours, surely old, and that it can remove
    /// without asking the user for anything. Anything else stays where it is, which is why none of
    /// this throws: it is best effort, and a failure only means that the item stays.
    ///
    /// - Only keys (certificates are public data, an equal certificate can be the user's, and
    ///   the legacy macOS keychain does not even keep a label for them);
    /// - only a label this library wrote (see ``isLibraryKeyLabel(_:applicationLabel:)``);
    /// - only in the data-protection keychain in production, where this process sees nothing but
    ///   its own access groups. The legacy macOS keychain is shared with every other binary of the
    ///   user, has no creation date to check and no way to tell whose item it is: not cleaned up.
    /// - only an item created more than `minimumAge` ago, with a creation date: an older version of
    ///   this library that is still running (another app of the same team, an extension) may still
    ///   use the item it created minutes ago;
    /// - one item at a time, by the persistent reference of the very row that was inspected.
    package enum LegacyIdentityItems {

        package static let labelPrefix = "RequestDL.mtls.key."

        /// Older than this, an item is not in use by a version of this library that is still
        /// running.
        package static let defaultMinimumAge: TimeInterval = 86_400

        // MARK: - Once per process

        private static let scheduledOnce: Void = {
            // A background queue, not a `Task`: the calls into Security block, and a blocked thread
            // of the cooperative pool is a thread less for the async code of the user. Nothing
            // waits for this, nothing holds the process alive, and a process that exits in the
            // middle of it only leaves the item for the next run.
            DispatchQueue.global(qos: .utility).async {
                _ = removeOrphanedKeys(useDataProtectionKeychain: true, now: Date())
            }
        }()

        /// Starts the cleanup of the data-protection keychain, once per process, whatever the
        /// number of identities built, on any thread. Returns at once.
        package static func scheduleOnce() {
            _ = scheduledOnce
        }

        // MARK: - Rule

        /// Whether `label` is one this library gave to a key.
        ///
        /// - `RequestDL.mtls.key.` and 40 lowercase hex digits, equal to the hex of
        ///   `applicationLabel` (the SHA-1 of the key's own public key): the label of the later
        ///   versions, which the library can prove it made, because it is derived from the item;
        /// - `RequestDL.mtls.key.` and 64 lowercase hex digits (the SHA-256 of the key's DER): the
        ///   label of the first versions that had it, which cannot be checked against the item.
        ///
        /// Anything else is not ours: another length, uppercase, another prefix.
        package static func isLibraryKeyLabel(_ label: String, applicationLabel: Data?) -> Bool {
            let prefix = Array(labelPrefix.utf8)
            let bytes = Array(label.utf8)

            guard bytes.count > prefix.count, bytes.starts(with: prefix) else {
                return false
            }

            let suffix = bytes[prefix.count...]

            guard suffix.allSatisfy({ ($0 >= 0x30 && $0 <= 0x39) || ($0 >= 0x61 && $0 <= 0x66) }) else {
                return false
            }

            switch suffix.count {
            case 40:
                guard let applicationLabel else { return false }
                return Array(hex(applicationLabel).utf8) == Array(suffix)
            case 64:
                return true
            default:
                return false
            }
        }

        private static func hex(_ data: Data) -> String {
            let digits = Array("0123456789abcdef")
            var result = ""
            result.reserveCapacity(data.count * 2)
            for byte in data {
                result.append(digits[Int(byte >> 4)])
                result.append(digits[Int(byte & 0x0F)])
            }
            return result
        }

        // MARK: - Cleanup

        /// Removes the orphaned keys of the Keychain, as described in the type's documentation.
        ///
        /// - Parameters:
        ///   - useDataProtectionKeychain: Production passes `true`. `false` (the legacy macOS
        ///     keychain) exists for tests.
        ///   - now: The moment the age of an item is measured at.
        ///   - minimumAge: How long ago an item must have been created.
        ///   - onlyLabels: Tests only. When set, an item whose label is not in it stays, whatever
        ///     the rule says.
        /// - Returns: How many items were removed. Never throws: any failure leaves the item.
        @discardableResult
        package static func removeOrphanedKeys(
            useDataProtectionKeychain: Bool,
            now: Date,
            minimumAge: TimeInterval = defaultMinimumAge,
            onlyLabels: Set<String>? = nil
        ) -> Int {
            removeOrphanedKeys(
                from: SystemKeychainItemStore(useDataProtectionKeychain: useDataProtectionKeychain),
                now: now,
                minimumAge: minimumAge,
                onlyLabels: onlyLabels
            )
        }

        @discardableResult
        package static func removeOrphanedKeys(
            from store: some KeychainItemStore,
            now: Date,
            minimumAge: TimeInterval = defaultMinimumAge,
            onlyLabels: Set<String>? = nil
        ) -> Int {
            // Without the entitlement (`swift test`, an unsigned process) the query answers
            // `errSecMissingEntitlement`: nothing to do, not an error.
            guard let items = try? store.queryKeys() else {
                return 0
            }

            var removed = 0

            orphans: for item in items where isOrphan(item, now: now, minimumAge: minimumAge, onlyLabels: onlyLabels) {
                do {
                    try store.delete(persistentRef: item.persistentRef)
                    removed += 1
                } catch let failure as KeychainFailure where failure.needsTheUser {
                    // Security wants the user for this: not insisting on this item, nor on any
                    // other.
                    break orphans
                } catch {
                    // Gone already, or refused: the item stays, and the next one is tried.
                    continue
                }
            }

            return removed
        }

        private static func isOrphan(
            _ item: KeychainItem,
            now: Date,
            minimumAge: TimeInterval,
            onlyLabels: Set<String>?
        ) -> Bool {
            guard item.itemClass == .key, let label = item.label else {
                return false
            }

            if let onlyLabels, !onlyLabels.contains(label) {
                return false
            }

            guard isLibraryKeyLabel(label, applicationLabel: item.applicationLabel) else {
                return false
            }

            // No creation date, no deletion. A date in the future is not old either.
            guard let creationDate = item.creationDate, now.timeIntervalSince(creationDate) > minimumAge else {
                return false
            }

            return true
        }
    }
}

#endif
