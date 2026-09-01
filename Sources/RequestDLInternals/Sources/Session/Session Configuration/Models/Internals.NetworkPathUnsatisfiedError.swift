//
// See LICENSE for this package's licensing information.
//

extension Internals {

    /// Thrown by ``Internals/NetworkPathGate`` when the current network path does not satisfy
    /// the caller's constraints and either waiting is disabled, or the wait was cancelled before
    /// a satisfying path arrived.
    ///
    /// Rewrapped into the public, documented `NetworkAvailabilityError` at the one call site in
    /// `RequestDL` that can throw it (`RawTask.swift`), the same way `Internals.SecureFileLoadError`
    /// becomes `SecureFileError`.
    package struct NetworkPathUnsatisfiedError: Error, Sendable {

        package enum Reason: Sendable, Hashable {
            case noConnection
            case cellularNotAllowed
            case expensiveNotAllowed
            case constrainedNotAllowed
        }

        // MARK: - Internal properties

        package let reason: Reason
        package let waitedForConnectivity: Bool

        // MARK: - Inits

        package init(reason: Reason, waitedForConnectivity: Bool) {
            self.reason = reason
            self.waitedForConnectivity = waitedForConnectivity
        }
    }
}
