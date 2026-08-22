//
// See LICENSE for this package's licensing information.
//

#if canImport(UIKit) || canImport(AppKit)

/// An error thrown when a response's data could not be decoded into a ``PlatformImage``.
public struct RDLImageDecodingError: TaskError {

    /// Creates the error.
    public init() {}
}

#endif
