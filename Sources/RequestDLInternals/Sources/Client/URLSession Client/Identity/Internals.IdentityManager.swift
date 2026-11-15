//
// See LICENSE for this package's licensing information.
//

#if canImport(Darwin)

import Security
import SwiftAsyncStream

extension Internals {

    /// One `SecIdentity` built by
    /// `Internals.RawBytesIdentityBuilder.makeIdentity(certificateDER:privateKeyDER:)`,
    /// reference-counted against every other `IdentityHandle` built for the same certificate/key
    /// pair.
    ///
    /// Multiple independently-built `Internals.Client`/`Internals.URLSessionIdentityPolicy`
    /// instances configured with the same mTLS identity share one Keychain-backed `SecIdentity`
    /// and one pair of Keychain items, rather than the first to deallocate deleting items the
    /// others still depend on.
    ///
    /// The underlying Keychain items are removed only once every live `IdentityHandle` for that
    /// pair has deinitialized; see ``IdentityManager``.
    package final class IdentityHandle: @unchecked Sendable {
        package let identity: SecIdentity
        fileprivate let label: String
        fileprivate let keyLabel: String

        /// The certificate this handle's build put in the Keychain, when it did (see
        /// `RawBytesIdentityBuilder.StoredIdentity/addedCertificate`). It is what the handle
        /// deletes the certificate item by.
        ///
        /// Only read and written under ``IdentityManager``'s lock: a release that finds this
        /// handle already registered for its label hands the certificate over (see `release`).
        fileprivate var ownedCertificate: SecCertificate?

        /// Which Keychain the items behind `identity` were stored in, so that releasing the
        /// handle deletes from that same one. On macOS the build can land in either, depending
        /// on whether the process carries the Keychain Sharing entitlement.
        fileprivate let useDataProtectionKeychain: Bool

        private let manager: IdentityManager

        fileprivate init(
            identity: SecIdentity,
            label: String,
            keyLabel: String,
            ownedCertificate: SecCertificate?,
            useDataProtectionKeychain: Bool,
            manager: IdentityManager
        ) {
            self.identity = identity
            self.label = label
            self.keyLabel = keyLabel
            self.ownedCertificate = ownedCertificate
            self.useDataProtectionKeychain = useDataProtectionKeychain
            self.manager = manager
        }

        deinit {
            manager.release(
                label: label,
                keyLabel: keyLabel,
                ownedCertificate: ownedCertificate,
                useDataProtectionKeychain: useDataProtectionKeychain
            )
        }
    }

    /// Deduplicates ``IdentityHandle``s by their content-derived Keychain label, process-wide. The
    /// labels name the Keychain's own items (a certificate paired with a key by the key's public
    /// hash), so two handles share a label exactly when they share items, however the key's
    /// bytes were encoded.
    ///
    /// Only this process's handles are counted. Another process of the same user that builds an
    /// identity for the same certificate and key shares those Keychain items (the macOS login
    /// keychain is shared), and nothing here can see it: whichever process releases last is not
    /// necessarily the one that is, and the first to release removes the key under the other.
    /// `Internals.RawBytesIdentityBuilder.makeIdentity(certificateDER:privateKeyDER:)` and
    /// `IdentityHandle.deinit` are this type's only two callers, and both take the same lock.
    ///
    /// A build for a label and the teardown of that label's last surviving handle can therefore
    /// never interleave: one Keychain round trip (add or delete) always finishes before the next
    /// begins.
    ///
    /// That ordering alone isn't enough to make teardown safe, though. Swift zeroes a `weak var`
    /// as soon as the referenced object's strong refcount hits zero, independently of `lock`,
    /// before the dying `IdentityHandle`'s own `deinit` gets a chance to even ask for it. So a
    /// second caller building for the same label can win the lock first, see the already-zeroed
    /// weak reference, and register a brand new handle for that label before the original
    /// handle's `release(label:)` ever runs.
    ///
    /// `release(label:)` only deletes the Keychain items, and only then clears the registry slot,
    /// when nothing live is registered for the label at that point. That lets it tell "nobody
    /// rebuilt while I was waiting for the lock" apart from "a new handle already owns this
    /// label," and never delete out from under the latter.
    package final class IdentityManager: @unchecked Sendable {
        package static let shared = IdentityManager(deleteItems: IdentityManager.deleteKeychainItems)

        private let lock = Lock()
        private var live: [String: Weak<IdentityHandle>] = [:]

        /// How many handles are alive per key label. The Keychain keeps one item per key however
        /// many certificates it is paired with, so identities for one key share one item, which
        /// goes away with the last of them and not with the one that happened to add it.
        private var keyUsers: [String: Int] = [:]
        private let deleteItems:
            @Sendable (_ label: String, _ certificate: SecCertificate?, _ useDataProtectionKeychain: Bool) -> Void

        /// - Parameter deleteItems: Removes the key and certificate items stored under `label`
        ///   from the given Keychain, and `certificate`'s own item when there is one. Only a test
        ///   replaces it, to observe which Keychain a release targets.
        init(
            deleteItems:
                @escaping @Sendable (
                    _ label: String,
                    _ certificate: SecCertificate?,
                    _ useDataProtectionKeychain: Bool
                ) -> Void
        ) {
            self.deleteItems = deleteItems
        }

        /// Returns the already-live handle for `label`, if some other caller still holds a
        /// strong reference to one, without touching the Keychain again. Otherwise runs `build`
        /// (the actual Keychain round trip) and registers its result.
        ///
        /// `build` also reports which Keychain it stored the items in, and the certificate it
        /// added there, if it was the one to add it.
        ///
        /// - Parameter keyLabel: The label of the key item, when it is shared with the identities
        ///   of other certificates. It is `label` when `nil`.
        package func handle(
            for label: String,
            keyLabel: String? = nil,
            build: () throws -> (
                identity: SecIdentity, useDataProtectionKeychain: Bool, ownedCertificate: SecCertificate?
            )
        ) throws -> IdentityHandle {
            try lock.withLock {
                if let existing = live[label]?.value {
                    return existing
                }

                let keyLabel = keyLabel ?? label
                let built = try build()
                let handle = IdentityHandle(
                    identity: built.identity,
                    label: label,
                    keyLabel: keyLabel,
                    ownedCertificate: built.ownedCertificate,
                    useDataProtectionKeychain: built.useDataProtectionKeychain,
                    manager: self
                )
                live[label] = Weak(handle)
                keyUsers[keyLabel, default: 0] += 1
                return handle
            }
        }

        /// Called once per `IdentityHandle.deinit`. Drops the registry entry and removes both
        /// Keychain items `label` was built from, but only if nothing live is registered for
        /// `label` right now.
        ///
        /// A concurrent `handle(for:build:)` call can have already rebuilt and registered a fresh
        /// handle for the same label between this handle's weak reference zeroing and this call
        /// actually acquiring `lock` (see this type's own doc comment). When that has happened,
        /// the newer handle owns these Keychain items now, and this call must leave both the
        /// registry slot and the Keychain alone.
        ///
        /// The deletion targets the Keychain the releasing handle was built in, not a fixed one:
        /// a signed macOS app stores in the data-protection Keychain, and deleting from the
        /// legacy one would leave the imported private key behind for good.
        func release(
            label: String,
            keyLabel: String,
            ownedCertificate: SecCertificate?,
            useDataProtectionKeychain: Bool
        ) {
            lock.withLock {
                let remainingKeyUsers = (keyUsers[keyLabel] ?? 1) - 1
                keyUsers[keyLabel] = remainingKeyUsers > 0 ? remainingKeyUsers : nil

                guard live[label]?.value == nil else {
                    // The newer handle for this label was built while this one was dying, so it
                    // found the certificate this handle had added "already there" and does not
                    // own it. This is the last reference to it that can delete it: pass it on, or
                    // the certificate stays in the (legacy) keychain for good.
                    if let ownedCertificate, let newer = live[label]?.value, newer.ownedCertificate == nil {
                        newer.ownedCertificate = ownedCertificate
                    }
                    return
                }

                live[label] = nil
                deleteItems(label, ownedCertificate, useDataProtectionKeychain)

                if remainingKeyUsers <= 0, keyLabel != label {
                    deleteItems(keyLabel, nil, useDataProtectionKeychain)
                }
            }
        }

        private static func deleteKeychainItems(
            label: String,
            certificate: SecCertificate?,
            useDataProtectionKeychain: Bool
        ) {
            RawBytesIdentityBuilder.deleteKeychainItems(
                label: label,
                certificate: certificate,
                useDataProtectionKeychain: useDataProtectionKeychain
            )
        }
    }
}

/// A weak reference to a class instance, usable as a dictionary value. `weak var` isn't allowed
/// directly on a dictionary's `Value` generic parameter, so `Internals.IdentityManager` stores
/// one of these per label instead.
private struct Weak<Value: AnyObject> {
    weak var value: Value?

    init(_ value: Value) {
        self.value = value
    }
}

#endif
