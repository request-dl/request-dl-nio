//
// See LICENSE for this package's licensing information.
//

#if canImport(Darwin)
// import Foundation

/// A error type representing a validation error due to a missing keyPath in `RequestTask` result data.
/// Conforms to the `TaskError` protocol.
@available(*, deprecated, message: "Use '.decode(_:decoder:)' with a Codable type instead.")
public struct KeyPathNotFound: TaskError, LocalizedError {
    // MARK: - Public properties
    public var errorDescription: String? {
        "Unable to resolve the KeyPath '\(keyPath)' in the current Task result"
    }

    // MARK: - Internal properties
    let keyPath: String
}
#endif
