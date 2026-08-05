//
// See LICENSE for this package's licensing information.
//

#if canImport(Darwin)
import Foundation

/// A error type representing a validation error due to a unexpected `RequestTask` result data.
/// Conforms to the `TaskError` protocol.
@available(*, deprecated, message: "Use '.decode(_:decoder:)' with a Codable type instead.")
public struct KeyPathInvalidDataError: TaskError, LocalizedError {
    public var errorDescription: String? {
        "Unable to read the current data result on Task.keyPath() in key-value format"
    }
}
#endif
