//
// See LICENSE for this package's licensing information.
//

#if canImport(FoundationEssentials)
import FoundationEssentials
#else
// import protocol Foundation.LocalizedError
#endif

/// An error type representing a request with no response.
public struct RequestFailureError: LocalizedError {

    public var errorDescription: String? {
        "The request received no response."
    }

    /// Creates the error.
    public init() {}
}
