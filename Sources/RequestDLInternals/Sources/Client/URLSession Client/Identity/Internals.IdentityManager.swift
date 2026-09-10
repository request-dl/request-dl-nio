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
    /// pair. Multiple independently-built `Internals.Client`/`Internals.URLSessionIdentityPolicy`
    /// instances configured with the same mTLS identity share one Keychain-backed `SecIdentity`
    /// and one pair of Keychain items, rather than the first to deallocate deleting items the
    /// others still depend on.
    ///
    /// The underlying Keychain items are removed only once every live `IdentityHandle` for that
    /// pair has deinitialized -- see ``IdentityManager``.
    package final class IdentityHandle: @unchecked Sendable {
        package let identity: SecIdentity
        fileprivate let label: String

        fileprivate init(identity: SecIdentity, label: String) {
            self.identity = identity
            self.label = label
        }

        deinit {
            IdentityManager.shared.release(label: label)
        }
    }

    /// Deduplicates ``IdentityHandle``s by their content-derived Keychain label, process-wide.
    /// `Internals.RawBytesIdentityBuilder.makeIdentity(certificateDER:privateKeyDER:)` and
    /// `IdentityHandle.deinit` are this type's only two callers, and both take the same lock --
    /// so a build for a label and the teardown of that label's last surviving handle can never
    /// interleave: one Keychain round trip (add or delete) always finishes before the next
    /// begins.
    package final class IdentityManager: @unchecked Sendable {
        package static let shared = IdentityManager()

        private let lock = Lock()
        private var live: [String: Weak<IdentityHandle>] = [:]

        private init() {}

        /// Returns the already-live handle for `label`, if some other caller still holds a
        /// strong reference to one, without touching the Keychain again. Otherwise runs `build`
        /// (the actual Keychain round trip) and registers its result.
        package func handle(
            for label: String,
            build: () throws -> SecIdentity
        ) throws -> IdentityHandle {
            try lock.withLock {
                if let existing = live[label]?.value {
                    return existing
                }

                let identity = try build()
                let handle = IdentityHandle(identity: identity, label: label)
                live[label] = Weak(handle)
                return handle
            }
        }

        /// Called once per `IdentityHandle.deinit`. Drops the (by now stale) registry entry and
        /// removes both Keychain items `label` was built from.
        fileprivate func release(label: String) {
            lock.withLock {
                live[label] = nil

                #if os(macOS)
                let useDataProtectionKeychain = false
                #else
                let useDataProtectionKeychain = true
                #endif

                for itemClass in [kSecClassKey, kSecClassCertificate] {
                    let query: [CFString: Any] = [
                        kSecClass: itemClass,
                        kSecAttrLabel: label,
                        kSecUseDataProtectionKeychain: useDataProtectionKeychain,
                    ]
                    SecItemDelete(query as CFDictionary)
                }
            }
        }
    }
}

/// A weak reference to a class instance, usable as a dictionary value -- `weak var` isn't allowed
/// directly on a dictionary's `Value` generic parameter, so `Internals.IdentityManager` stores
/// one of these per label instead.
private struct Weak<Value: AnyObject> {
    weak var value: Value?

    init(_ value: Value) {
        self.value = value
    }
}

#endif
