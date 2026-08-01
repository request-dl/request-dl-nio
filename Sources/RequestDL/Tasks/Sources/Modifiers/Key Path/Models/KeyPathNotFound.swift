//
// See LICENSE for this package's licensing information.
//

#if canImport(FoundationEssentials)
import protocol FoundationEssentials.LocalizedError
#else
import protocol Foundation.LocalizedError
#endif

/// A error type representing a validation error due to a missing keyPath in `RequestTask` result data.
/// Conforms to the `TaskError` protocol.
public struct KeyPathNotFound: TaskError, LocalizedError {

    // MARK: - Public properties

    public var errorDescription: String? {
        "Unable to resolve the KeyPath.\(keyPath) in the current Task result"
    }

    // MARK: - Internal properties

    let keyPath: String
}
